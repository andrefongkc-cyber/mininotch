import AppKit
import Observation
import ScreenCaptureKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The Answers tab: reads the window in front and answers the questions in it.
///
/// Three steps, all on this Mac. ScreenCaptureKit takes one picture of the frontmost app's front
/// window on the notch's display (the whole display, less MiniNotch, when there is no such window),
/// which needs the Screen Recording permission. Vision reads the text off it. Apple's on-device
/// model (FoundationModels, macOS 26 with Apple Intelligence on) answers what it finds, and the
/// answer is shown as it is written. Nothing is sent anywhere, and neither the picture nor the text
/// is kept: only the answer, until the next one.
@Observable
@MainActor
final class ScreenAnswersService {
    enum Phase: Equatable {
        case idle
        /// Screen Recording is not granted to this copy.
        case needsPermission
        /// Taking the picture and reading the text.
        case reading
        /// The model is writing; `answer` grows.
        case thinking
        case answered
        case failed(String)

        var isBusy: Bool { self == .reading || self == .thinking }
    }

    /// Whether Apple's model can be used here, and if not, why not in words.
    enum ModelAvailability: Equatable {
        case available
        case unavailable(String)
    }

    private(set) var phase: Phase = .idle
    /// The answer so far.
    private(set) var answer = ""
    /// The app whose window was read, for the line above the answer.
    private(set) var sourceName: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    /// The longest text handed to the model. Its context is about 4,000 tokens for the
    /// instructions, the page and the answer together, and a token is three or four characters.
    static let textLimit = 6000

    /// The small on-device model mixes questions up when it answers several at once (it gave a
    /// multiple choice letter to the question above the options), so the page is split into
    /// questions here (`QuestionSplitter`) and each is answered in a session of its own.
    /// Two sets, because telling it about options made it invent a list of them, A to Z, for a
    /// question that had none.
    static let answerInstructions = """
        Answer the question correctly and briefly, in one or two lines. For maths, give the \
        result and the step that gets there. Write plain text, no markdown.
        """

    static let choiceInstructions = """
        The question has answer options. Give the letter and the text of the right option, then \
        at most one line saying why. Write plain text, no markdown.
        """

    static let summaryInstructions = """
        The text was read off someone's screen. Say in two sentences what it is about. Write \
        plain text, no markdown.
        """

    static var modelAvailability: ModelAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable("This Mac cannot run Apple Intelligence, which answers the questions.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("Turn on Apple Intelligence in System Settings to get answers.")
            case .unavailable(.modelNotReady):
                return .unavailable("Apple Intelligence is still downloading. Try again in a while.")
            case .unavailable:
                return .unavailable("Apple Intelligence is not available right now.")
            }
        }
        #endif
        return .unavailable("Answers need macOS 26 with Apple Intelligence.")
    }

    // MARK: Asking

    /// Reads the front window on `displayID` and answers what is in it.
    func ask(on displayID: CGDirectDisplayID) {
        task?.cancel()
        answer = ""
        sourceName = nil

        if case .unavailable(let reason) = Self.modelAvailability {
            phase = .failed(reason)
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            phase = .needsPermission
            return
        }

        phase = .reading
        let target = ScreenCapture.frontWindow(on: displayID)
        sourceName = target.appName
        task = Task { [weak self] in
            do {
                let image = try await ScreenCapture.image(displayID: displayID, windowID: target.windowID)
                try Task.checkCancellation()
                let text = try await Self.recognizeText(in: image)
                try Task.checkCancellation()
                try await self?.answerQuestions(in: text)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.phase = .failed(Self.message(for: error))
            }
        }
    }

    /// Answers the questions in `text`, without the screen. Shared with `--check-answers`.
    func answerQuestions(in text: String) async throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            phase = .failed("There is no text to read in the window in front.")
            return
        }
        if case .unavailable(let reason) = Self.modelAvailability {
            phase = .failed(reason)
            return
        }
        phase = .thinking
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            try await stream(text)
        }
        #endif
        try Task.checkCancellation()
        phase = .answered
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase.isBusy { phase = answer.isEmpty ? .idle : .answered }
    }

    func copyAnswer() {
        guard !answer.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
    }

    #if canImport(FoundationModels)
    /// Answers each question as it is written, below the ones already answered; a page with no
    /// question gets a summary instead. Not greedy sampling: with it this model repeats itself
    /// until its context is full, even on one short question. Each reply is capped as well.
    @available(macOS 26, *)
    private func stream(_ text: String) async throws {
        let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: 160)
        let questions = QuestionSplitter.questions(in: String(text.prefix(Self.textLimit)))

        guard !questions.isEmpty else {
            let summary = LanguageModelSession(instructions: Self.summaryInstructions)
            let prompt = "Text from the screen:\n\n" + String(text.prefix(Self.textLimit))
            for try await snapshot in summary.streamResponse(to: prompt, options: options) {
                try Task.checkCancellation()
                answer = snapshot.content
            }
            return
        }

        var answered: [String] = []
        for (index, question) in questions.enumerated() {
            try Task.checkCancellation()
            let question = QuestionSplitter.withoutNumber(question)
            let heading = "\(index + 1). \(question)"
            let hasOptions = QuestionSplitter.hasOptions(question)
            let session = LanguageModelSession(instructions: hasOptions ? Self.choiceInstructions : Self.answerInstructions)
            var reply = ""
            for try await snapshot in session.streamResponse(to: question, options: options) {
                try Task.checkCancellation()
                reply = QuestionSplitter.tidy(snapshot.content)
                answer = (answered + [heading + "\n→ " + reply]).joined(separator: "\n\n")
            }
            answered.append(heading + "\n→ " + reply)
        }
    }
    #endif

    #if DEBUG
    /// A finished answer for the capture tools.
    func applySample() {
        sourceName = "Safari"
        answer = """
            1. What is the capital of Australia?
            → Canberra is the capital of Australia.

            2. Solve for x: 3x + 7 = 22
            → x = 5
            Subtract 7 from both sides, then divide by 3.

            3. Which gas do plants absorb from the air?
            A) Oxygen B) Nitrogen C) Carbon dioxide D) Helium
            → C) Carbon dioxide
            """
        phase = .answered
    }
    #endif

    // MARK: Permission

    /// Asks for Screen Recording. macOS shows its dialog only the first time, so after that this
    /// opens the place in System Settings where it is switched on. A grant takes effect when
    /// MiniNotch is reopened, which macOS offers to do itself.
    func requestPermission() {
        let key = "screenAnswers.askedForRecording"
        let askedBefore = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(true, forKey: key)

        ForegroundPrompt.begin(timeout: 20)
        if CGRequestScreenCaptureAccess() {
            ForegroundPrompt.end()
            phase = .idle
            return
        }
        if askedBefore {
            ForegroundPrompt.end()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Clears a missing permission once it has been granted, when the tab is shown again.
    func refreshPermission() {
        if phase == .needsPermission, CGPreflightScreenCaptureAccess() { phase = .idle }
    }

    // MARK: Reading

    /// The text in `image`, top to bottom, read on a background thread.
    nonisolated static func recognizeText(in image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }

    private static func message(for error: Error) -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal:
                return "Apple's model would not answer what is on this screen."
            case .exceededContextWindowSize:
                return "There is too much text on screen. Make the window smaller, or scroll to the question."
            case .unsupportedLanguageOrLocale:
                return "Apple's model does not read this language yet."
            default:
                break
            }
        }
        #endif
        if error is ScreenCapture.Failure { return "Could not take a picture of the screen." }
        return error.localizedDescription
    }
}

/// One picture of the front window, or of the display without MiniNotch.
enum ScreenCapture {
    struct Failure: Error {}

    struct Target {
        var windowID: CGWindowID?
        var appName: String?
    }

    /// The frontmost app's front window on `displayID`, from the window server's list, which runs
    /// front to back. Nil when MiniNotch itself is in front, or the app has no ordinary window
    /// there; the whole display is read instead. Window bounds and owners need no permission.
    @MainActor
    static func frontWindow(on displayID: CGDirectDisplayID) -> Target {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid() else { return Target() }
        let display = CGDisplayBounds(displayID)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width > 120, bounds.height > 120,
                  bounds.intersects(display) else { continue }
            return Target(windowID: id, appName: app.localizedName)
        }
        return Target(appName: app.localizedName)
    }

    static func image(displayID: CGDirectDisplayID, windowID: CGWindowID?) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let filter: SCContentFilter
        let size: CGSize
        if let windowID, let window = content.windows.first(where: { $0.windowID == windowID }) {
            filter = SCContentFilter(desktopIndependentWindow: window)
            size = window.frame.size
        } else {
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                throw Failure()
            }
            let ownApp = content.applications.filter { $0.processID == getpid() }
            filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
            size = CGSize(width: display.width, height: display.height)
        }
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int(size.width * scale)
        configuration.height = Int(size.height * scale)
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}

/// Splits text read off a screen into questions, each with the lines under it (its options).
///
/// A line starts a question when it asks something (a "?") or is numbered ("3.", "b)", "Q4");
/// the lines after it, up to the next, belong to it. Text before the first question is a
/// heading or interface and is left out. Done here rather than by the model, which dropped the
/// options when asked to list the questions.
enum QuestionSplitter {
    static let limit = 12
    private static let maxLinesPerQuestion = 8

    static func questions(in text: String) -> [String] {
        var blocks: [[String]] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if startsQuestion(line) {
                // A numbered line under a question that has not asked yet, like "Solve:" then
                // "3x + 7 = 22", is its continuation, not a new question.
                if let last = blocks.last, !last.joined().contains("?"), last.count == 1, !isNumbered(line), !line.contains("?") {
                    blocks[blocks.count - 1].append(line)
                } else {
                    blocks.append([line])
                }
            } else if !blocks.isEmpty, blocks[blocks.count - 1].count < maxLinesPerQuestion {
                blocks[blocks.count - 1].append(line)
            }
        }
        return blocks.prefix(limit).map { $0.joined(separator: "\n") }
    }

    static func startsQuestion(_ line: String) -> Bool {
        line.contains("?") || isNumbered(line)
    }

    private static func isNumbered(_ line: String) -> Bool {
        line.range(of: #"^(Q(uestion)?\s*)?\d{1,3}\s*[.):]\s+\S"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Whether the question offers lettered options, "B)" or "C." (the first letter is often lost
    /// in reading, which leaves a line starting with ")").
    static func hasOptions(_ question: String) -> Bool {
        question.range(of: #"(^|\s)[A-Ea-e][.)]\s+\S"#, options: .regularExpression) != nil
            || question.range(of: #"(?m)^\)\s+\S"#, options: .regularExpression) != nil
    }

    /// The question without the number it was read with, since the answers are numbered again.
    static func withoutNumber(_ question: String) -> String {
        question.replacingOccurrences(of: #"^(Q(uestion)?\s*)?\d{0,3}\s*[.):]\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    /// The reply without markdown asterisks, or a stray "Answer: C" or "Option A." line the model
    /// sometimes adds after an answer it already gave in words, or a line of punctuation alone.
    static func tidy(_ reply: String) -> String {
        reply.replacingOccurrences(of: "**", with: "")
            .components(separatedBy: .newlines)
            .filter { $0.range(of: #"^\s*((answer|option)\s*[A-Z]?\s*[:.)]?\s*([A-Z]\)?\.?)?|[.,;:]+)\s*$|^\s*option\s+[A-Z]\s*:"#, options: [.regularExpression, .caseInsensitive]) == nil }
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

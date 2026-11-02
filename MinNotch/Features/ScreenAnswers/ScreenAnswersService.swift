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
        Answer the question correctly, using the text on the page when there is one. Reply with \
        the answer alone, in a few words, such as "Canberra" or "x = 5". Write plain text, no \
        markdown.
        """

    static let choiceInstructions = """
        The question has answer options. Answer from the text on the page when there is one. Start \
        with the letter and the text of the right option, then at most one line saying why. Write \
        plain text, no markdown.
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
                // What was read from, never what was read: enough to tell a wrong window or an
                // empty picture from a page with nothing on it.
                let blank = ScreenCapture.isBlank(image)
                AppLog.answers.info("Read \(target.appName ?? "?", privacy: .public), window \(target.windowID.map(String.init) ?? "none, whole display", privacy: .public): \(image.width)x\(image.height), blank \(blank), \(text.split(separator: "\n").count) lines")
                if blank, text.isEmpty {
                    self?.phase = .failed("The picture of the screen came back empty. Quit and reopen MiniNotch, which Screen Recording needs after it is switched on.")
                    return
                }
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
        let questions = QuestionSplitter.split(String(text.prefix(Self.textLimit)))

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
            let text = QuestionSplitter.withoutNumber(question.text)
            let hasOptions = QuestionSplitter.hasOptions(text)
            let session = LanguageModelSession(instructions: hasOptions ? Self.choiceInstructions : Self.answerInstructions)
            // The passage above a question is what it asks about: without it a reading question
            // was answered from the options alone, and wrongly (2026-11-02).
            let prompt = question.passage.isEmpty ? text : "Text on the page:\n\(question.passage)\n\nQuestion:\n\(text)"
            // The answer comes first, the question it answers after it in one line.
            let asked = "\(questions.count > 1 ? "\(index + 1). " : "")" + (text.components(separatedBy: .newlines).first ?? text)
            var reply = ""
            for try await snapshot in session.streamResponse(to: prompt, options: options) {
                try Task.checkCancellation()
                reply = QuestionSplitter.tidy(snapshot.content)
                answer = (answered + ["→ " + reply + "\n" + asked]).joined(separator: "\n\n")
            }
            answered.append("→ " + reply + "\n" + asked)
        }
    }
    #endif

    #if DEBUG
    /// A finished answer for the capture tools.
    func applySample() {
        sourceName = "Safari"
        answer = """
            → Canberra
            1. What is the capital of Australia?

            → x = 5
            2. Solve for x: 3x + 7 = 22

            → C) Carbon dioxide
            3. Which gas do plants absorb from the air?
            """
        phase = .answered
    }
    #endif

    // MARK: Permission

    /// Asks for Screen Recording, then opens the place in System Settings where it is switched on.
    /// A grant takes effect when MiniNotch is reopened, which macOS offers to do itself.
    ///
    /// `CGRequestScreenCaptureAccess` alone only checked, on macOS 26: after a `tccutil reset` the
    /// log showed nothing but preflights, and no MiniNotch row appeared in the list (2026-11-02).
    /// Asking ScreenCaptureKit what is on screen is a real request, which shows macOS's dialog
    /// the first time and puts MiniNotch in the list either way.
    func requestPermission() {
        ForegroundPrompt.begin(timeout: 20)
        if CGRequestScreenCaptureAccess() {
            ForegroundPrompt.end()
            phase = .idle
            return
        }
        Task { @MainActor [weak self] in
            let granted = (try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)) != nil
            ForegroundPrompt.end()
            if granted, CGPreflightScreenCaptureAccess() {
                self?.phase = .idle
                return
            }
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
        let windows: [(id: CGWindowID, area: CGFloat)] = list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width > 120, bounds.height > 120,
                  bounds.intersects(display) else { return nil }
            return (id, bounds.width * bounds.height)
        }
        // The front window that is a real window, not a strip in front of one: Chrome in full
        // screen puts its toolbar in a window of its own, 158 points tall, in front of the page,
        // and that was all Read Screen ever read (2026-11-02). A quarter of the app's largest
        // window still lets a dialog in front be read.
        let largest = windows.map(\.area).max() ?? 0
        if let window = windows.first(where: { $0.area >= largest / 4 }) {
            return Target(windowID: window.id, appName: app.localizedName)
        }
        return Target(appName: app.localizedName)
    }

    /// Whether `image` is one flat colour, which is what a capture without the permission in
    /// force returns. Judged on a 16 × 16 copy.
    nonisolated static func isBlank(_ image: CGImage) -> Bool {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let first = Array(pixels[0..<3])
        return stride(from: 0, to: pixels.count, by: 4).allSatisfy { index in
            zip(pixels[index..<index + 3], first).allSatisfy { abs(Int($0) - Int($1)) < 6 }
        }
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
    private static let maxLinesPerQuestion = 14
    /// How much of the text before a question goes with it, in characters: enough for a reading
    /// passage, little enough that the model's 4,096-token context has room left to answer.
    static let passageLimit = 1_600

    /// A question as read, and the text above it since the last question: the passage it asks
    /// about, or only interface.
    struct Question {
        var text: String
        var passage: String
    }

    static func questions(in text: String) -> [String] {
        split(text).map(\.text)
    }

    static func split(_ text: String) -> [Question] {
        var blocks: [(lines: [String], passage: [String])] = []
        var pending: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if startsQuestion(line) {
                // A numbered line under a question that has not asked yet, like "Solve:" then
                // "3x + 7 = 22", is its continuation, not a new question.
                if let last = blocks.last, pending.isEmpty, !last.lines.joined().contains("?"), last.lines.count == 1, !isNumbered(line), !line.contains("?") {
                    blocks[blocks.count - 1].lines.append(line)
                } else {
                    blocks.append(([line], pending))
                    pending = []
                }
            } else if !blocks.isEmpty, blocks[blocks.count - 1].lines.count < maxLinesPerQuestion, pending.isEmpty {
                blocks[blocks.count - 1].lines.append(line)
            } else {
                pending.append(line)
            }
        }
        return blocks.prefix(limit).map { block in
            Question(text: block.lines.joined(separator: "\n"),
                     passage: String(block.passage.joined(separator: "\n").suffix(passageLimit)))
        }
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
            .map { $0.replacingOccurrences(of: #"^\s*(answer|step|working)\s*:\s*(?=\S)"#, with: "", options: [.regularExpression, .caseInsensitive]) }
            .filter { $0.range(of: #"^\s*((answer|option)\s*[A-Z]?\s*[:.)]?\s*([A-Z]\)?\.?)?|[.,;:]+)\s*$|^\s*option\s+[A-Z]\s*:"#, options: [.regularExpression, .caseInsensitive]) == nil }
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

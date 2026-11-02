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
    /// The letter picked for each question with lettered options, in order.
    private(set) var letters: [String] = []
    /// The letters the closed notch is showing: set when an answer's letters change, cleared
    /// `letterShowTime` later, so the notch says it once and fades rather than holding it up.
    private(set) var notchLetters: [String] = []
    /// When Keep Reading next reads, for the countdown on the closed notch.
    private(set) var nextReadAt: Date?
    /// Keep Reading: the screen is read again every `watchInterval`, and answered again only when
    /// its text changed. For as long as MiniNotch runs, never saved, so it is never on at launch.
    private(set) var isWatching = false

    @ObservationIgnored private var task: Task<Void, Never>?
    /// Off only in `--check-answers --no-calc`, to measure what the calculator is worth.
    @ObservationIgnored var usesCalculator = true
    @ObservationIgnored private var watchTimer: Timer?
    @ObservationIgnored private var watchDisplay: CGDirectDisplayID = CGMainDisplayID()
    @ObservationIgnored private var letterFade: DispatchWorkItem?
    /// The text of the last read, so a read that finds the same page costs no model time.
    @ObservationIgnored private var lastText = ""
    /// What the notch last showed, so the same answer read again stays faded.
    @ObservationIgnored private var lastShownLetters: [String] = []

    /// Seconds between Keep Reading's reads, from Settings (`answerReadInterval`).
    @ObservationIgnored private(set) var watchInterval: TimeInterval = 5
    static let letterShowTime: TimeInterval = 5

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

    /// Added for a question with numbers in it, which is also the only kind given the calculator:
    /// given it on every question, the SAT reading question went from A to D (2026-11-02).
    static let calculatorInstructions = """
        For any arithmetic, call the calculate tool with the numbers and use its result; never \
        work numbers out yourself.
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
        lastShownLetters = []
        read(on: displayID, quietly: false)
    }

    /// Starts or stops Keep Reading, from the display the tab was opened on.
    func setWatching(_ on: Bool, display displayID: CGDirectDisplayID) {
        watchTimer?.invalidate()
        watchTimer = nil
        nextReadAt = nil
        isWatching = on
        guard on else { return }
        watchDisplay = displayID
        lastShownLetters = []
        read(on: displayID, quietly: false)
        scheduleWatch()
    }

    /// Changes the time between reads; a running Keep Reading starts counting again from now.
    func setWatchInterval(_ seconds: TimeInterval) {
        guard seconds != watchInterval else { return }
        watchInterval = seconds
        if isWatching { scheduleWatch() }
    }

    private func scheduleWatch() {
        watchTimer?.invalidate()
        nextReadAt = Date().addingTimeInterval(watchInterval)
        let timer = Timer.onMain(every: watchInterval) { [weak self] in
            guard let self else { return }
            self.nextReadAt = Date().addingTimeInterval(self.watchInterval)
            guard !self.phase.isBusy else { return }
            self.read(on: self.watchDisplay, quietly: true)
        }
        timer.tolerance = 0.2
        watchTimer = timer
    }

    /// One read. `quietly` is a Keep Reading tick: it leaves the answer on screen while it looks,
    /// and changes nothing when the page's text is what it was, or when there is nothing to read.
    private func read(on displayID: CGDirectDisplayID, quietly: Bool) {
        if case .unavailable(let reason) = Self.modelAvailability {
            task?.cancel()
            phase = .failed(reason)
            if isWatching { setWatching(false, display: displayID) }
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            task?.cancel()
            phase = .needsPermission
            if isWatching { setWatching(false, display: displayID) }
            return
        }

        let target = ScreenCapture.frontWindow(on: displayID)
        if !quietly {
            task?.cancel()
            answer = ""
            letters = []
            sourceName = target.appName
            phase = .reading
        }
        task = Task { [weak self] in
            do {
                let image = try await ScreenCapture.image(displayID: displayID, windowID: target.windowID)
                try Task.checkCancellation()
                let text = try await Self.recognizeText(in: image)
                try Task.checkCancellation()
                guard let self else { return }
                // What was read from, never what was read: enough to tell a wrong window or an
                // empty picture from a page with nothing on it.
                let blank = ScreenCapture.isBlank(image)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if quietly {
                    guard !trimmed.isEmpty, trimmed != self.lastText else { return }
                }
                AppLog.answers.info("Read \(target.appName ?? "?", privacy: .public), window \(target.windowID.map(String.init) ?? "none, whole display", privacy: .public): \(image.width)x\(image.height), blank \(blank), \(text.split(separator: "\n").count) lines\(quietly ? ", kept reading" : "", privacy: .public)")
                if blank, trimmed.isEmpty {
                    self.phase = .failed("The picture of the screen came back empty. Quit and reopen MiniNotch, which Screen Recording needs after it is switched on.")
                    return
                }
                self.lastText = trimmed
                if quietly {
                    self.answer = ""
                    self.letters = []
                    self.sourceName = target.appName
                }
                try await self.answerQuestions(in: text)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                // Forget the page, so a quiet read that failed (the model paused in Game Mode)
                // is answered on the next tick rather than skipped as already seen.
                self?.lastText = ""
                guard !quietly else { return }
                self?.phase = .failed(Self.message(for: error))
            }
        }
    }

    /// Puts new letters on the closed notch. They stay until the closed notch has shown them for
    /// `letterShowTime` (`notchShowedLetters`), not from when they arrive: a read is started from
    /// the open panel, which covers the closed notch, and a fade timed from the answer had run
    /// out before anyone closed it (2026-11-02). The same letters read again stay faded.
    private func showLetters() {
        guard !letters.isEmpty, letters != lastShownLetters else { return }
        lastShownLetters = letters
        letterFade?.cancel()
        letterFade = nil
        notchLetters = letters
    }

    /// Called by a closed notch while it draws the letters: they fade `letterShowTime` later.
    /// Calling again while that is under way changes nothing.
    func notchShowedLetters() {
        guard !notchLetters.isEmpty, letterFade == nil else { return }
        let fade = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.notchLetters = []
                self?.letterFade = nil
            }
        }
        letterFade = fade
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.letterShowTime, execute: fade)
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
        showLetters()
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
            // The calculator does the arithmetic: the model on its own guessed at sums (2026-11-02).
            let hasNumbers = usesCalculator && QuestionSplitter.hasArithmetic(text)
            let instructions = (hasOptions ? Self.choiceInstructions : Self.answerInstructions)
                + (hasNumbers ? "\n" + Self.calculatorInstructions : "")
            let session = LanguageModelSession(tools: hasNumbers ? [CalculatorTool()] : [], instructions: instructions)
            // The passage above a question is what it asks about: without it a reading question
            // was answered from the options alone, and wrongly (2026-11-02).
            let prompt = question.passage.isEmpty ? text : "Text on the page:\n\(question.passage)\n\nQuestion:\n\(text)"
            // The answer comes first, the question it answers after it in one line.
            let asked = "\(questions.count > 1 ? "\(index + 1). " : "")" + (text.components(separatedBy: .newlines).first ?? text)
            // An equation MiniNotch can solve exactly is never given to the model.
            if !hasOptions, let solution = EquationSolver.solve(in: text) {
                answered.append("→ " + solution.text + "\n" + asked)
                answer = answered.joined(separator: "\n\n")
                continue
            }
            var reply = ""
            for try await snapshot in session.streamResponse(to: prompt, options: options) {
                try Task.checkCancellation()
                reply = QuestionSplitter.tidy(snapshot.content)
                answer = (answered + ["→ " + reply + "\n" + asked]).joined(separator: "\n\n")
            }
            answered.append("→ " + reply + "\n" + asked)
            if hasOptions {
                let letter = QuestionSplitter.letter(in: reply, question: text)
                if let letter { letters.append(letter) }
                AppLog.answers.info("Question \(index + 1) has options: letter \(letter ?? "not found", privacy: .public)")
            }
        }
    }
    #endif

    #if DEBUG
    /// A finished answer for the capture tools.
    /// Keep Reading's countdown for the capture tools, with no timer and no read behind it.
    func applySampleCountdown(seconds: TimeInterval) {
        isWatching = true
        nextReadAt = Date().addingTimeInterval(seconds)
    }

    func applySample() {
        sourceName = "Safari"
        letters = ["C"]
        showLetters()
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
        // macOS pauses Apple's model for every app in Game Mode, and says so only deep in the
        // error: "Not executed due to current system state [StandardGameMode]" (2026-11-02).
        if Self.describesSystemPause(error as NSError) {
            return "Apple's model is paused right now, which macOS does in Game Mode. Close the game, or try again in a moment."
        }
        return error.localizedDescription
    }
}

extension ScreenAnswersService {
    /// Whether the model service refused because of the Mac's state rather than the request:
    /// Game Mode, or a busy system. Walks the underlying errors, where the reason is kept.
    nonisolated static func describesSystemPause(_ error: NSError) -> Bool {
        if error.code == 1013, error.domain.contains("ModelManager") { return true }
        if "\(error)".contains("GameMode") || "\(error)".contains("system state") { return true }
        let underlying = (error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] ?? [])
            + [error.userInfo[NSUnderlyingErrorKey] as? NSError].compactMap { $0 }
        return underlying.contains { describesSystemPause($0) }
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
        line.contains("?") || isNumbered(line) || isInstruction(line)
    }

    /// "Solve for x: …", "Find the area…": a maths question asks without a question mark.
    private static func isInstruction(_ line: String) -> Bool {
        line.range(of: #"^(solve|find|calculate|compute|evaluate|simplify|factori[sz]e|expand|work out|determine|convert)\b"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
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

    /// The option a reply picked: "A" from "A. It isn't growing…", "C) Carbon dioxide", "The
    /// answer is B" or "Option D: …", or failing those, the option whose text the reply repeats.
    /// The model words its replies differently from page to page, and a letter it was only
    /// matched in the first form left the closed notch empty (2026-11-02).
    static func letter(in reply: String, question: String = "") -> String? {
        let patterns = [
            #"^\s*\(?([A-Ha-h])\s*[.):]"#,
            #"(?i)\b(?:answer|option|choice)\s*(?:is|:)?\s*\(?([A-H])\b"#,
            #"^\s*\(?([A-H])\)?\s*$"#,
        ]
        let firstLine = reply.components(separatedBy: .newlines).first ?? reply
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]),
               let match = regex.firstMatch(in: firstLine, range: NSRange(firstLine.startIndex..., in: firstLine)),
               let range = Range(match.range(at: 1), in: firstLine) {
                return firstLine[range].uppercased()
            }
        }
        // The option whose text the reply repeats, from "B. It isn't producing young trees".
        let lowered = reply.lowercased()
        for line in question.components(separatedBy: .newlines) {
            guard let match = line.range(of: #"^\s*\(?([A-Ha-h])\s*[.)]\s+"#, options: .regularExpression) else { continue }
            let text = line[match.upperBound...].trimmingCharacters(in: .whitespaces).lowercased()
            if text.count >= 4, lowered.contains(text), let letter = line[match].first(where: \.isLetter) {
                return String(letter).uppercased()
            }
        }
        return nil
    }

    /// Whether the question itself (not the page around it) has a sum in it: two numbers, or a
    /// number and a word that asks for one. "Question 3" or "47,000 trees" alone is not maths.
    static func hasArithmetic(_ question: String) -> Bool {
        let body = withoutNumber(question)
        let numbers = body.matches(of: #/\d+(?:[.,]\d+)*/#).count
        let asks = body.range(of: #"(?i)(%|percent|how (many|much|far|long)|total|sum|product|average|[+×÷*/^=]|\d\s*[-x]\s*\d)"#,
                               options: .regularExpression) != nil
        // Algebra ("x^2", "2x", "3y + 1") is not arithmetic: given the calculator, the model
        // rambled over a derivative and once dropped the letter.
        let algebra = body.range(of: #"(?i)(\b[a-z]\s*\^|\d[a-z]\b|\b[a-z]\s*[-+*/]\s*\d)"#, options: .regularExpression) != nil
        return !algebra && (numbers >= 2 || (numbers >= 1 && asks))
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

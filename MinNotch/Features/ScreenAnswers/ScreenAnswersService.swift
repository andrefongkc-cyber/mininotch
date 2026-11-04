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

    private(set) var phase: Phase = .idle {
        didSet {
            // The tab is symbols only, so the reason is a tooltip; the log keeps it too. These are
            // MiniNotch's own messages and the framework's error, never the page's text.
            if case .failed(let reason) = phase, phase != oldValue {
                AppLog.answers.error("Failed: \(reason, privacy: .public)")
            }
        }
    }
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

    /// Scroll and Read: while on, the window that was in front when it started is read about
    /// once a second and every new line is kept (`LineMerge`), so a page longer than the screen
    /// is gathered as the user scrolls it. Answer ends it and answers everything gathered.
    private(set) var isGathering = false
    /// Lines gathered so far, for the tab and the closed notch.
    private(set) var gatheredLineCount = 0
    @ObservationIgnored private var gatherer = PageGatherer()
    /// Questions answered while gathering, by `liveKey`, and each question's text at the last
    /// read: one is answered once it reads the same twice, so its options have all come in.
    @ObservationIgnored private var liveAnswers: [String: (reply: String, letter: String?)] = [:]
    @ObservationIgnored private var liveBlocks: [String: String] = [:]
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var gatherTimer: Timer?
    @ObservationIgnored private var gatherTarget = ScreenCapture.Target()
    @ObservationIgnored private var gatherDisplay: CGDirectDisplayID = CGMainDisplayID()
    @ObservationIgnored private var gatherInFlight = false
    static let gatherInterval: TimeInterval = 0.8
    /// The most a gathered page keeps: about forty screens of text.
    static let gatherLineLimit = 2_000

    /// How much of the text one answer takes: a screen's worth, or a gathered page's.
    struct ReadLimits: Sendable {
        var characters: Int
        var questions: Int
        static let screen = ReadLimits(characters: 6_000, questions: 12)
        static let gathered = ReadLimits(characters: 60_000, questions: 30)
    }
    @ObservationIgnored private var readLimits = ReadLimits.screen
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
        if isGathering { finishGathering(); return }
        lastShownLetters = []
        readLimits = .screen
        read(on: displayID, quietly: false)
    }

    /// Starts or stops Keep Reading, from the display the tab was opened on.
    func setWatching(_ on: Bool, display displayID: CGDirectDisplayID) {
        watchTimer?.invalidate()
        watchTimer = nil
        nextReadAt = nil
        isWatching = on
        guard on else { return }
        if isGathering { cancelGathering() }
        readLimits = .screen
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

    // MARK: Scroll and Read

    /// Starts gathering the window in front on `displayID`; Keep Reading stops while it runs.
    func startGathering(on displayID: CGDirectDisplayID) {
        if case .unavailable(let reason) = Self.modelAvailability {
            phase = .failed(reason)
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            phase = .needsPermission
            return
        }
        if isWatching { setWatching(false, display: displayID) }
        task?.cancel()
        gatherTarget = ScreenCapture.frontWindow(on: displayID)
        gatherDisplay = displayID
        resetGathered()
        answer = ""
        letters = []
        sourceName = gatherTarget.appName
        phase = .idle
        isGathering = true
        gatherOnce()
        let timer = Timer.onMain(every: Self.gatherInterval) { [weak self] in self?.gatherOnce() }
        timer.tolerance = 0.2
        gatherTimer = timer
    }

    /// Stops gathering and answers whatever was not answered as it went, in page order.
    func finishGathering() {
        guard isGathering else { return }
        stopGatherTimer()
        liveTask?.cancel()
        liveTask = nil
        AppLog.answers.info("Scroll and Read: \(self.gatherer.pages.count) pages, \(self.gatherer.lineCount) lines from \(self.gatherTarget.appName ?? "?", privacy: .public)")
        let questions = gatheredQuestions()
        guard !questions.isEmpty else {
            // No question in it at all: a summary of the page, as a single read would give.
            let text = gatherer.pages.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
            readLimits = .gathered
            task = Task { [weak self] in
                do { try await self?.answerQuestions(in: text) } catch {
                    guard !Task.isCancelled else { return }
                    self?.phase = .failed(Self.message(for: error))
                }
            }
            return
        }
        phase = .thinking
        task = Task { [weak self] in
            guard let self else { return }
            do {
                #if canImport(FoundationModels)
                if #available(macOS 26, *) {
                    for (key, question) in questions where self.liveAnswers[key] == nil {
                        try Task.checkCancellation()
                        self.liveAnswers[key] = try await self.answerOne(question) { _ in }
                        self.renderGathered(questions)
                    }
                }
                #endif
                self.renderGathered(questions)
                self.letters = questions.compactMap { self.liveAnswers[$0.key]?.letter }
                self.lastShownLetters = []
                self.phase = .answered
                self.showLetters()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(Self.message(for: error))
            }
        }
    }

    /// Stops gathering and throws away what was gathered.
    func cancelGathering() {
        stopGatherTimer()
        liveTask?.cancel()
        liveTask = nil
        resetGathered()
        if phase.isBusy || phase == .answered, answer.isEmpty { phase = .idle }
    }

    private func resetGathered() {
        gatherer = PageGatherer()
        gatheredLineCount = 0
        liveAnswers = [:]
        liveBlocks = [:]
    }

    private func stopGatherTimer() {
        gatherTimer?.invalidate()
        gatherTimer = nil
        isGathering = false
    }

    /// Every question gathered, in page order, each with the passage it is about (its own, or
    /// the last real one before it), keyed by page and wording so it is answered once.
    private func gatheredQuestions() -> [(key: String, question: QuestionSplitter.Question)] {
        var keyed: [(String, QuestionSplitter.Question)] = []
        for (page, lines) in gatherer.pages.enumerated() {
            for question in QuestionSplitter.split(lines.joined(separator: "\n"), limit: ReadLimits.gathered.questions) {
                let first = question.text.components(separatedBy: .newlines).first ?? question.text
                keyed.append(("\(page):" + LineMerge.key(first), question))
            }
        }
        let carried = QuestionSplitter.carryPassages(keyed.map(\.1))
        return Array(zip(keyed.map(\.0), carried).prefix(ReadLimits.gathered.questions))
    }

    /// The answers so far, in the order the questions appear.
    private func renderGathered(_ questions: [(key: String, question: QuestionSplitter.Question)]) {
        answer = questions.enumerated().compactMap { index, item in
            guard let result = liveAnswers[item.key] else { return nil }
            return "→ " + result.reply + "\n" + Self.asked(item.question, number: index + 1)
        }.joined(separator: "\n\n")
    }

    /// One read of the gathered window, added to its page. Skipped while the last one is still
    /// being read, which a large window on a slow Mac can take longer than a tick to do.
    private func gatherOnce() {
        guard isGathering, !gatherInFlight else { return }
        gatherInFlight = true
        let target = gatherTarget, displayID = gatherDisplay
        Task { [weak self] in
            defer { self?.gatherInFlight = false }
            guard let image = try? await ScreenCapture.image(displayID: displayID, windowID: target.windowID),
                  let text = try? await Self.recognizeText(in: image),
                  let self, self.isGathering else { return }
            let lines = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty, self.gatherer.lineCount < Self.gatherLineLimit else { return }
            self.gatherer.add(lines)
            self.gatheredLineCount = self.gatherer.lineCount
            self.answerSettledQuestions()
        }
    }

    /// Answers, one at a time, each gathered question that read the same as last time, so the
    /// letter for a page shows while the user is still on it rather than at the end.
    private func answerSettledQuestions() {
        let questions = gatheredQuestions()
        let previous = liveBlocks
        liveBlocks = Dictionary(questions.map { ($0.key, $0.question.text) }, uniquingKeysWith: { first, _ in first })
        guard liveTask == nil,
              let next = questions.first(where: { liveAnswers[$0.key] == nil && previous[$0.key] == $0.question.text
                  && QuestionSplitter.hasOptions(QuestionSplitter.withoutNumber($0.question.text)) }) else { return }
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            liveTask = Task { [weak self] in
                guard let self else { return }
                defer { self.liveTask = nil }
                guard let result = try? await self.answerOne(next.question, onUpdate: { _ in }),
                      self.isGathering, !Task.isCancelled else { return }
                self.liveAnswers[next.key] = result
                self.renderGathered(self.gatheredQuestions())
                if self.phase == .idle { self.phase = .answered }
                if let letter = result.letter {
                    // The newest letter alone, even when it is the same as the last one.
                    self.letters = [letter]
                    self.lastShownLetters = []
                    self.showLetters()
                }
            }
        }
        #endif
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
        let questions = QuestionSplitter.split(String(text.prefix(readLimits.characters)), limit: readLimits.questions)

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
        let carried = QuestionSplitter.carryPassages(questions)
        for (index, question) in carried.enumerated() {
            try Task.checkCancellation()
            let asked = Self.asked(question, number: questions.count > 1 ? index + 1 : nil)
            let result = try await answerOne(question) { reply in
                self.answer = (answered + ["→ " + reply + "\n" + asked]).joined(separator: "\n\n")
            }
            answered.append("→ " + result.reply + "\n" + asked)
            answer = answered.joined(separator: "\n\n")
            if let letter = result.letter { letters.append(letter) }
        }
    }

    /// The question as shown under its answer: its first line, numbered when there are several.
    static func asked(_ question: QuestionSplitter.Question, number: Int?) -> String {
        let text = QuestionSplitter.withoutNumber(question.text)
        return (number.map { "\($0). " } ?? "") + (text.components(separatedBy: .newlines).first ?? text)
    }

    /// One question answered: by the equation solver when it can, else by Apple's model with
    /// the passage above it. `onUpdate` sees the reply as it is written.
    @available(macOS 26, *)
    func answerOne(_ question: QuestionSplitter.Question, onUpdate: (String) -> Void) async throws -> (reply: String, letter: String?) {
        // Without the page's interface around it: a "Question 1 of 3" under the options with a
        // toolbar above the passage turned the Pando answer wrong half the time, and either one
        // removed made it right six times in six (2026-11-03).
        let text = QuestionSplitter.withoutInterface(QuestionSplitter.withoutNumber(question.text))
        let hasOptions = QuestionSplitter.hasOptions(text)
        let options = hasOptions && choosesGreedily
            ? GenerationOptions(sampling: .greedy, maximumResponseTokens: 160)
            : GenerationOptions(temperature: 0.2, maximumResponseTokens: 160)
        // The calculator does the arithmetic: the model on its own guessed at sums (2026-11-02).
        let hasNumbers = usesCalculator && QuestionSplitter.hasArithmetic(text)
        let instructions = (hasOptions ? Self.choiceInstructions : Self.answerInstructions)
            + (hasNumbers ? "\n" + Self.calculatorInstructions : "")
        let session = LanguageModelSession(tools: hasNumbers ? [CalculatorTool()] : [], instructions: instructions)
        // The passage above a question is what it asks about: without it a reading question
        // was answered from the options alone, and wrongly (2026-11-02).
        // Rejoined into sentences: a passage broken where the screen wrapped it moved the Pando
        // answer from A to D half the time, though the words were the same (2026-11-03).
        let passage = QuestionSplitter.reflow(QuestionSplitter.withoutHeadings(question.passage))
        var prompt = passage.isEmpty ? text : "Text on the page:\n\(passage)\n\nQuestion:\n\(text)"
        if hasOptions, fillsBlanks, let filled = QuestionSplitter.filledIn(passage: question.passage, question: text) {
            prompt = filled
        }
        // An equation MiniNotch can solve exactly is never given to the model.
        if !hasOptions, let solution = EquationSolver.solve(in: text) {
            return (solution.text, nil)
        }
        // Reasoning before a constrained letter, measured worse and off (`usesReasonedChoice`).
        if hasOptions, usesReasonedChoice, let choice = try await reasonedChoice(prompt: prompt, question: text, tools: hasNumbers) {
            AppLog.answers.info("Question has options: letter \(choice.letter, privacy: .public), reasoned")
            return (choice.shown, choice.letter)
        }
        var reply = ""
        do {
            reply = try await streamReply(session: session, prompt: prompt, options: options, onUpdate: onUpdate)
        } catch let error as LanguageModelSession.GenerationError {
            // Apple's safety check flagged an innocent page (a farmhouse in a 1913 novel,
            // 2026-11-02). Answering about text the user already has is what the relaxed
            // check is for; it applies to plain text replies.
            guard case .guardrailViolation = error else { throw error }
            let relaxed = LanguageModelSession(model: Self.relaxedModel, tools: hasNumbers ? [CalculatorTool()] : [], instructions: instructions)
            reply = try await streamReply(session: relaxed, prompt: prompt, options: options, onUpdate: onUpdate)
        }
        guard hasOptions else { return (reply, nil) }
        let letter = QuestionSplitter.letter(in: reply, question: text)
        // A reply that is the letter alone shows the option's own words with it.
        if let letter, reply.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^\(?[A-Ea-e]\)?[.)]?$"#, options: .regularExpression) != nil,
           let option = QuestionSplitter.option(letter, in: text) {
            reply = option
        }
        AppLog.answers.info("Question has options: letter \(letter ?? "not found", privacy: .public)")
        return (reply, letter)
    }

    @available(macOS 26, *)
    private static let relaxedModel = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    @available(macOS 26, *)
    private func streamReply(session: LanguageModelSession, prompt: String, options: GenerationOptions,
                             onUpdate: (String) -> Void) async throws -> String {
        var reply = ""
        for try await snapshot in session.streamResponse(to: prompt, options: options) {
            try Task.checkCancellation()
            reply = QuestionSplitter.tidy(snapshot.content)
            onUpdate(reply)
        }
        return reply
    }

    /// The letter, and the option as it is shown: "A. It isn't growing at the same rate…".
    struct Choice {
        var letter: String
        var shown: String
    }

    /// A multiple-choice question answered as a sentence of reasoning and then a letter from a
    /// fixed set. Nil when the model will not answer it this way (its safety check, mostly), so
    /// the plain reply is tried instead.
    @available(macOS 26, *)
    private func reasonedChoice(prompt: String, question: String, tools: Bool) async throws -> Choice? {
        let session = LanguageModelSession(tools: tools ? [CalculatorTool()] : [], instructions: Self.reasonedChoiceInstructions
            + (tools ? "\n" + Self.calculatorInstructions : ""))
        do {
            let response = try await session.respond(to: prompt, generating: ChoiceReply.self,
                                                     options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 300))
            try Task.checkCancellation()
            let letter = response.content.letter.uppercased()
            return Choice(letter: letter, shown: QuestionSplitter.option(letter, in: question) ?? letter)
        } catch let error as LanguageModelSession.GenerationError {
            if case .guardrailViolation = error { return nil }
            if case .refusal = error { return nil }
            throw error
        }
    }

    static let reasonedChoiceInstructions = """
        Answer a multiple-choice question about the text on the page. First check the options in \
        a sentence or two: for a reading question, what the text actually says; for a grammar \
        question, the rule that decides it, such as which noun the verb agrees with. Then give the \
        letter of the one right option.
        """
    #endif

    /// Reasoning before the letter, measured on 2026-11-02 against twelve SAT-style questions:
    /// 75% with it, 89% without, because the model talked itself out of right transitions. Off;
    /// `--check-answers --reasoned` measures it again.
    @ObservationIgnored var usesReasonedChoice = false
    /// The most likely reply, every time, for multiple choice. Under test.
    @ObservationIgnored var choosesGreedily = false
    /// A blank's options shown as finished sentences (`QuestionSplitter.filledIn`): 83% against
    /// 89% without on the same twelve, fixing a comma and losing a transition. Off; `--fill`.
    @ObservationIgnored var fillsBlanks = false

    #if DEBUG
    /// A finished answer for the capture tools.
    /// Scroll and Read part way through, for the capture tools: no timer, no read.
    func applySampleGathering(lines: Int) {
        isGathering = true
        gatheredLineCount = lines
        sourceName = "Google Chrome"
        phase = .idle
        answer = ""
    }

    /// Scroll and Read fed `reads` as if from the screen, each settling before the next, then
    /// finished, for `--check-answers --quiz`. Returns the letters answered live, in order.
    func simulateGather(_ reads: [[String]]) async -> [String] {
        resetGathered()
        isGathering = true
        var live: [String] = []
        for read in reads {
            gatherer.add(read)
            gatheredLineCount = gatherer.lineCount
            answerSettledQuestions()
            while let running = liveTask { await running.value }
            if letters != live.suffix(1), let letter = letters.last, liveTask == nil, !letters.isEmpty {
                live.append(letter)
                letters = []
            }
        }
        finishGathering()
        while phase == .thinking || isGathering { try? await Task.sleep(for: .milliseconds(100)) }
        if let task { await task.value }
        return live
    }

    /// A gathered page answered with the gathered limits, for `--check-answers --long`.
    func answerGathered(_ text: String) async throws {
        readLimits = .gathered
        try await answerQuestions(in: text)
    }

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
        AppLog.answers.error("Error: \(String(describing: error), privacy: .public)")
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

    static func split(_ text: String, limit: Int = limit) -> [Question] {
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
                    // A question that wrapped on screen: "…conforms to the conventions of" then
                    // "Standard English?". Its first half is not the end of a sentence, so it
                    // belongs to the question, not to the passage above (2026-11-02).
                    // Only a long line cut off mid-sentence, and only when the "?" line does not
                    // start a question itself: a toolbar's "Practice Test" above "Based on the
                    // text, …?" was joined onto it (2026-11-03).
                    var start = [line]
                    while line.contains("?"), start.count < 3, !startsAsQuestion(start[0]), let last = pending.last,
                          last.count >= 40, last.range(of: #"[.!?:;"”)\]]$"#, options: .regularExpression) == nil, !isOptionLine(last) {
                        start.insert(pending.removeLast(), at: 0)
                    }
                    blocks.append((start.count > 1 ? [start.joined(separator: " ")] : start, pending))
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

    /// A multiple-choice question without the short lines after its last option: "Question 1
    /// of 3", "Next", "Mark for Review". A long line after it is the last option wrapping.
    static func withoutInterface(_ question: String) -> String {
        var lines = question.components(separatedBy: .newlines)
        guard let lastOption = lines.lastIndex(where: isOptionLine) else { return question }
        var end = lastOption + 1
        while end < lines.count, lines[end].trimmingCharacters(in: .whitespaces).count >= 40 { end += 1 }
        lines.removeSubrange(end...)
        return lines.joined(separator: "\n")
    }

    /// A passage without the short lines above it that end no sentence: a toolbar's
    /// "Practice Test", a section's "Reading and Writing".
    static func withoutHeadings(_ passage: String) -> String {
        var lines = passage.components(separatedBy: .newlines)
        while let first = lines.first?.trimmingCharacters(in: .whitespaces),
              first.count < 40, first.range(of: #"[.!?:;"”]$"#, options: .regularExpression) == nil, lines.count > 1 {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n")
    }

    /// Lines that the screen wrapped, joined back: a line that does not end a sentence runs on
    /// into the next, unless it is short (a heading or a label) or the next starts a list item.
    static func reflow(_ text: String) -> String {
        var paragraphs: [String] = []
        var current = ""
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                if !current.isEmpty { paragraphs.append(current); current = "" }
                continue
            }
            if current.isEmpty {
                current = line
            } else if current.count >= 40, current.range(of: #"[.!?:;"”)\]]$"#, options: .regularExpression) == nil, !isOptionLine(line) {
                current += " " + line
            } else {
                paragraphs.append(current)
                current = line
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs.joined(separator: "\n")
    }

    /// "Which…", "According to…": a line that opens a question rather than finishing one.
    private static func startsAsQuestion(_ line: String) -> Bool {
        line.range(of: #"^(which|what|why|how|who|whom|whose|when|where|according|based|in the|as used|is|are|does|do|did|can|could|would|should|will|select|choose|identify)\b"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isOptionLine(_ line: String) -> Bool {
        line.range(of: #"^\(?[A-Ea-e]\s*[.)]\s+\S"#, options: .regularExpression) != nil
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

    /// A fill-in-the-blank question as each option makes it: "A. … were surprised when …",
    /// "B. … was surprised when …". Nil without a blank ("______") in the passage or options.
    static func filledIn(passage: String, question: String) -> String? {
        guard let blank = passage.range(of: #"_{3,}"#, options: .regularExpression) else { return nil }
        // The sentence with the blank, from the sentence end before it to the one after.
        let before = passage[..<blank.lowerBound]
        let after = passage[blank.upperBound...]
        let start = before.range(of: #"[.!?]\s"#, options: [.regularExpression, .backwards])?.upperBound ?? before.startIndex
        let end = after.range(of: #"[.!?](\s|$)"#, options: .regularExpression)?.upperBound ?? after.endIndex
        let head = String(passage[start..<blank.lowerBound])
        let tail = String(passage[blank.upperBound..<end])
        let options = question.components(separatedBy: .newlines).compactMap { line -> (String, String)? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let match = trimmed.range(of: #"^\(?[A-Ea-e]\s*[.)]\s*"#, options: .regularExpression),
                  let letter = trimmed[match].first(where: \.isLetter) else { return nil }
            return (String(letter).uppercased(), String(trimmed[match.upperBound...]))
        }
        guard options.count >= 2 else { return nil }
        let asked = question.components(separatedBy: .newlines).first ?? question
        let context = String(passage[..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
        let versions = options.map { letter, text in
            "\(letter). " + (head + text + (text.hasSuffix(" ") || tail.hasPrefix(" ") || tail.hasPrefix(",") || tail.hasPrefix(".") ? "" : " ") + tail)
                .replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        }
        return (context.isEmpty ? "" : "Text on the page:\n\(context)\n\n")
            + "\(asked)\nThe sentence with each option in the blank:\n" + versions.joined(separator: "\n")
            + "\nWhich version is right? Answer with its letter and the option."
    }

    /// Each question with no passage of its own, or only a line of interface, takes the last
    /// real passage before it: "Questions 1 to 3 refer to the text", or a passage on one page
    /// and its questions on the pages after (2026-11-03).
    static let passageMinimum = 150

    static func carryPassages(_ questions: [Question]) -> [Question] {
        var last = ""
        return questions.map { question in
            var question = question
            if question.passage.count >= passageMinimum {
                last = question.passage
            } else if !last.isEmpty {
                question.passage = last
            }
            return question
        }
    }

    /// The option line for `letter`, "B. It isn't producing young trees anymore.", as read.
    static func option(_ letter: String, in question: String) -> String? {
        for line in question.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: "^\\(?\(letter)\\s*[.)]\\s+", options: [.regularExpression, .caseInsensitive]) != nil {
                return trimmed
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

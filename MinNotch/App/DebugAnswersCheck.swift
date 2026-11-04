#if DEBUG
import AppKit

/// Runs the Answers tab's reading and answering on a page drawn here, without the screen.
///
/// Run with `MiniNotch --check-answers [--image page.png | --text "page"]`. Prints what Vision read off the page,
/// then what Apple's model answered and how long each took. Screen Recording is the one step it
/// leaves out, since a capture from a shell is judged against the terminal.
@MainActor
enum DebugAnswersCheck {
    static let flag = "--check-answers"

    static let samplePage = """
        Chapter 3 Review

        1. What is the capital of Australia?
        2. Solve for x: 3x + 7 = 22
        3. Which gas do plants absorb from the air?
           A) Oxygen   B) Nitrogen   C) Carbon dioxide   D) Helium
        4. Who wrote Romeo and Juliet?
        """

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard arguments.contains(flag) else { return false }

        // `--merge` checks Scroll and Read's stitching on a page read as overlapping screens.
        if arguments.contains("--merge") {
            let chrome = ["Course Home", "Quiz 4: Reading", "Time left 12:00"]
            let page = (1...60).map { "Line \($0) of the passage, with words that differ." }
            // Screens of 20 lines, scrolled down 7 at a time, then back up 9 at a time.
            var starts = Array(stride(from: 0, through: 40, by: 7)) + [40]
            starts += Array(stride(from: 31, through: 0, by: -9))
            var kept: [String] = []
            for (n, start) in starts.enumerated() {
                var screen = chrome + Array(page[start..<min(start + 20, page.count)])
                // Text recognition is not identical between reads: a lost full stop, a case change.
                if n % 2 == 1 { screen = screen.map { $0.replacingOccurrences(of: ".", with: "") } }
                if n % 3 == 2 { screen[3] = screen[3].uppercased() }
                kept = LineMerge.merge(kept, screen)
            }
            let keys = kept.map(LineMerge.key)
            let wanted = (chrome + page).map(LineMerge.key)
            print("screens: \(starts.count), lines kept: \(kept.count), wanted: \(wanted.count)")
            print(keys == wanted ? "PASS the page, once, in order" : "FAIL\n" + kept.joined(separator: "\n"))
            // A jump further than a screen keeps both, the new one after.
            let jumped = LineMerge.merge(Array(page[0..<10]), Array(page[30..<40]))
            print(jumped.count == 20 ? "PASS a jump keeps both" : "FAIL a jump kept \(jumped.count)")
            return true
        }

        // `--pages` gathers a quiz: a long passage scrolled on page one, then pages of questions
        // that repeat their wording, a footer that changes and a step back.
        if arguments.contains("--pages") {
            let top = ["Practice Test", "Section 1, Module 1", "Time left 31:00"]
            func footer(_ n: Int) -> [String] { ["Mark for Review", "Question \(n) of 4", "Back", "Next"] }
            let passage = (1...36).map { "Passage line \($0): the town built a second bridge in year \(1900 + $0)." }
            func question(_ n: Int) -> [String] {
                ["Which choice best states the main idea of the text?",
                 "A. Option \(n)A about bridges.", "B. Option \(n)B about rivers.",
                 "C. Option \(n)C about towns.", "D. Option \(n)D about years."]
            }
            let page1 = passage + question(1)
            var gatherer = PageGatherer()
            // Page one, scrolled down a screen of 18 at a time by 8.
            for start in stride(from: 0, through: page1.count - 18, by: 8) + [page1.count - 18] {
                gatherer.add(top + Array(page1[start..<start + 18]) + footer(1))
            }
            gatherer.add(top + Array(page1[page1.count - 18..<page1.count]) + footer(1))   // the same screen again
            for n in 2...4 { for _ in 0..<3 { gatherer.add(top + question(n) + footer(n)) } }   // each read three times
            gatherer.add(top + question(2) + footer(2))   // back to page two
            gatherer.add(top + question(4) + footer(4))   // and forward again
            print("pages: \(gatherer.pages.count), wanted 4")
            for (i, page) in gatherer.pages.enumerated() {
                let questions = QuestionSplitter.carryPassages(QuestionSplitter.split(page.joined(separator: "\n")))
                let options = page.filter { $0.range(of: #"^[A-D]\. Option"#, options: .regularExpression) != nil }
                let passageLines = page.filter { $0.hasPrefix("Passage line") }.count
                print("page \(i + 1): \(page.count) lines, passage lines \(passageLines), questions \(questions.count), options \(options.count)")
            }
            let all = gatherer.pages.map { $0.joined(separator: "\n") }
            let questions = QuestionSplitter.carryPassages(all.flatMap { QuestionSplitter.split($0) })
            let withPassage = questions.filter { $0.passage.contains("Passage line 36") || $0.passage.contains("Passage line 1:") }.count
            print("questions \(questions.count), with the passage: \(withPassage)")
            let pass = gatherer.pages.count == 4 && questions.count == 4 && withPassage == 4
                && gatherer.pages[0].filter { $0.hasPrefix("Passage line") }.count == 36
            print(pass ? "PASS" : "FAIL")
            return true
        }

        // `--calc` checks the calculator the model is given, on sums and on hostile input.
        if arguments.contains("--calc") {
            let cases = ["17 × 24", "(22 - 7) / 3", "15% * 240", "60 * 2.5", "3/4 + 2/3", "1234 + 5678",
                         "sqrt(144)", "2^10", "-3 + -4", "1,000 * 3", "1/0", "2^5000", "((((1", "FUNCTION(1,'x')",
                         "1e308*10", String(repeating: "(", count: 500) + "1", ""]
            for expression in cases {
                let shown = expression.count > 30 ? String(expression.prefix(30)) + "…" : expression
                do { print("\(shown) = \(Calculator.format(try Calculator.evaluate(expression)))") }
                catch { print("\(shown) → refused: \(error)") }
            }
            for question in ["Solve for x: 5x - 3 = 2x + 12", "Find x if 4x = 52", "3x + 7 = 22", "Solve: 2(x + 3) = 14",
                             "x/4 = 3", "Solve for y: 7 - y = 10", "x^2 = 16", "2x + 3y = 6", "What is 5 = 5?",
                             "Solve for x: 0.5x + 1.25 = 3"] {
                print("\(question) → \(EquationSolver.solve(in: question)?.text ?? "left to the model")")
            }
            return true
        }

        // `--eval file.json [--runs 3]`: questions with known letters, each answered `runs` times.
        if let index = arguments.firstIndex(of: "--eval"), index + 1 < arguments.count {
            runEval(path: arguments[index + 1], runs: arguments.firstIndex(of: "--runs").flatMap { Int(arguments[$0 + 1]) } ?? 3)
            return true
        }

        // `--quiz` runs a three-page quiz through Scroll and Read: the passage on page one, then
        // questions about it on the next two, each screen read three times.
        if arguments.contains("--quiz") {
            let top = ["Practice Test", "Reading and Writing"]
            let passage = ["Utah is home to Pando, a colony of about 47,000 quaking aspen trees that all share a single root system.",
                           "Pando is one of the largest single organisms by mass on Earth, but ecologists are worried that its growth",
                           "is declining in part because of grazing by animals. The ecologists say that strong fences could prevent deer",
                           "from eating young trees and help Pando start thriving again."]
            let pages: [[String]] = [
                passage + ["According to the text, why are ecologists worried about Pando?",
                           "A. It isn't growing at the same rate it used to.", "B. It isn't producing young trees anymore.",
                           "C. It can't grow into new areas because it is blocked by fences.", "D. Its root system can't support many more new trees.",
                           "Question 1 of 3"],
                ["Based on the text, what do the ecologists suggest could help Pando?",
                 "A. Planting new trees beside it", "B. Building fences to keep deer away",
                 "C. Removing its oldest trees", "D. Watering its roots", "Question 2 of 3"],
                ["According to the text, about how many trees make up Pando?",
                 "A. 4,700", "B. 47", "C. 47,000", "D. 470,000", "Question 3 of 3"],
            ]
            let reads = pages.flatMap { page in Array(repeating: top + page, count: 3) }
            let service = ScreenAnswersService()
            var done = false
            Task {
                let live = await service.simulateGather(reads)
                print("letters as it went: \(live.joined(separator: " ")), wanted A B C")
                print("letters at the end: \(service.letters.joined(separator: " "))")
                print(service.answer)
                done = true
            }
            while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
            return true
        }

        // `--gather-images a.png b.png … [--key ABC…] [--split-only]` reads each picture as a
        // screen, gathers them as one page the way a scroll through a document does, then answers
        // it as Scroll & Read's Answer would, question by question, against an optional key.
        if let index = arguments.firstIndex(of: "--gather-images") {
            let paths = arguments[(index + 1)...].prefix { !$0.hasPrefix("--") }
            let key = arguments.firstIndex(of: "--key").map { Array(arguments[$0 + 1]).map(String.init) } ?? []
            let service = ScreenAnswersService()
            var done = false
            Task {
                var lines: [String] = []
                for path in paths {
                    guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                          let text = try? await ScreenAnswersService.recognizeText(in: image) else { print("FAIL \(path)"); continue }
                    // Concatenated, not merged: pictures of separate pages share no lines to line up on.
                    lines += text.components(separatedBy: .newlines)
                }
                let questions = QuestionSplitter.carryPassages(QuestionSplitter.split(lines.joined(separator: "\n"), limit: ScreenAnswersService.ReadLimits.gathered.questions))
                print("\(lines.count) lines, \(questions.count) questions")
                var right = 0
                for (n, question) in questions.enumerated() {
                    let first = question.text.components(separatedBy: .newlines).first ?? ""
                    print(String(format: "%2d  passage %4d  options %@  %@", n + 1, question.passage.count,
                                 QuestionSplitter.hasOptions(question.text) ? "y" : "n", String(first.prefix(70))))
                    if arguments.contains("--show-lines"), let quoted = QuestionSplitter.referencedLines(question: question.text, passage: question.passage) {
                        print("      " + quoted.replacingOccurrences(of: "\n", with: "\n      "))
                    }
                    guard !arguments.contains("--split-only") else { continue }
                    #if canImport(FoundationModels)
                    if #available(macOS 26, *) {
                        do {
                            let result = try await service.answerOne(question) { _ in }
                            let expected = key.indices.contains(n) ? key[n] : "?"
                            if result.letter == expected { right += 1 }
                            print("      → \(result.letter ?? "-") (key \(expected))  \(result.reply.prefix(80).replacingOccurrences(of: "\n", with: " "))")
                        } catch {
                            print("      FAIL \(error)")
                        }
                    }
                    #endif
                }
                if !key.isEmpty, !arguments.contains("--split-only") { print("right \(right) of \(key.count)") }
                done = true
            }
            while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
            return true
        }

        // `--long` answers a gathered page of twenty questions, more than one screen's twelve.
        if arguments.contains("--long") {
            let page = (1...20).map { "\($0). What is \($0 * 7) + \($0 * 3)?" }.joined(separator: "\n")
            let service = ScreenAnswersService()
            var done = false
            Task {
                do { try await service.answerGathered(page) } catch { print("FAIL \(error)") }
                let answers = service.answer.components(separatedBy: "\n").filter { $0.hasPrefix("→") }
                let right = (1...20).filter { n in answers.indices.contains(n - 1) && answers[n - 1].contains("\(n * 10)") }.count
                print("answered \(answers.count) of 20, right \(right)")
                done = true
            }
            while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
            return true
        }

        print("model: \(ScreenAnswersService.modelAvailability)")

        let image: CGImage
        if let index = arguments.firstIndex(of: "--image"), index + 1 < arguments.count {
            guard let loaded = NSImage(contentsOfFile: arguments[index + 1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                print("FAIL could not open \(arguments[index + 1])")
                return true
            }
            image = loaded
        } else if let index = arguments.firstIndex(of: "--text"), index + 1 < arguments.count {
            image = render(arguments[index + 1].replacingOccurrences(of: "\\n", with: "\n"))
        } else {
            image = render(samplePage)
        }

        let service = ScreenAnswersService()
        service.usesCalculator = !arguments.contains("--no-calc")
        var done = false
        let started = Date()
        Task {
            do {
                let text = try await ScreenAnswersService.recognizeText(in: image)
                print(String(format: "read in %.2f s:\n---\n%@\n---", Date().timeIntervalSince(started), text))
                let thinking = Date()
                try await service.answerQuestions(in: text)
                print(String(format: "answered in %.2f s (%@):\n---\n%@\n---",
                             Date().timeIntervalSince(thinking), String(describing: service.phase), service.answer))
                print("letters for the notch: \(service.letters.isEmpty ? "none" : service.letters.joined(separator: " "))")
            } catch {
                print("FAIL \(error)")
            }
            done = true
        }
        while !done, Date().timeIntervalSince(started) < 120 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        if !done { print("FAIL no answer within two minutes") }
        return true
    }

    private struct EvalItem: Decodable { var page: String; var answer: String }

    /// Prints one line per question, its letters over the runs, and the share right overall.
    private static func runEval(path: String, runs: Int) {
        let arguments = CommandLine.arguments
        guard let data = FileManager.default.contents(atPath: path),
              let items = try? JSONDecoder().decode([EvalItem].self, from: data) else {
            print("FAIL could not read \(path)")
            return
        }
        var done = false
        Task {
            var right = 0, total = 0
            for (number, item) in items.enumerated() {
                var got: [String] = []
                var wrongReply: String?
                for _ in 0..<runs {
                    let service = ScreenAnswersService()
                    service.usesReasonedChoice = arguments.contains("--reasoned")
                    service.fillsBlanks = arguments.contains("--fill")
                    if arguments.contains("--greedy") { service.choosesGreedily = true }
                    do { try await service.answerQuestions(in: item.page) } catch { wrongReply = "error: \(error)" }
                    let letter = service.letters.first ?? "?"
                    got.append(letter)
                    if letter != item.answer, wrongReply == nil { wrongReply = service.answer }
                }
                let hits = got.filter { $0 == item.answer }.count
                right += hits
                total += runs
                print(String(format: "%2d  want %@  got %@  %d/%d", number + 1, item.answer, got.joined(separator: " "), hits, runs))
                if arguments.contains("--show-wrong"), let wrongReply {
                    print("      " + wrongReply.replacingOccurrences(of: "\n", with: "\n      ").prefix(400))
                }
            }
            print(String(format: "right: %d of %d (%.0f%%)", right, total, 100 * Double(right) / Double(max(total, 1))))
            done = true
        }
        let started = Date()
        while !done, Date().timeIntervalSince(started) < 900 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
    }

    /// The page as a screen would show it: dark text on white, at 2x.
    private static func render(_ text: String) -> CGImage {
        let size = CGSize(width: 1200, height: 700)
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(.white)
        context.fill(CGRect(origin: .zero, size: size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30),
            .foregroundColor: NSColor.black,
        ]
        (text as NSString).draw(in: CGRect(x: 60, y: 40, width: size.width - 120, height: size.height - 100), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }
}
#endif

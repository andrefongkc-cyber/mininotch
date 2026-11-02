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

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

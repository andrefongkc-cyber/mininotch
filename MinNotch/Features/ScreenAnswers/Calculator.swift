import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Arithmetic worked out exactly, for a language model that cannot do it.
///
/// Apple's on-device model is small, and small models guess at sums: "it is really bad at
/// math" (2026-11-02). Given this as a tool, the model writes the expression and the number
/// comes from here. A parser of its own rather than `NSExpression`, because the expression is
/// written from text on someone's screen, and `NSExpression` will call methods by name from a
/// format string and raises an Objective-C exception, which Swift cannot catch, on bad input.
///
/// Numbers, `+ - * / ^`, `×` and `÷`, parentheses, unary minus, a trailing `%` (hundredths),
/// and `sqrt( )`. Anything else is an error, never a guess.
enum Calculator {
    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    static func evaluate(_ expression: String) throws -> Double {
        var parser = Parser(Array(expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "√", with: "sqrt")
            .replacingOccurrences(of: ",", with: "")
            .lowercased()
            .filter { !$0.isWhitespace }))
        let value = try parser.expression()
        guard parser.isAtEnd else { throw Failure(description: "unexpected \"\(parser.rest)\"") }
        guard value.isFinite else { throw Failure(description: "the result is not a number") }
        return value
    }

    /// `408`, `0.75`, `1.416667`: whole numbers without a point, others to six places at most.
    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    private struct Parser {
        let characters: [Character]
        var index = 0
        var depth = 0

        init(_ characters: [Character]) { self.characters = characters }

        var isAtEnd: Bool { index >= characters.count }
        var rest: String { String(characters[index...]) }
        private var current: Character? { isAtEnd ? nil : characters[index] }

        mutating func expression() throws -> Double {
            var value = try term()
            while let c = current, c == "+" || c == "-" {
                index += 1
                value = c == "+" ? value + (try term()) : value - (try term())
            }
            return value
        }

        private mutating func term() throws -> Double {
            var value = try power()
            while let c = current, c == "*" || c == "/" {
                index += 1
                let right = try power()
                if c == "/" {
                    guard right != 0 else { throw Failure(description: "division by zero") }
                    value /= right
                } else {
                    value *= right
                }
            }
            return value
        }

        private mutating func power() throws -> Double {
            let base = try unary()
            guard current == "^" else { return base }
            index += 1
            return pow(base, try power())
        }

        private mutating func unary() throws -> Double {
            if current == "-" { index += 1; return -(try unary()) }
            if current == "+" { index += 1; return try unary() }
            var value = try primary()
            while current == "%" { index += 1; value /= 100 }
            return value
        }

        private mutating func primary() throws -> Double {
            // Deep enough for any real sum, shallow enough that "((((…" cannot exhaust the stack.
            depth += 1
            defer { depth -= 1 }
            guard depth < 64 else { throw Failure(description: "too deeply nested") }

            if characters[index...].starts(with: "sqrt") {
                index += 4
                let value = try primary()
                guard value >= 0 else { throw Failure(description: "square root of a negative number") }
                return value.squareRoot()
            }
            if current == "(" {
                index += 1
                let value = try expression()
                guard current == ")" else { throw Failure(description: "missing )") }
                index += 1
                return value
            }
            let start = index
            while let c = current, c.isNumber || c == "." { index += 1 }
            guard index > start, let value = Double(String(characters[start..<index])) else {
                throw Failure(description: isAtEnd ? "the expression ends early" : "unexpected \"\(rest)\"")
            }
            return value
        }
    }
}

/// Solves a one-unknown linear equation exactly: "5x - 3 = 2x + 12" is x = 5.
///
/// The model cannot do this reliably even with the calculator, which only does numbers: it
/// answered x = 7 for that one (2026-11-02). An equation that is linear in its one letter is a
/// straight line, so its value at three points says everything: two to find where it crosses
/// zero, a third to check it really is a line. Anything else (x², two letters, no "=") is left
/// to the model.
enum EquationSolver {
    struct Solution: Equatable {
        var variable: Character
        var value: Double
        var text: String { "\(variable) = \(Calculator.format(value))" }
    }

    /// The equation in `question`, solved, or nil when there is none it can solve.
    static func solve(in question: String) -> Solution? {
        for line in question.components(separatedBy: .newlines) {
            if let solution = solveLine(line) { return solution }
        }
        return nil
    }

    private static func solveLine(_ line: String) -> Solution? {
        // The equation is the run of maths around the "=": "Solve for x: 5x - 3 = 2x + 12".
        guard let range = line.range(of: #"[-+(\d.a-zA-Z\s*/^×÷−]*[a-zA-Z0-9)]\s*=\s*[-+(\d.a-zA-Z\s*/^×÷−]*[a-zA-Z0-9)]"#,
                                     options: .regularExpression) else { return nil }
        var equation = String(line[range])
        // Drop the words before it: keep from the first character that belongs to maths and
        // is not part of a word ("for x: 5x" leaves "5x").
        let sides = equation.split(separator: "=", omittingEmptySubsequences: false)
        guard sides.count == 2 else { return nil }
        let left = trimWords(String(sides[0])), right = trimWords(String(sides[1]))
        equation = left + "=" + right
        let letters = Set(equation.filter(\.isLetter).map { Character($0.lowercased()) })
        guard letters.count == 1, let variable = letters.first,
              !left.isEmpty, !right.isEmpty else { return nil }

        func f(_ x: Double) -> Double? {
            guard let l = try? Calculator.evaluate(substitute(left, variable, x)),
                  let r = try? Calculator.evaluate(substitute(right, variable, x)) else { return nil }
            return l - r
        }
        guard let f0 = f(0), let f1 = f(1), let f2 = f(2) else { return nil }
        let slope = f1 - f0
        // A straight line, and one that crosses zero once.
        guard abs(slope) > 1e-12, abs((f2 - f1) - slope) < 1e-9 * max(1, abs(slope)) else { return nil }
        let value = -f0 / slope
        guard value.isFinite else { return nil }
        return Solution(variable: variable, value: abs(value) < 1e-12 ? 0 : value)
    }

    /// One side without the words in front of it: "Solve for x: 5x - 3" is "5x - 3".
    private static func trimWords(_ side: String) -> String {
        var text = side
        if let colon = text.lastIndex(of: ":") { text = String(text[text.index(after: colon)...]) }
        // A word of two or more letters is prose, not maths; keep what follows the last one.
        if let word = text.range(of: #"(?i)^.*\b[a-z]{2,}\b"#, options: .regularExpression),
           !text[word].lowercased().hasSuffix("sqrt") {
            text = String(text[word.upperBound...])
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// The side with the letter replaced by a number, and the multiplication written out:
    /// "5x" is "5*(2)", "2(x + 3)" is "2*((2) + 3)".
    private static func substitute(_ side: String, _ variable: Character, _ value: Double) -> String {
        var text = side.lowercased()
        text = text.replacingOccurrences(of: #"(\d|\))\s*(?=[a-z(])"#, with: "$1*", options: .regularExpression)
        text = text.replacingOccurrences(of: #"([a-z])\s*(?=[\d(])"#, with: "$1*", options: .regularExpression)
        // Undo the "*" put inside "sqrt(" by the line above.
        text = text.replacingOccurrences(of: "sqrt*(", with: "sqrt(")
        return text.replacingOccurrences(of: String(variable), with: "(\(value))")
    }
}

#if canImport(FoundationModels)
/// A multiple-choice reply: the reasoning first, so the letter is chosen after it, and a letter
/// that can only be one of the options' letters.
@available(macOS 26, *)
@Generable
struct ChoiceReply {
    @Guide(description: "One or two sentences checking the options against the text, or naming the grammar rule that decides it")
    var reasoning: String
    @Guide(description: "The letter of the one right option", .anyOf(["A", "B", "C", "D", "E"]))
    var letter: String
}

/// The calculator as Apple's model sees it.
@available(macOS 26, *)
struct CalculatorTool: Tool {
    let name = "calculate"
    let description = "Works out arithmetic on numbers exactly: + - * / ^, parentheses, % and sqrt(). Numbers only: it cannot solve an equation or use a letter such as x."

    /// The calls one question may make. Given algebra, the model asked again and again with the
    /// same "4x = 52" or "x^2" until its 4,096-token context was full (2026-11-02).
    static let callLimit = 4
    let calls = CallCount()

    @Generable
    struct Arguments {
        @Guide(description: "Numbers and operators only, such as \"17 * 24\" or \"(22 - 7) / 3\" or \"15% * 240\"")
        var expression: String
    }

    func call(arguments: Arguments) async throws -> String {
        #if DEBUG
        if CommandLine.arguments.contains("--check-answers") { print("  calculate(\(arguments.expression))") }
        #endif
        guard calls.next() <= Self.callLimit else {
            return "Do not call calculate again. Answer the question now with what you have."
        }
        // "x = 52 / 4": the model's own working, whose right-hand side is a sum.
        var expression = arguments.expression
        if let match = expression.range(of: #"^\s*[A-Za-z]\s*=\s*"#, options: .regularExpression) {
            expression = String(expression[match.upperBound...])
        }
        if expression.contains("=") || expression.contains(where: { $0.isLetter && !"sqrt".contains($0.lowercased()) }) {
            return "The calculator only works with numbers; it cannot solve equations or use letters. Do not call it for this. Work it out yourself and answer."
        }
        do {
            return Calculator.format(try Calculator.evaluate(expression))
        } catch let failure as Calculator.Failure {
            return "Could not work that out: \(failure.description). Do not call it again with the same thing; answer the question."
        }
    }

    /// Calls made in one session. A class with a lock because the tool is a `Sendable` value
    /// that the framework may call from any thread.
    final class CallCount: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func next() -> Int { lock.withLock { count += 1; return count } }
    }
}
#endif

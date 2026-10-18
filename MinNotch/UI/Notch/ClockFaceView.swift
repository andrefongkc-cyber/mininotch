import SwiftUI

/// The pop-out timer's time in a mechanical style, chosen from the window: split-flap cards, a
/// seven-segment display whose segments are paddles that turn over, or one whose segments are bars
/// a rack pushes out of the plate and draws back in. Sized to the room it is given, like `BigTime`.
///
/// Every digit animates when it changes, as fast as it can and still finish before the next
/// change: whole seconds and up take the full movement, tenths a quick one, and hundredths change
/// at once, because no mechanism turns over a hundred times a second.
struct ClockFaceView: View {
    var text: String
    var style: TimerClockStyle
    var space: CGSize

    private struct Cell: Identifiable {
        /// Counted from the right, so the seconds keep their identity when the time gains a digit.
        let id: Int
        let character: Character
        /// Seconds between changes of this digit: 0.01 for hundredths, 1 or more for the rest.
        let period: TimeInterval
    }

    private var cells: [Cell] {
        let characters = Array(text)
        let point = characters.firstIndex(of: ".")
        return characters.enumerated().map { index, character in
            var period: TimeInterval = 1
            if let point, index > point { period = pow(10, -Double(index - point)) }
            return Cell(id: characters.count - 1 - index, character: character, period: period)
        }
    }

    private var metrics: Metrics { Metrics(style: style) }

    /// The digit height that fits the text in the space.
    private var digitHeight: CGFloat {
        let cells = cells
        let digits = CGFloat(cells.filter(\.character.isNumber).count)
        let separators = CGFloat(cells.count) - digits
        let m = metrics
        let widthPerHeight = digits * m.digitAspect + separators * m.separatorAspect
            + CGFloat(max(cells.count - 1, 0)) * m.gap + 2 * m.platePadding
        let byWidth = space.width * 0.92 / max(widthPerHeight, 0.1)
        // A little short of the height too, so cards do not butt against the lines above and below.
        let byHeight = space.height * 0.9 / (1 + 2 * m.platePadding)
        return max(10, floor(min(byWidth, byHeight)))
    }

    var body: some View {
        let height = digitHeight
        let m = metrics
        HStack(spacing: height * m.gap) {
            ForEach(cells) { cell in
                if cell.character.isNumber {
                    digit(cell, height: height)
                } else {
                    Separator(character: cell.character, style: style, height: height)
                        .frame(width: height * m.separatorAspect, height: height)
                }
            }
        }
        .padding(height * m.platePadding)
        .background {
            if style == .segments || style == .rack {
                // The display's housing: a black plate the segments sit in, whatever the window.
                RoundedRectangle(cornerRadius: height * 0.12, style: .continuous)
                    .fill(Color(white: 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: height * 0.12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
        }
        .frame(width: space.width, height: space.height)
    }

    @ViewBuilder
    private func digit(_ cell: Cell, height: CGFloat) -> some View {
        let size = CGSize(width: height * metrics.digitAspect, height: height)
        switch style {
        case .flip:
            FlipDigit(digit: cell.character, size: size, duration: Self.duration(for: cell.period, full: 0.5))
        case .rack:
            RackDigit(digit: cell.character, size: size, duration: Self.duration(for: cell.period, full: 0.45))
        case .segments, .plain:
            SegmentDigit(digit: cell.character, size: size, response: Self.duration(for: cell.period, full: 0.3))
        }
    }

    /// The full movement for a digit that changes once a second or slower, a quicker one for
    /// tenths, none for hundredths.
    private static func duration(for period: TimeInterval, full: TimeInterval) -> TimeInterval? {
        let fitted = min(full, period * 0.6)
        return fitted < 0.04 ? nil : fitted
    }

    private struct Metrics {
        var digitAspect: CGFloat
        var separatorAspect: CGFloat
        var gap: CGFloat
        var platePadding: CGFloat

        init(style: TimerClockStyle) {
            switch style {
            case .flip: self.init(digitAspect: 0.68, separatorAspect: 0.2, gap: 0.05, platePadding: 0)
            case .segments, .rack, .plain: self.init(digitAspect: 0.56, separatorAspect: 0.18, gap: 0.12, platePadding: 0.14)
            }
        }

        init(digitAspect: CGFloat, separatorAspect: CGFloat, gap: CGFloat, platePadding: CGFloat) {
            self.digitAspect = digitAspect
            self.separatorAspect = separatorAspect
            self.gap = gap
            self.platePadding = platePadding
        }
    }
}

// MARK: - Colours

/// A mechanical display looks the same in any Notch Style: black cards with white figures, a black
/// plate with yellow paddles, or one with white bars, as the real things are.
private enum ClockColors {
    static let card = Color(white: 0.13)
    static let cardTop = Color(white: 0.16)
    static let figure = Color(white: 0.94)
    static let segmentOn = Color(red: 1.0, green: 0.84, blue: 0.25)
    static let segmentOff = Color(white: 0.1)
    static let slot = Color(white: 0.015)
    static let barSide = Color(white: 0.5)
}

// MARK: - Separators

private struct Separator: View {
    var character: Character
    var style: TimerClockStyle
    var height: CGFloat

    var body: some View {
        let dot = height * (style == .flip ? 0.1 : 0.11)
        let color: Color = switch style {
        case .flip: ClockColors.figure.opacity(0.85)
        case .rack: ClockColors.figure
        default: ClockColors.segmentOn
        }
        Group {
            if character == ":" {
                VStack(spacing: height * 0.26) {
                    dotShape(dot, color)
                    dotShape(dot, color)
                }
            } else {
                // The decimal point sits on the baseline.
                dotShape(dot, color)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, style == .flip ? height * 0.12 : height * 0.02)
            }
        }
    }

    @ViewBuilder
    private func dotShape(_ size: CGFloat, _ color: Color) -> some View {
        if style == .flip {
            Circle().fill(color).frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.2).fill(color).frame(width: size, height: size)
        }
    }
}

// MARK: - Flip clock

/// One split-flap card. A change counts `target` up by one at once and animates `flips` after it,
/// and `FlipCard` draws how far `flips` has to go as how far the flap has fallen.
///
/// The card draws the digit it has taken on (`shown`), not the one passed in, and is only at rest
/// while `flips` has caught up with `target`. It used to draw the incoming digit and call any whole
/// number of flips rest, so a change showed the new digit whole for the frame before the flip began
/// and again on the flip's first frame, then the old one under the falling flap: 25 flashed 26,
/// went back to 25, and flipped to 26 (the user's report). `--check-flip` records every frame.
private struct FlipDigit: View {
    var digit: Character
    var size: CGSize
    var duration: TimeInterval?

    /// Taken from the first digit when the card is made, and after that only from a change.
    @State private var shown: Character
    @State private var previous: Character?
    @State private var flips: Double = 0
    @State private var target: Double = 0

    init(digit: Character, size: CGSize, duration: TimeInterval?) {
        self.digit = digit
        self.size = size
        self.duration = duration
        _shown = State(initialValue: digit)
    }

    var body: some View {
        FlipCard(old: previous ?? shown, new: shown, flips: flips, target: target, size: size)
            .onChange(of: digit) { _, new in
                previous = shown
                shown = new
                target += 1
                if let duration {
                    withAnimation(.linear(duration: duration)) { flips = target }
                } else {
                    var instant = Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) { flips = target }
                }
            }
    }
}

private struct FlipCard: View, Animatable {
    var old: Character
    var new: Character
    var flips: Double
    /// Where `flips` is going; not animated.
    var target: Double
    var size: CGSize

    nonisolated var animatableData: Double {
        get { flips }
        set { flips = newValue }
    }

    /// 0 as a flip starts, through to 1 as the flap lands; nil at rest. A change that arrives
    /// mid-flip starts over from the digit already showing.
    private var progress: Double? {
        let remaining = target - flips
        guard remaining > 0.0001 else { return nil }
        return min(max(1 - remaining, 0), 1)
    }

    var body: some View {
        let p = progress
        let half = size.height / 2
        let falling = p.map { $0 < 0.5 } ?? false
        let landing = p.map { $0 >= 0.5 } ?? false
        let land = p.map(Self.landing) ?? 1
        #if DEBUG
        let _ = Self.debugRecord?("\(falling ? old : new)\(landing && land > 0.5 ? new : (p == nil ? new : old))")
        #endif
        VStack(spacing: 0) {
            ZStack {
                // Behind the falling flap, the new digit's top half is already there.
                CardHalf(digit: new, size: size, top: true)
                if falling, let p {
                    // The old top half falls forward on its hinge, speeding up like a real flap.
                    let fall = pow(p / 0.5, 2)
                    CardHalf(digit: old, size: size, top: true)
                        .overlay(Color.black.opacity(0.45 * fall))
                        .rotation3DEffect(.degrees(-90 * fall), axis: (x: 1, y: 0, z: 0),
                                          anchor: .bottom, perspective: 0.45)
                }
            }
            .frame(height: half)
            .zIndex(falling ? 1 : 0)

            ZStack {
                // Until the new bottom half lands on it, the old one stays, shadowed by the flap.
                CardHalf(digit: p == nil ? new : old, size: size, top: false)
                    .overlay(Color.black.opacity(p.map { landing ? 0.3 * (1 - land) : 0.3 * $0 / 0.5 } ?? 0))
                if landing {
                    CardHalf(digit: new, size: size, top: false)
                        .overlay(Color.black.opacity(0.35 * (1 - min(land, 1))))
                        .rotation3DEffect(.degrees(90 * (1 - land)), axis: (x: 1, y: 0, z: 0),
                                          anchor: .top, perspective: 0.45)
                }
            }
            .frame(height: half)
            .zIndex(landing ? 1 : 0)
        }
        .frame(width: size.width, height: size.height)
    }

    #if DEBUG
    /// Each frame's visible top and bottom digit, for `--check-flip`.
    static var debugRecord: ((String) -> Void)?
    #endif

    /// The bottom flap's travel, 0 to 1 over the second half, with a small bounce as it lands.
    private static func landing(_ p: Double) -> Double {
        let q = (p - 0.5) / 0.5
        if q < 0.7 { return pow(q / 0.7, 2) }
        return 1 - 0.1 * sin(.pi * (q - 0.7) / 0.3)
    }
}

/// The top or bottom half of a card, with the split line along its inner edge.
private struct CardHalf: View {
    var digit: Character
    var size: CGSize
    var top: Bool

    var body: some View {
        let radius = size.height * 0.07
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: top ? radius : 0,
                bottomLeadingRadius: top ? 0 : radius,
                bottomTrailingRadius: top ? 0 : radius,
                topTrailingRadius: top ? radius : 0,
                style: .continuous
            )
            .fill(top ? ClockColors.cardTop : ClockColors.card)

            Text(String(digit))
                .font(.system(size: size.height * 0.8, weight: .bold).width(.condensed).monospacedDigit())
                .foregroundStyle(ClockColors.figure)
                .frame(width: size.width, height: size.height)
                .frame(height: size.height / 2, alignment: top ? .top : .bottom)
                .clipped()
        }
        .frame(width: size.width, height: size.height / 2)
        .overlay(alignment: top ? .bottom : .top) {
            // The gap between the two halves.
            Rectangle()
                .fill(Color.black.opacity(0.7))
                .frame(height: max(1, size.height * 0.012))
        }
    }
}

// MARK: - Seven segment

/// One digit of a mechanical seven-segment display. Each segment is a paddle, yellow on one face
/// and black on the other, that turns over on its long axis when it changes, with a little
/// overshoot as it settles, the way a magnet-driven segment snaps round.
private struct SegmentDigit: View {
    var digit: Character
    var size: CGSize
    var response: TimeInterval?

    var body: some View {
        let lit = SevenSegment.segments(for: digit)
        ZStack {
            ForEach(SevenSegment.allCases, id: \.self) { segment in
                SegmentPaddle(segment: segment, angle: lit.contains(segment) ? 180 : 0, size: size)
                    .animation(response.map { .spring(response: $0, dampingFraction: 0.5) },
                               value: lit.contains(segment))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

private enum SevenSegment: CaseIterable {
    case a, b, c, d, e, f, g

    static func segments(for digit: Character) -> Set<SevenSegment> {
        switch digit {
        case "0": return [.a, .b, .c, .d, .e, .f]
        case "1": return [.b, .c]
        case "2": return [.a, .b, .g, .e, .d]
        case "3": return [.a, .b, .g, .c, .d]
        case "4": return [.f, .g, .b, .c]
        case "5": return [.a, .f, .g, .c, .d]
        case "6": return [.a, .f, .g, .e, .d, .c]
        case "7": return [.a, .b, .c]
        case "8": return Set(allCases)
        case "9": return [.a, .b, .c, .d, .f, .g]
        default: return []
        }
    }

    var isHorizontal: Bool { self == .a || self == .d || self == .g }

    /// The segment's centre line in a cell of this size, end to end.
    func line(in size: CGSize, thickness t: CGFloat) -> (CGPoint, CGPoint) {
        let w = size.width, h = size.height
        let left = t / 2, right = w - t / 2, top = t / 2, middle = h / 2, bottom = h - t / 2
        switch self {
        case .a: return (CGPoint(x: left, y: top), CGPoint(x: right, y: top))
        case .g: return (CGPoint(x: left, y: middle), CGPoint(x: right, y: middle))
        case .d: return (CGPoint(x: left, y: bottom), CGPoint(x: right, y: bottom))
        case .f: return (CGPoint(x: left, y: top), CGPoint(x: left, y: middle))
        case .b: return (CGPoint(x: right, y: top), CGPoint(x: right, y: middle))
        case .e: return (CGPoint(x: left, y: middle), CGPoint(x: left, y: bottom))
        case .c: return (CGPoint(x: right, y: middle), CGPoint(x: right, y: bottom))
        }
    }
}

private struct SegmentPaddle: View, Animatable {
    var segment: SevenSegment
    /// 0 shows the black face, 180 the yellow one; the spring carries it a little past either.
    var angle: Double
    var size: CGSize

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let thickness = size.width * 0.2
        let (start, end) = segment.line(in: size, thickness: thickness)
        let centre = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let showsLit = cos(angle * .pi / 180) < 0
        let shape = SegmentShape(start: start, end: end, thickness: thickness, gap: thickness * 0.22)
        ZStack {
            if showsLit {
                shape.fill(ClockColors.segmentOn)
                // A paddle turned partway catches less light.
                shape.fill(Color.black.opacity(0.35 * (1 - abs(cos(angle * .pi / 180)))))
            } else {
                shape.fill(ClockColors.segmentOff)
                shape.stroke(Color.white.opacity(0.06), lineWidth: 0.75)
            }
        }
        .frame(width: size.width, height: size.height)
        .rotation3DEffect(
            .degrees(angle),
            axis: segment.isHorizontal ? (x: 1, y: 0, z: 0) : (x: 0, y: 1, z: 0),
            anchor: UnitPoint(x: centre.x / size.width, y: centre.y / size.height),
            perspective: 0.3
        )
    }
}

// MARK: - Rack segments

/// One digit of a rack-driven display: each segment is a white bar that a rack pushes out of its
/// slot in the plate, or draws back in, at the even, geared pace of a pinion turning, with no
/// bounce. Out, it stands proud of the plate, lit from the top left, with its side and its shadow
/// showing; in, it sits deep in the dark slot.
private struct RackDigit: View {
    var digit: Character
    var size: CGSize
    var duration: TimeInterval?

    var body: some View {
        let lit = SevenSegment.segments(for: digit)
        ZStack {
            ForEach(SevenSegment.allCases, id: \.self) { segment in
                RackBar(segment: segment, travel: lit.contains(segment) ? 1 : 0, size: size)
                    .animation(duration.map { .timingCurve(0.45, 0, 0.55, 1, duration: $0) },
                               value: lit.contains(segment))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct RackBar: View, Animatable {
    var segment: SevenSegment
    /// 0 drawn back into the slot, 1 pushed all the way out.
    var travel: Double
    var size: CGSize

    nonisolated var animatableData: Double {
        get { travel }
        set { travel = newValue }
    }

    var body: some View {
        let thickness = size.width * 0.2
        let (start, end) = segment.line(in: size, thickness: thickness)
        let anchor = UnitPoint(x: (start.x + end.x) / 2 / size.width, y: (start.y + end.y) / 2 / size.height)
        let shape = SegmentShape(start: start, end: end, thickness: thickness, gap: thickness * 0.22)
        let t = min(max(travel, 0), 1)
        let depth = thickness * 0.6 * t
        // Shaded only while deep in the slot: once its face clears the lip it is in the light.
        let light = pow(t, 0.6)
        ZStack {
            // The slot the bar slides in and out of.
            shape.fill(ClockColors.slot)
            shape.stroke(Color.white.opacity(0.07), lineWidth: 0.75)
            // Its shadow on the plate, longer the further out it stands.
            shape.fill(Color.black.opacity(0.7 * t))
                .offset(x: depth, y: depth)
            // The bar's side, between its face and its shadow.
            shape.fill(ClockColors.barSide.opacity(t > 0.01 ? 1 : 0))
                .scaleEffect(0.86 + 0.14 * t, anchor: anchor)
                .offset(x: depth * 0.45, y: depth * 0.45)
            // The face: deep in the slot it is small and in shade; out, full size, white, and a
            // little towards the light.
            shape.fill(Color(white: 0.17 + 0.77 * light))
                .scaleEffect(0.86 + 0.14 * t, anchor: anchor)
                .offset(x: -depth * 0.3, y: -depth * 0.3)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// A segment's outline: a bar with pointed ends, shortened by `gap` so neighbours do not touch.
private struct SegmentShape: Shape {
    var start: CGPoint
    var end: CGPoint
    var thickness: CGFloat
    var gap: CGFloat

    func path(in rect: CGRect) -> Path {
        let horizontal = abs(end.y - start.y) < abs(end.x - start.x)
        let half = thickness / 2
        var path = Path()
        if horizontal {
            let y = start.y, x0 = start.x + gap, x1 = end.x - gap
            path.move(to: CGPoint(x: x0, y: y))
            path.addLine(to: CGPoint(x: x0 + half, y: y - half))
            path.addLine(to: CGPoint(x: x1 - half, y: y - half))
            path.addLine(to: CGPoint(x: x1, y: y))
            path.addLine(to: CGPoint(x: x1 - half, y: y + half))
            path.addLine(to: CGPoint(x: x0 + half, y: y + half))
        } else {
            let x = start.x, y0 = start.y + gap, y1 = end.y - gap
            path.move(to: CGPoint(x: x, y: y0))
            path.addLine(to: CGPoint(x: x + half, y: y0 + half))
            path.addLine(to: CGPoint(x: x + half, y: y1 - half))
            path.addLine(to: CGPoint(x: x, y: y1))
            path.addLine(to: CGPoint(x: x - half, y: y1 - half))
            path.addLine(to: CGPoint(x: x - half, y: y0 + half))
        }
        path.closeSubpath()
        return path
    }
}

#if DEBUG
/// Each clock style's movement frozen at fixed points, a 7 turning into an 8, for
/// `MiniNotch --clock-frames`. A layer capture does not draw the 3D turn of a flap or a paddle,
/// so this is put in a real window and read back with `screencapture -l`.
struct ClockFaceDebugFrames: View {
    var body: some View {
        let card = CGSize(width: 68, height: 100)
        let segment = CGSize(width: 56, height: 100)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ForEach([0, 0.1, 0.2, 0.3, 0.42, 0.55, 0.7, 0.85, 1], id: \.self) { p in
                    FlipCard(old: "7", new: "8", flips: p, target: 1, size: card)
                }
            }
            HStack(spacing: 14) {
                ForEach([0.0, 30, 60, 80, 100, 130, 160, 180, 195], id: \.self) { angle in
                    ZStack {
                        ForEach(SevenSegment.allCases, id: \.self) { s in
                            SegmentPaddle(segment: s, angle: Self.angle(s, changing: angle), size: segment)
                        }
                    }
                    .frame(width: segment.width, height: segment.height)
                    .padding(6)
                    .background(Color(white: 0.04))
                }
            }
            HStack(spacing: 14) {
                ForEach([0.0, 0.15, 0.3, 0.5, 0.7, 0.85, 1], id: \.self) { travel in
                    ZStack {
                        ForEach(SevenSegment.allCases, id: \.self) { s in
                            RackBar(segment: s, travel: Self.travel(s, changing: travel), size: segment)
                        }
                    }
                    .frame(width: segment.width, height: segment.height)
                    .padding(6)
                    .background(Color(white: 0.04))
                }
            }
        }
        .padding(20)
        .background(Color.black)
    }

    private static let seven = SevenSegment.segments(for: "7")
    private static let eight = SevenSegment.segments(for: "8")

    private static func angle(_ s: SevenSegment, changing angle: Double) -> Double {
        seven.contains(s) ? 180 : (eight.contains(s) ? angle : 0)
    }

    private static func travel(_ s: SevenSegment, changing travel: Double) -> Double {
        seven.contains(s) ? 1 : (eight.contains(s) ? travel : 0)
    }
}

/// One card turning 5 into 6 at half a second, for `--check-flip`, which reads what it shows on
/// every frame through `record`.
struct FlipDigitDebugHost: View {
    static func record(_ handler: ((String) -> Void)?) { FlipCard.debugRecord = handler }

    @State private var digit: Character = "5"

    var body: some View {
        FlipDigit(digit: digit, size: CGSize(width: 68, height: 100), duration: 0.5)
            .padding(20)
            .background(Color.black)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { digit = "6" }
            }
    }
}
#endif

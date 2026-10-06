import SwiftUI

/// A miniature of the open notch in a style, for Settings > Appearance > Notch Style.
///
/// Built from the parts the notch itself draws with: the surface, a module, the artwork's
/// treatment, the groove under a progress bar, and the transport discs, all reading the style
/// from the environment. A preview that drew its own idea of a style would drift from the real
/// thing the first time either changed.
struct NotchStylePreview: View {
    let style: NotchStyle
    var accent: Color = Palette.controlAccent
    /// Draws the camera housing as the black tab the open panel shows on a Mac that has one.
    var showsHousing = false

    static let size = CGSize(width: 168, height: 84)

    private var shape: NotchShape { NotchShape(shoulderRadius: 5, bottomRadius: 14) }

    var body: some View {
        ZStack(alignment: .top) {
            NotchSurfaceView(
                style: style.surface,
                isTranslucent: false,
                edge: NotchShape(shoulderRadius: 5, bottomRadius: 14, closesTop: false),
                drawsMaterials: false
            )
            if showsHousing, !style.isHousingBlack {
                NotchShape(shoulderRadius: 0, bottomRadius: 4)
                    .fill(Palette.notchFill)
                    .frame(width: 44, height: 12)
            }
            content
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(shape)
        .background {
            if let shadow = style.surface.shadow {
                shape.fill(shadow.color).offset(y: shadow.y / 2).blur(radius: shadow.radius / 2)
            }
        }
        .environment(\.notchStyle, style)
        .environment(\.colorScheme, style.isDark ? .dark : .light)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The top bar, either side of the housing.
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == 0 ? accent : style.ink.opacity(0.4))
                        .frame(width: 4, height: 4)
                }
                Spacer(minLength: 0)
                Capsule().fill(style.ink.opacity(0.4)).frame(width: 12, height: 4)
            }
            .padding(.horizontal, 6)
            .frame(height: 10)

            HStack(spacing: 8) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Text("Blue Hour")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(style.ink)
                    Text("Aoife Lennox")
                        .font(.system(size: 7.5))
                        .foregroundStyle(style.ink.opacity(0.6))
                    track
                        .padding(.top, 2)
                    transport
                }
            }
            .padding(5)
            .background(NotchElementView(.module, shape: .rounded(9), emphasis: 0.05))
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var artwork: some View {
        let corner = 5 * style.artwork.cornerScale
        return LinearGradient(
            colors: [Color(red: 0.84, green: 0.38, blue: 0.36), Color(red: 0.36, green: 0.27, blue: 0.55)],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            if let border = style.artwork.border {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(border.shapeStyle, lineWidth: border.width)
            }
        }
        .notchShadow(style.artwork.shadow.map { NotchShadow(color: $0.color, radius: $0.radius / 2, x: $0.x / 2, y: $0.y / 2) })
    }

    private var track: some View {
        ZStack(alignment: .leading) {
            NotchElementView(.groove, shape: .capsule, emphasis: 0.18)
            Capsule()
                .fill(accent)
                .frame(width: 34)
        }
        .frame(width: 88, height: 3)
    }

    private var transport: some View {
        HStack(spacing: 7) {
            symbol("backward.fill", primary: false)
            symbol("pause.fill", primary: true)
            symbol("forward.fill", primary: false)
        }
        .padding(.leading, 12)
    }

    private func symbol(_ name: String, primary: Bool) -> some View {
        TransportSymbol.image(name, pointSize: primary ? 10 : 8)
            .foregroundStyle(style.ink.opacity(primary ? 1 : 0.8))
            .frame(width: 16, height: 14)
            .background(
                NotchElementView(primary ? .primaryTransport : .transport, shape: .circle, emphasis: 0.08)
                    .frame(width: primary ? 18 : 15, height: primary ? 18 : 15)
            )
    }
}

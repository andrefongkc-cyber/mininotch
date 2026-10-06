import AppKit
import SwiftUI

/// Settings > Appearance > Notch Style: a tile per design language, each a miniature of the open
/// notch drawn in that language (`NotchStylePreview`), and the light or dark choice under them.
///
/// The tiles show whichever variant is in force, so switching Light or Dark, or the Mac's own
/// appearance under Match System, redraws every tile, and what a tile shows is what clicking it
/// gives.
struct NotchStylePicker: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        @Bindable var settings = settings

        VStack(spacing: 0) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 176), spacing: 12)], spacing: 14) {
                ForEach(NotchDesignLanguage.allCases) { language in
                    tile(language)
                }
            }
            .padding(Metrics.cardHorizontalPadding)

            SettingsDivider()

            SettingsRow(
                title: "Light or Dark",
                subtitle: "Match System follows your Mac.",
                systemImage: "circle.lefthalf.filled"
            ) {
                Picker("", selection: $settings.appearance.notchVariant) {
                    ForEach(NotchStyleVariant.allCases) { variant in
                        Text(variant.title).tag(variant)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            SettingsDivider()

            // Shown everywhere, switched off before macOS 26 with the reason, rather than hidden:
            // someone reading about Liquid Glass should find out why they cannot have it.
            SettingsRow(
                title: "Background",
                subtitle: NotchBackground.isLiquidGlassSupported
                    ? "Liquid Glass bends and blurs what is behind the notch."
                    : "Liquid Glass needs macOS 26 or later.",
                systemImage: "drop",
                isEnabled: NotchBackground.isLiquidGlassSupported
            ) {
                Picker("", selection: Binding(
                    get: { NotchBackground.isLiquidGlassSupported ? settings.appearance.notchBackground : .solid },
                    set: { settings.appearance.notchBackground = $0 }
                )) {
                    ForEach(NotchBackground.allCases) { background in
                        Text(background.title).tag(background)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            SettingsDivider()

            SettingsRow(
                title: "Glass Opacity",
                subtitle: "Lower lets more of the desktop through; higher brings back the style's own colour.",
                systemImage: "circle.dotted.circle",
                isEnabled: NotchBackground.isLiquidGlassSupported && settings.appearance.notchBackground == .liquidGlass
            ) {
                ValueSlider(value: $settings.appearance.liquidGlassOpacity, range: 0...1, step: 0.05) {
                    "\(Int(($0 * 100).rounded()))%"
                }
            }
        }
    }

    private var isDark: Bool {
        switch settings.appearance.notchVariant {
        case .dark: return true
        case .light: return false
        case .system: return environment.systemAppearance.isDark
        }
    }

    /// Whether this Mac has a camera housing, so the previews show the tab the open panel draws
    /// around it.
    private var hasHousing: Bool {
        NSScreen.screens.contains { $0.isBuiltIn && $0.safeAreaInsets.top > 0 }
    }

    private func tile(_ language: NotchDesignLanguage) -> some View {
        let isOffered = NotchStyle.isOffered(language)
        let isSelected = settings.appearance.notchLanguage == language
        let accent = settings.appearance.resolvedAccent

        return Button {
            settings.appearance.notchLanguage = language
        } label: {
            VStack(spacing: 4) {
                preview(language, accent: accent)
                    .frame(maxWidth: .infinity)
                    .background(backdrop)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? accent : Palette.separator, lineWidth: isSelected ? 2 : 1)
                )

                HStack(spacing: 6) {
                    Text(language.title)
                        .font(Typography.bodyEmphasised)
                        .foregroundStyle(isSelected ? Palette.primaryText : Palette.secondaryText)
                    if !isOffered { BadgeView(.comingSoon) }
                }
                .padding(.top, 3)

                Text(language.blurb)
                    .font(Typography.helper)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isOffered)
        .opacity(isOffered ? 1 : 0.55)
        .accessibilityLabel("\(language.title) notch style")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The miniature as a picture: see `NotchStylePreviewCache` for why.
    @ViewBuilder
    private func preview(_ language: NotchDesignLanguage, accent: Color) -> some View {
        let style = NotchStyle.make(language, isDark: isDark)
        if let image = NotchStylePreviewCache.image(for: style, accent: accent, showsHousing: hasHousing, scale: displayScale) {
            Image(nsImage: image)
                .accessibilityHidden(true)
        } else {
            NotchStylePreview(style: style, accent: accent, showsHousing: hasHousing)
                .padding(NotchStylePreviewCache.margin)
        }
    }

    /// A stand-in desktop behind each miniature, mid-toned so a light surface and a dark one both
    /// keep their edges, as they would on a real wallpaper.
    private var backdrop: some View {
        LinearGradient(
            colors: isDark
                ? [Color(red: 0.24, green: 0.27, blue: 0.34), Color(red: 0.12, green: 0.13, blue: 0.17)]
                : [Color(red: 0.72, green: 0.77, blue: 0.86), Color(red: 0.55, green: 0.61, blue: 0.72)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

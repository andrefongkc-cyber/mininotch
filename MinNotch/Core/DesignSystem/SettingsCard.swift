import SwiftUI

/// A rounded-rectangle group of related settings rows, matching a System Settings card.
///
/// Rows are separated by hairline dividers that are inset from the leading edge, exactly
/// like the system panes. Pass rows as a `SettingsRow` list; the divider insertion is
/// handled here so individual rows never have to know their position.
struct SettingsCard<Content: View>: View {
    var header: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            if let header {
                Text(header)
                    .font(Typography.sectionHeader)
                    .foregroundStyle(Palette.primaryText)
                    .padding(.leading, 2)
            }

            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                        .fill(Palette.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                        .strokeBorder(Palette.separator.opacity(0.6), lineWidth: 0.5)
                )

            if let footer {
                Text(footer)
                    .font(Typography.helper)
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.leading, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One control row inside a `SettingsCard`.
///
/// The label column is leading-aligned, the control column trailing-aligned, and an
/// optional helper line sits under the label in secondary grey.
/// The row a Settings search result points at.
///
/// Carries a token that changes every time a result is chosen, so choosing the same result
/// twice still scrolls to it and flashes it. Without the token the second choice is equal to
/// the first, nothing observes a change, and the click appears to do nothing.
struct SettingsSearchTarget: Equatable {
    var tab: SettingsTab
    var title: String
    var token = UUID()
}

private struct SettingsSearchTargetKey: EnvironmentKey {
    static let defaultValue: SettingsSearchTarget? = nil
}

extension EnvironmentValues {
    /// Set by the Settings window while a search result is being shown; read by every row
    /// and pane, so a result can land on a row without any pane knowing search exists.
    var settingsSearchTarget: SettingsSearchTarget? {
        get { self[SettingsSearchTargetKey.self] }
        set { self[SettingsSearchTargetKey.self] = newValue }
    }
}

struct SettingsRow<Control: View>: View {
    var title: String
    var subtitle: String?
    var systemImage: String?
    /// Coloured dot shown in the icon slot, used for per-calendar rows.
    var accentDot: Color?
    var badge: SettingsBadge?
    var isEnabled: Bool = true
    @ViewBuilder var control: Control

    @Environment(\.settingsSearchTarget) private var searchTarget
    @State private var isFlashing = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let accentDot {
                Circle()
                    .fill(accentDot)
                    .frame(width: 9, height: 9)
                    .frame(width: 18)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 18)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(Palette.primaryText)
                    if let badge { BadgeView(badge) }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.helper)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            control
                .labelsHidden()
        }
        .padding(.horizontal, Metrics.cardHorizontalPadding)
        .padding(.vertical, 9)
        .frame(minHeight: subtitle == nil ? Metrics.rowHeight : Metrics.tallRowHeight)
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled)
        // Behind the disabled dimming rather than inside it, so a search that lands on a
        // row which is currently switched off still visibly lands.
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.controlAccent.opacity(isFlashing ? 0.22 : 0))
                .padding(.horizontal, 4)
        )
        // The anchor `SettingsPane` scrolls to. Titles are unique within a pane in practice;
        // where one is not, the scroll lands on the first, which is still the right card.
        .id(SettingsSearchTarget.anchor(title))
        .onAppear { flashIfTargeted() }
        .onChange(of: searchTarget) { flashIfTargeted() }
    }

    private func flashIfTargeted() {
        guard let searchTarget, searchTarget.title == title else { return }
        withAnimation(.easeOut(duration: 0.2)) { isFlashing = true }
        // Long enough to find with the eye after the scroll settles, short enough that the
        // pane does not look permanently selected.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.6)) { isFlashing = false }
        }
    }
}

extension SettingsSearchTarget {
    /// Scroll anchor for a row. Prefixed so it cannot collide with any other `.id` a pane
    /// happens to use for its own purposes.
    static func anchor(_ title: String) -> String { "settings-row:\(title)" }
}

/// Hairline divider between rows, inset to match System Settings.
struct SettingsDivider: View {
    var leadingInset: CGFloat = Metrics.cardHorizontalPadding

    var body: some View {
        Divider()
            .overlay(Palette.separator)
            .padding(.leading, leadingInset)
    }
}

/// Convenience wrapper: a detail pane that scrolls a stack of cards with the standard margins.
struct SettingsPane<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    @Environment(\.settingsSearchTarget) private var searchTarget

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
                    if let subtitle {
                        Text(subtitle)
                            .font(Typography.helper)
                            .foregroundStyle(Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content
                }
                .padding(.horizontal, Metrics.paneMargin)
                .padding(.vertical, Metrics.paneMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Keyed on the token, so it runs again when the same result is chosen twice.
            .task(id: searchTarget?.token) {
                guard let searchTarget else { return }
                // A pane that has just been switched to has not laid its rows out yet, and a
                // scroll requested before layout lands nowhere. One short wait is enough.
                try? await Task.sleep(for: .milliseconds(90))
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(SettingsSearchTarget.anchor(searchTarget.title), anchor: .center)
                }
            }
        }
        .navigationTitle(title)
        .background(Palette.paneBackground)
    }
}

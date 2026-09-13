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
struct SettingsRow<Control: View>: View {
    var title: String
    var subtitle: String?
    var systemImage: String?
    /// Coloured dot shown in the icon slot, used for per-calendar rows.
    var accentDot: Color?
    var badge: SettingsBadge?
    var isEnabled: Bool = true
    @ViewBuilder var control: Control

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
    }
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

    var body: some View {
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
        .navigationTitle(title)
        .background(Palette.paneBackground)
    }
}

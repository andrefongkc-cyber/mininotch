import SwiftUI

/// Small capsule badge used to mark a control's maturity.
///
/// Used heavily while V2 features land: a row can ship disabled with `.comingSoon`, then
/// flip to `.beta` and finally to no badge at all without any other change to the view.
enum SettingsBadge: Equatable {
    case beta
    case comingSoon
    case pro
    case custom(String, Color)

    var text: String {
        switch self {
        case .beta: return "Beta"
        case .comingSoon: return "Coming soon"
        case .pro: return "Pro"
        case .custom(let text, _): return text
        }
    }

    var tint: Color {
        switch self {
        case .beta: return Palette.controlAccent
        case .comingSoon: return Palette.secondaryText
        case .pro: return Color(nsColor: .systemIndigo)
        case .custom(_, let color): return color
        }
    }
}

struct BadgeView: View {
    private let badge: SettingsBadge

    init(_ badge: SettingsBadge) { self.badge = badge }

    var body: some View {
        Text(badge.text)
            .font(Typography.badge)
            .foregroundStyle(badge.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(badge.tint.opacity(0.14)))
            .overlay(Capsule().strokeBorder(badge.tint.opacity(0.28), lineWidth: 0.5))
            .accessibilityLabel(badge.text)
    }
}

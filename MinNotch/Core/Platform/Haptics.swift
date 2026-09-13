import AppKit

/// How firm a trackpad tap should feel.
///
/// macOS exposes three feedback patterns and no amplitude control, so "stronger" means a
/// sharper pattern rather than a louder one. `.firm` is the sharpest single tap the system
/// has; `.double` plays it twice in quick succession, which is the most that can be done
/// without a private API.
enum HapticStrength: String, Codable, CaseIterable, Identifiable {
    case soft
    case medium
    case firm
    case double

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soft: return "Soft"
        case .medium: return "Medium"
        case .firm: return "Firm"
        case .double: return "Firm, Twice"
        }
    }

    var pattern: NSHapticFeedbackManager.FeedbackPattern {
        switch self {
        case .soft: return .alignment
        case .medium: return .generic
        case .firm, .double: return .levelChange
        }
    }

    var repeatCount: Int { self == .double ? 2 : 1 }
}

/// Trackpad haptics.
///
/// `NSHapticFeedbackManager` only does anything on a Force Touch trackpad, and no-ops
/// elsewhere, so there is no hardware check to make. The gate is the user's setting, and it
/// is felt only if a hand is actually resting on the trackpad.
enum Haptics {
    static func perform(enabled: Bool, strength: HapticStrength) {
        guard enabled else { return }

        let performer = NSHapticFeedbackManager.defaultPerformer
        performer.perform(strength.pattern, performanceTime: .now)

        guard strength.repeatCount > 1 else { return }
        // Far enough apart to be felt as two taps, close enough to read as one event.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            performer.perform(strength.pattern, performanceTime: .now)
        }
    }
}

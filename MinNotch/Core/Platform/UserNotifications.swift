import os
import UserNotifications

/// Local notifications, currently only for battery events.
///
/// Authorisation is requested lazily, the first time a notification is actually needed,
/// rather than at launch: a permission prompt before the user has enabled anything that
/// notifies is the kind of thing that gets an app deleted.
enum NotificationCenterBridge {
    /// Behind a lock, because it is read and set in the notification centre's callback, which
    /// runs on a queue of its own.
    private static let hasRequestedAuthorization = OSAllocatedUnfairLock(initialState: false)

    /// The completion runs on the main actor. The notification centre answers on a queue of its
    /// own, so both of its callbacks are `@Sendable` and hop back rather than inheriting the
    /// caller's isolation, which in Swift 6 would stop the app when they were called.
    static func requestAuthorizationIfNeeded(completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        @Sendable func finish(_ granted: Bool) {
            Task { @MainActor in completion?(granted) }
        }

        UNUserNotificationCenter.current().getNotificationSettings { @Sendable settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                finish(true)
            case .denied:
                finish(false)
            default:
                let alreadyAsked = hasRequestedAuthorization.withLock { asked in
                    defer { asked = true }
                    return asked
                }
                guard !alreadyAsked else { finish(false); return }
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { @Sendable granted, error in
                    if let error {
                        AppLog.app.error("Notification authorisation failed: \(error.localizedDescription, privacy: .public)")
                    }
                    finish(granted)
                }
            }
        }
    }

    static func post(identifier: String, title: String, body: String, sound: Bool = false) {
        requestAuthorizationIfNeeded { granted in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if sound { content.sound = .default }

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}

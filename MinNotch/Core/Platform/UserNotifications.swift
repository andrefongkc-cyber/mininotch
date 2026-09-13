import UserNotifications

/// Local notifications, currently only for battery events.
///
/// Authorisation is requested lazily, the first time a notification is actually needed,
/// rather than at launch: a permission prompt before the user has enabled anything that
/// notifies is the kind of thing that gets an app deleted.
enum NotificationCenterBridge {
    private static var hasRequestedAuthorization = false

    static func requestAuthorizationIfNeeded(completion: ((Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                completion?(true)
            case .denied:
                completion?(false)
            default:
                guard !hasRequestedAuthorization else { completion?(false); return }
                hasRequestedAuthorization = true
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        AppLog.app.error("Notification authorisation failed: \(error.localizedDescription, privacy: .public)")
                    }
                    completion?(granted)
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

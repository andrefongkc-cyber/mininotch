import ServiceManagement

/// Login item registration.
///
/// `SMAppService.mainApp` is the modern replacement for the deprecated login item APIs and
/// is the only approach allowed in the App Store. Registration can fail, most often because
/// the user has disabled the item in System Settings > General > Login Items, so the stored
/// preference is reconciled against reality at launch rather than trusted.
enum LaunchAtLogin {
    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the user has explicitly turned the item off in System Settings. The
    /// General pane shows an explanation in this case instead of a toggle that fights back.
    static var isBlockedByUser: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return true }
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            AppLog.app.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Brings the stored preference and the real registration back into agreement.
    ///
    /// Called at launch. If the user turned the item off in System Settings, the stored
    /// preference loses, because System Settings is the more authoritative surface.
    static func reconcile(_ settings: SettingsStore) {
        let wanted = settings.general.launchAtLogin
        let actual = isRegistered
        guard wanted != actual else { return }

        if wanted, isBlockedByUser {
            settings.general.launchAtLogin = false
            return
        }

        if !setEnabled(wanted) {
            settings.general.launchAtLogin = actual
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

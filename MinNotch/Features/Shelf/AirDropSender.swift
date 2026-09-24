import AppKit

/// Sends files with AirDrop, from the shelf.
///
/// `NSSharingService`'s AirDrop service is the same picker the Share menu opens: nearby Macs
/// and iPhones, and nothing else to set up. It is a window of this app's, so the app has to be
/// active for it to come to the front, and the notch panel is non-activating by design; hence
/// the activation before it is shown. No Dock icon is needed for that, unlike a permission
/// dialog, because an accessory app can still be the active one.
@MainActor
final class AirDropSender {
    static let shared = AirDropSender()

    /// True when this Mac offers AirDrop at all.
    var isAvailable: Bool { NSSharingService(named: .sendViaAirDrop) != nil }

    /// False on a Mac with AirDrop unavailable, such as one with Wi-Fi or Bluetooth off.
    func canSend(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return false }
        return service.canPerform(withItems: urls)
    }

    /// The service behind the picker that is open. Held, because the picker belongs to it and a
    /// service released as soon as `send` returns can take the picker down with it.
    private var active: NSSharingService?

    @discardableResult
    func send(_ urls: [URL]) -> Bool {
        guard canSend(urls), let service = NSSharingService(named: .sendViaAirDrop) else { return false }
        active = service
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
        return true
    }
}

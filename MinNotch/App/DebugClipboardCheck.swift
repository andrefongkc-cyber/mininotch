#if DEBUG
import AppKit

/// Checks what the clipboard history records, and when Blur Until Unlocked shows it.
///
/// Run with `MiniNotch --check-clipboard`. Uses a private pasteboard of its own and a stand-in for
/// the app in front, never the user's clipboard. It cannot answer an owner check, so it says what
/// this Mac would ask with and leaves the dialog to be tried by hand.
@MainActor
enum DebugClipboardCheck {
    static let flag = "--check-clipboard"

    /// The stand-in for whichever app is in front, which the service reads at each poll.
    @MainActor private final class Front {
        var app: String? = "com.apple.finder"
    }

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains(flag) else { return false }
        var failures = 0
        func check(_ passed: Bool, _ what: String) {
            print((passed ? "ok   " : "FAIL ") + what)
            if !passed { failures += 1 }
        }

        let pasteboard = NSPasteboard(name: .init("com.minnotch.MinNotch.clipboard-check"))
        defer { pasteboard.releaseGlobally() }
        let front = Front()
        var inFront: String? {
            get { front.app }
            set { front.app = newValue }
        }
        let service = ClipboardHistoryService(pasteboard: pasteboard, frontmostApp: { front.app })
        func copy(_ text: String, marked type: String? = nil) {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            if let type { pasteboard.setString("", forType: .init(type)) }
        }
        func recorded(_ text: String) -> Bool { service.items.contains { $0.text == text } }

        copy("hello")
        service.pollNow()
        check(recorded("hello"), "a copy in an ordinary app is recorded")

        inFront = "com.apple.Passwords"
        service.noteAppInFront(inFront)
        copy("hunter2")
        service.pollNow()
        check(!recorded("hunter2"), "a copy made with Passwords in front is not")

        // Copied in Passwords, then straight to another app before the next poll.
        inFront = "com.apple.Passwords"
        service.pollNow()
        copy("correct horse")
        inFront = "com.apple.Notes"
        service.noteAppInFront(inFront)
        service.pollNow()
        check(!recorded("correct horse"), "nor one made in Passwords just before switching away")

        copy("after")
        service.pollNow()
        check(recorded("after"), "the next copy elsewhere is recorded again")

        inFront = "com.apple.keychainaccess"
        service.noteAppInFront(inFront)
        copy("keychain secret")
        service.pollNow()
        check(!recorded("keychain secret"), "a copy made in Keychain Access is not recorded")

        inFront = "com.apple.finder"
        service.pollNow()
        copy("from a password manager", marked: "org.nspasteboard.ConcealedType")
        service.pollNow()
        check(!recorded("from a password manager"), "a copy marked concealed is not recorded")

        // Blur Until Unlocked. The store is a throwaway seeded from the real settings.
        let settings = DebugSupport.makeEnvironment().settings
        settings.advanced.clipboardHistoryEnabled = true
        settings.advanced.clipboardBlurUntilUnlocked = false
        service.start(settings: settings)
        check(!service.isBlurred(in: settings), "with the setting off nothing is blurred")
        settings.advanced.clipboardBlurUntilUnlocked = true
        service.settingsChanged()
        check(service.isBlurred(in: settings), "with it on the list starts blurred")
        service.reveal()
        check(service.isBlurred(in: settings), "an unlock that lands with the tab closed shows nothing")
        service.beginSampling()
        service.reveal()
        check(!service.isBlurred(in: settings), "an unlock with the tab open shows the list")
        service.endSampling()
        check(service.isBlurred(in: settings), "closing the tab blurs it again")
        service.beginSampling()
        service.reveal()
        settings.advanced.clipboardBlurUntilUnlocked = false
        service.settingsChanged()
        settings.advanced.clipboardBlurUntilUnlocked = true
        service.settingsChanged()
        check(service.isBlurred(in: settings), "switching the setting back on blurs a list unlocked before it")
        // Screen lock and sleep call `hide()` too. Not posted here: a fake screen-locked
        // notification would reach every app on the Mac, the running MiniNotch included.
        service.endSampling()
        service.stop()

        print("     owner check on this Mac: \(OwnerCheck.method)")
        print(failures == 0 ? "ok   the clipboard keeps what it should" : "FAIL \(failures) checks")
        return true
    }
}
#endif

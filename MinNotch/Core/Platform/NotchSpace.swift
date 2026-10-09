import AppKit

/// A window server space of the notch's own, so the notch stays over the camera while the desktop
/// changes.
///
/// `canJoinAllSpaces` and `stationary` put the notch on every desktop, but on macOS 27 a window
/// that belongs to the desktops still slides out with one and in with the next when the user
/// swipes between them: the user's recording showed the black pill travelling half the screen
/// while the camera housing stayed put. A space of its own with an absolute level is not one of
/// the desktops, so the swipe does not move it. Boring Notch does the same (`NotchSpaceManager`,
/// a space at the highest level there is).
///
/// The level here is deliberately low: above the ordinary spaces (0), below Setup Assistant (100),
/// the security agent's password prompts (200) and the lock screen (300). At Boring Notch's level
/// the notch, with the clipboard history and notes in it, would draw and take clicks over a
/// locked Mac. The lock screen's own windows are `LockScreenSpace`'s business, at 400.
///
/// Private API, like `LockScreenSpace`: loaded at run time, so a macOS without these symbols just
/// leaves the notch where AppKit puts it, and switched off with Settings > Advanced > Keep the
/// Notch Still Between Desktops. Return values are not checked, because macOS 27 answers these
/// calls with meaningless numbers whether or not they worked (see `LockScreenSpace.adopt`).
@MainActor
final class NotchSpace {
    static let shared = NotchSpace()

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias WindowsAndSpaces = @convention(c) (Int32, CFArray, CFArray) -> Void

    private struct Functions {
        let mainConnectionID: MainConnectionID
        let spaceCreate: SpaceCreate
        let setAbsoluteLevel: SpaceSetAbsoluteLevel
        let showSpaces: ShowSpaces
        let addWindows: WindowsAndSpaces
    }

    /// Above the desktops, below everything that has to cover the notch. See the type's comment.
    private static let level: Int32 = 99

    private let functions: Functions?
    private var connection: Int32 = 0
    private var space: UInt64?

    var isAvailable: Bool { functions != nil }

    private init() {
        functions = Self.load()
    }

    private static func load() -> Functions? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_LAZY) else {
            return nil
        }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        guard let main = symbol("SLSMainConnectionID", as: MainConnectionID.self),
              let create = symbol("SLSSpaceCreate", as: SpaceCreate.self),
              let level = symbol("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevel.self),
              let show = symbol("SLSShowSpaces", as: ShowSpaces.self),
              let add = symbol("SLSAddWindowsToSpaces", as: WindowsAndSpaces.self)
        else {
            AppLog.app.error("SkyLight is missing a function the notch's own space needs")
            return nil
        }
        return Functions(mainConnectionID: main, spaceCreate: create, setAbsoluteLevel: level, showSpaces: show, addWindows: add)
    }

    /// Puts a notch window in the notch's space, creating the space the first time. The window has
    /// to be on screen already, since only then does it have a window number.
    func pin(_ window: NSWindow) {
        guard let functions, window.windowNumber > 0 else { return }
        if space == nil {
            connection = functions.mainConnectionID()
            // 1, as Boring Notch and Parrot both say: other values have Finder draw desktop icons
            // into the space.
            let created = functions.spaceCreate(connection, 1, nil)
            guard created != 0 else {
                AppLog.app.error("SkyLight did not create a space for the notch")
                return
            }
            _ = functions.setAbsoluteLevel(connection, created, Self.level)
            _ = functions.showSpaces(connection, [NSNumber(value: created)] as CFArray)
            space = created
        }
        guard let space else { return }
        functions.addWindows(connection, [NSNumber(value: window.windowNumber)] as CFArray, [NSNumber(value: space)] as CFArray)
    }
}

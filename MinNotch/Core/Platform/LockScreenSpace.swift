import AppKit

/// A window server space drawn above the lock screen, for the one window MinNotch shows there.
///
/// macOS gives third-party apps no lock screen surface, and no window level an app can set puts
/// a window over it: the lock screen is its own space, drawn above every ordinary one. What the
/// window server does have is spaces with an absolute level, which is how Notification Center
/// appears over a locked screen. SkyLight can create such a space, raise it to that level, and
/// move a window into it. This is private API, the same kind as the MediaRemote bridge: loaded
/// at run time, so a macOS without these symbols reports the feature unavailable rather than
/// failing to launch, and it cannot ship in an App Store build.
///
/// The levels, as the window server numbers them: 0 ordinary spaces, 100 Setup Assistant,
/// 200 the security agent, 300 the lock screen, 400 Notification Center at the lock screen,
/// 500 boot progress, 600 VoiceOver. 400 is the one meant for "over the lock screen".
@MainActor
final class LockScreenSpace {
    static let shared = LockScreenSpace()

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias SpaceAddWindowsAndRemoveFromSpaces = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32

    private struct Functions {
        let mainConnectionID: MainConnectionID
        let spaceCreate: SpaceCreate
        let setAbsoluteLevel: SpaceSetAbsoluteLevel
        let showSpaces: ShowSpaces
        let addWindows: SpaceAddWindowsAndRemoveFromSpaces
    }

    private static let aboveLockScreenLevel: Int32 = 400

    private let functions: Functions?
    private var connection: Int32 = 0
    private var space: UInt64?

    /// False when this macOS does not have the SkyLight functions this needs.
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
              let add = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", as: SpaceAddWindowsAndRemoveFromSpaces.self)
        else {
            AppLog.app.error("SkyLight is missing a function the lock screen HUD needs")
            return nil
        }
        return Functions(mainConnectionID: main, spaceCreate: create, setAbsoluteLevel: level, showSpaces: show, addWindows: add)
    }

    /// Moves a window into the space above the lock screen, creating the space the first time.
    /// The window has to be on screen already, since only then does it have a window number.
    @discardableResult
    func adopt(_ window: NSWindow) -> Bool {
        guard let functions, window.windowNumber > 0 else { return false }

        if space == nil {
            connection = functions.mainConnectionID()
            let created = functions.spaceCreate(connection, 1, nil)
            guard created != 0 else {
                AppLog.app.error("SkyLight did not create a space for the lock screen HUD")
                return false
            }
            _ = functions.setAbsoluteLevel(connection, created, Self.aboveLockScreenLevel)
            _ = functions.showSpaces(connection, [NSNumber(value: created)] as CFArray)
            space = created
        }

        guard let space else { return false }
        // 7 is every kind of space the window might already be on, so it leaves them all and
        // exists only in this one.
        let status = functions.addWindows(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
        return status == 0
    }
}

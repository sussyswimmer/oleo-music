import AppKit

/// The only code in Cadence that touches private SkyLight APIs (CLAUDE.md rule 3).
///
/// A window moved into a SkyLight space with a high absolute level draws above
/// the lock screen. Symbols are resolved at runtime: if any is missing, say after
/// a macOS update, `load()` fails and the lock screen feature stays off.
///
/// Signatures follow SkyLightWindow (lakr233/SkyLightWindow, MIT, July 2026).
/// Space IDs are passed as 64-bit values, as yabai (MIT) and CGSInternal (MIT)
/// declare them; a function that takes a 32-bit ID reads the low half of the same
/// register, so this is correct either way. Destroying a space follows
/// CGSInternal's `void CGSSpaceDestroy(CGSConnectionID, CGSSpaceID)`; it's
/// optional, and without it spaces are only hidden.
@MainActor
final class SkyLightBridge {
    typealias SpaceID = UInt64

    struct UnsupportedError: Error, CustomStringConvertible {
        let missing: [String]
        var description: String { "SkyLight unavailable, missing: \(missing.joined(separator: ", "))" }
    }

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowOrHideSpaces = @convention(c) (Int32, CFArray) -> Void
    private typealias SpaceAddWindowsAndRemoveFromSpaces = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32
    private typealias SpaceDestroy = @convention(c) (Int32, UInt64) -> Void

    private let connection: Int32
    private let spaceCreate: SpaceCreate
    private let spaceSetAbsoluteLevel: SpaceSetAbsoluteLevel
    private let showSpaces: ShowOrHideSpaces
    private let hideSpaces: ShowOrHideSpaces
    private let spaceAddWindowsAndRemoveFromSpaces: SpaceAddWindowsAndRemoveFromSpaces
    private let spaceDestroy: SpaceDestroy?

    private init(
        connection: Int32,
        spaceCreate: SpaceCreate,
        spaceSetAbsoluteLevel: SpaceSetAbsoluteLevel,
        showSpaces: ShowOrHideSpaces,
        hideSpaces: ShowOrHideSpaces,
        spaceAddWindowsAndRemoveFromSpaces: SpaceAddWindowsAndRemoveFromSpaces,
        spaceDestroy: SpaceDestroy?
    ) {
        self.connection = connection
        self.spaceCreate = spaceCreate
        self.spaceSetAbsoluteLevel = spaceSetAbsoluteLevel
        self.showSpaces = showSpaces
        self.hideSpaces = hideSpaces
        self.spaceAddWindowsAndRemoveFromSpaces = spaceAddWindowsAndRemoveFromSpaces
        self.spaceDestroy = spaceDestroy
    }

    static func load() -> Result<SkyLightBridge, UnsupportedError> {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW) else {
            return .failure(UnsupportedError(missing: ["SkyLight.framework"]))
        }
        var missing: [String] = []
        func symbol<Function>(_ name: String, as type: Function.Type) -> Function? {
            guard let pointer = dlsym(handle, name) else {
                missing.append(name)
                return nil
            }
            return unsafeBitCast(pointer, to: type)
        }

        let mainConnectionID = symbol("SLSMainConnectionID", as: MainConnectionID.self)
        let spaceCreate = symbol("SLSSpaceCreate", as: SpaceCreate.self)
        let spaceSetAbsoluteLevel = symbol("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevel.self)
        let showSpaces = symbol("SLSShowSpaces", as: ShowOrHideSpaces.self)
        let hideSpaces = symbol("SLSHideSpaces", as: ShowOrHideSpaces.self)
        let addWindows = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", as: SpaceAddWindowsAndRemoveFromSpaces.self)

        guard let mainConnectionID, let spaceCreate, let spaceSetAbsoluteLevel, let showSpaces, let hideSpaces, let addWindows else {
            return .failure(UnsupportedError(missing: missing))
        }
        // Optional: SkyLight's SLS name, else the older CGS name of the same call.
        let spaceDestroy = (dlsym(handle, "SLSSpaceDestroy") ?? dlsym(handle, "CGSSpaceDestroy"))
            .map { unsafeBitCast($0, to: SpaceDestroy.self) }
        return .success(SkyLightBridge(
            connection: mainConnectionID(),
            spaceCreate: spaceCreate,
            spaceSetAbsoluteLevel: spaceSetAbsoluteLevel,
            showSpaces: showSpaces,
            hideSpaces: hideSpaces,
            spaceAddWindowsAndRemoveFromSpaces: addWindows,
            spaceDestroy: spaceDestroy
        ))
    }

    /// Creates a space at `level` (higher draws above more of the system UI).
    /// Returns nil if SkyLight didn't create one; `levelResult` is the CGError from setting the level.
    func createSpace(level: Int32) -> (id: SpaceID, levelResult: Int32)? {
        // (connection, 1, 0) as in SkyLightWindow; the flags aren't documented.
        let space = spaceCreate(connection, 1, 0)
        guard space > 0 else { return nil }
        let id = SpaceID(space)
        return (id, spaceSetAbsoluteLevel(connection, id, level))
    }

    func showSpace(_ space: SpaceID) {
        showSpaces(connection, [NSNumber(value: space)] as CFArray)
    }

    func hideSpace(_ space: SpaceID) {
        hideSpaces(connection, [NSNumber(value: space)] as CFArray)
    }

    /// Destroys an empty space. Returns false if this macOS has no destroy call,
    /// in which case the space stays hidden until Cadence quits.
    @discardableResult
    func destroySpace(_ space: SpaceID) -> Bool {
        guard let spaceDestroy else { return false }
        spaceDestroy(connection, space)
        return true
    }

    /// Moves `window` into `space`. Returns the CGError.
    func addWindow(_ window: NSWindow, to space: SpaceID) -> Int32 {
        // The final 7 is what SkyLightWindow passes; its meaning isn't documented.
        spaceAddWindowsAndRemoveFromSpaces(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
    }
}

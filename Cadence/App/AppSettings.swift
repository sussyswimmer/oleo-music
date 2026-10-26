import Foundation
import Observation
import ServiceManagement
import os

/// App preferences. The toggles persist in `UserDefaults`; launch at login is
/// read from `SMAppService` so it matches System Settings → Login Items.
@Observable
@MainActor
final class AppSettings {
    enum Key {
        static let notchEnabled = "notchEnabled"
        static let lockScreenEnabled = "lockScreenEnabled"
    }

    var notchEnabled: Bool {
        didSet { defaults.set(notchEnabled, forKey: Key.notchEnabled) }
    }

    /// Off by default: the lock screen player relies on private APIs.
    var lockScreenEnabled: Bool {
        didSet { defaults.set(lockScreenEnabled, forKey: Key.lockScreenEnabled) }
    }

    var launchAtLogin: Bool {
        get { launchAtLoginStatus == .enabled }
        set { setLaunchAtLogin(newValue) }
    }

    /// Registered, but the user turned it off in System Settings and has to allow it there.
    var launchAtLoginNeedsApproval: Bool {
        launchAtLoginStatus == .requiresApproval
    }

    private var launchAtLoginStatus: SMAppService.Status
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Key.notchEnabled: true,
            Key.lockScreenEnabled: false,
        ])
        self.defaults = defaults
        notchEnabled = defaults.bool(forKey: Key.notchEnabled)
        lockScreenEnabled = defaults.bool(forKey: Key.lockScreenEnabled)
        launchAtLoginStatus = SMAppService.mainApp.status
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.app.error("Launch at login \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        launchAtLoginStatus = SMAppService.mainApp.status
    }
}

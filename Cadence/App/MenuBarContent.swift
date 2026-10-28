import SwiftUI
import ServiceManagement

struct MenuBarContent: View {
    @Bindable var settings: AppSettings
    #if DEBUG
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        // Enabled once the notch player (Brief 03) and lock screen player (Brief 02) exist.
        Toggle("Show notch player", isOn: $settings.notchEnabled)
            .disabled(true)
        Toggle("Lock screen player", isOn: $settings.lockScreenEnabled)
            .disabled(true)

        Divider()

        Toggle("Launch at login", isOn: $settings.launchAtLogin)
        if settings.launchAtLoginNeedsApproval {
            Button("Allow in Login Items…") {
                SMAppService.openSystemSettingsLoginItems()
            }
        }

        #if DEBUG
        Divider()

        Button("Debug now playing…") {
            openWindow(id: DebugNowPlayingView.windowID)
            // A menu-bar app isn't frontmost, so bring the window forward.
            NSApplication.shared.activate()
        }
        #endif

        Divider()

        Button("Quit Cadence") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

import SwiftUI
import ServiceManagement

struct MenuBarContent: View {
    @Bindable var settings: AppSettings
    #if DEBUG
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Toggle("Show notch player", isOn: $settings.notchEnabled)
        Toggle("Lock screen player", isOn: $settings.lockScreenEnabled)

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
        Picker("Lock screen level", selection: $settings.lockScreenSpaceLevel) {
            ForEach(LockScreenController.spikeLevels, id: \.self) { level in
                Text("\(level)").tag(level)
            }
        }
        .pickerStyle(.menu)
        Button("Show lock screen log") {
            NSWorkspace.shared.open(LockScreenLog.shared.fileURL)
        }
        #endif

        Divider()

        Button("Quit Cadence") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

import SwiftUI

@main
struct CadenceApp: App {
    var body: some Scene {
        MenuBarExtra("Cadence", systemImage: "music.note") {
            Button("Quit Cadence") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

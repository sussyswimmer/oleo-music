import SwiftUI

@main
struct CadenceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings()

    var body: some Scene {
        MenuBarExtra("Cadence", systemImage: "music.note") {
            MenuBarContent(settings: settings)
        }
    }
}

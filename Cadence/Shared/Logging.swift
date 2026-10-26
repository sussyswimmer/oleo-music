import os

private let subsystem = "com.maxwell.cadence"

extension Logger {
    static let app = Logger(subsystem: subsystem, category: "app")
    static let spotify = Logger(subsystem: subsystem, category: "spotify")
    static let notch = Logger(subsystem: subsystem, category: "notch")
    static let lockScreen = Logger(subsystem: subsystem, category: "lockscreen")
}

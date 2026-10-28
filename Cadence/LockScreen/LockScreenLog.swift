import Foundation
import os

/// Appends timestamped lines to ~/Library/Logs/Cadence/lockscreen.log, because
/// the console can't be watched while the screen is locked. Safe from any thread.
///
/// The file is written in Debug builds, or in any build after
/// `defaults write com.maxwell.cadence LockScreenDiagnostics -bool YES`.
final class LockScreenLog: Sendable {
    static let shared = LockScreenLog()

    let isEnabled: Bool

    let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/Cadence/lockscreen.log")
    private let queue = DispatchQueue(label: "com.maxwell.cadence.lockscreen-log")
    private let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

    private init() {
        #if DEBUG
        isEnabled = true
        #else
        isEnabled = UserDefaults.standard.bool(forKey: "LockScreenDiagnostics")
        #endif
    }

    func write(_ message: String) {
        Logger.lockScreen.info("\(message, privacy: .public)")
        guard isEnabled else { return }
        let line = "\(Date.now.formatted(timestampStyle)) \(message)\n"
        queue.async { [fileURL] in
            Self.append(Data(line.utf8), to: fileURL)
        }
    }

    private static func append(_ data: Data, to url: URL) {
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }
}

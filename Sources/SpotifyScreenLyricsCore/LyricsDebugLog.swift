import Foundation
import OSLog

enum LyricsDebugLog {
    private static let logger = Logger(subsystem: "SpotifyScreenLyrics", category: "Lyrics")
    private static let fileQueue = DispatchQueue(label: "SpotifyScreenLyrics.LyricsDebugLog")
    static let logFileURL: URL = {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        return libraryURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("SpotifyScreenLyrics", isDirectory: true)
            .appendingPathComponent("lyrics-debug.log")
    }()
    private static let isEnabled: Bool = {
        ProcessInfo.processInfo.environment["SPOTIFY_SCREEN_LYRICS_DEBUG"] == "1"
    }()

    static func write(_ message: @autoclosure () -> String) {
        guard isEnabled else {
            return
        }

        let text = message()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        logger.debug("\(text, privacy: .public)")
        let line = "[LyricsDebug] \(formatter.string(from: Date())) \(text)\n"
        fputs(line, stderr)
        appendToFile(line)
    }

    private static func appendToFile(_ line: String) {
        fileQueue.async {
            do {
                let directoryURL = logFileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                let data = Data(line.utf8)
                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    let handle = try FileHandle(forWritingTo: logFileURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: logFileURL, options: .atomic)
                }
            } catch {
                fputs("[LyricsDebug] failed to write log file: \(error.localizedDescription)\n", stderr)
            }
        }
    }

    static func trackSummary(_ key: TrackLookupKey) -> String {
        "song=\"\(escaped("\(key.artist) - \(key.title)"))\" album=\"\(escaped(key.album))\" duration=\(Int(key.duration.rounded()))s stableID=\"\(escaped(key.stableID))\""
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

extension ContinuousClock.Instant {
    func elapsedMilliseconds(since start: ContinuousClock.Instant) -> String {
        let duration = start.duration(to: self)
        let components = duration.components
        let milliseconds = (Double(components.seconds) * 1_000) +
            (Double(components.attoseconds) / 1_000_000_000_000_000)
        return String(format: "%.1fms", milliseconds)
    }
}

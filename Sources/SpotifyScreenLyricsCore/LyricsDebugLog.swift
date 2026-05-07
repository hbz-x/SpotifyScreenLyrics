import Foundation
import OSLog

enum LyricsDebugLog {
    private static let logger = Logger(subsystem: "SpotifyScreenLyrics", category: "Lyrics")
    private static let isEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return ProcessInfo.processInfo.environment["SPOTIFY_SCREEN_LYRICS_DEBUG"] == "1"
        #endif
    }()

    static func write(_ message: @autoclosure () -> String) {
        guard isEnabled else {
            return
        }

        let text = message()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        logger.debug("\(text, privacy: .public)")
        fputs("[LyricsDebug] \(formatter.string(from: Date())) \(text)\n", stderr)
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

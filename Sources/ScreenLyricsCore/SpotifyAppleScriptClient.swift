import Foundation

public protocol SpotifyReading: Sendable {
    func currentTrack() async throws -> SpotifyTrack
}

public final class SpotifyAppleScriptClient: SpotifyReading, @unchecked Sendable {
    public init() {}

    public func currentTrack() async throws -> SpotifyTrack {
        try await Task.detached(priority: .utility) {
            try Self.readCurrentTrack()
        }.value
    }

    private static func readCurrentTrack() throws -> SpotifyTrack {
        let script = """
        tell application "System Events"
            set spotifyIsRunning to exists (processes where name is "Spotify")
        end tell
        if spotifyIsRunning is false then
            return "NOT_RUNNING"
        end if

        tell application "Spotify"
            if player state is stopped then
                return "NO_TRACK"
            end if

            set trackName to name of current track
            set artistName to artist of current track
            set albumName to album of current track
            set durationSeconds to (duration of current track) / 1000
            set positionSeconds to player position
            set isPlaying to player state is playing
            return trackName & linefeed & artistName & linefeed & albumName & linefeed & durationSeconds & linefeed & positionSeconds & linefeed & isPlaying
        end tell
        """

        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw SpotifyError.scriptFailed("Unable to create AppleScript.")
        }

        let result = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Spotify AppleScript failed."
            throw SpotifyError.scriptFailed(message)
        }

        guard let output = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            throw SpotifyError.noTrack
        }

        if output == "NOT_RUNNING" {
            throw SpotifyError.notRunning
        }

        if output == "NO_TRACK" {
            throw SpotifyError.noTrack
        }

        let parts = output.components(separatedBy: "\n")
        guard parts.count >= 6,
              let duration = TimeInterval(parts[3]),
              let position = TimeInterval(parts[4]) else {
            throw SpotifyError.scriptFailed("Unexpected Spotify response.")
        }

        return SpotifyTrack(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            duration: duration,
            position: position,
            isPlaying: parts[5] == "true"
        )
    }
}

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
            return {trackName, artistName, albumName, durationSeconds, positionSeconds, isPlaying}
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

        if result.stringValue == "NOT_RUNNING" {
            throw SpotifyError.notRunning
        }

        if result.stringValue == "NO_TRACK" {
            throw SpotifyError.noTrack
        }

        guard let output = SpotifyAppleScriptOutput(result) else {
            throw SpotifyError.scriptFailed("Unexpected Spotify response.")
        }

        return SpotifyTrack(
            title: output.title,
            artist: output.artist,
            album: output.album,
            duration: output.duration,
            position: output.position,
            isPlaying: output.isPlaying
        )
    }
}

private struct SpotifyAppleScriptOutput {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    let isPlaying: Bool

    init?(_ descriptor: NSAppleEventDescriptor) {
        guard descriptor.numberOfItems >= 6,
              let title = descriptor.atIndex(1)?.stringValue,
              let artist = descriptor.atIndex(2)?.stringValue,
              let album = descriptor.atIndex(3)?.stringValue,
              let duration = descriptor.atIndex(4)?.doubleValue,
              let position = descriptor.atIndex(5)?.doubleValue,
              let isPlaying = descriptor.atIndex(6)?.booleanValue else {
            return nil
        }

        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
        self.isPlaying = isPlaying
    }
}

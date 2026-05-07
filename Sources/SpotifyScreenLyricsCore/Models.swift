import Foundation

public struct SpotifyTrack: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    public let position: TimeInterval
    public let isPlaying: Bool

    public init(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        position: TimeInterval,
        isPlaying: Bool
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
        self.isPlaying = isPlaying
    }

    public var lookupKey: TrackLookupKey {
        TrackLookupKey(title: title, artist: artist, album: album, duration: duration)
    }
}

public struct TrackLookupKey: Equatable, Hashable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval

    public init(title: String, artist: String, album: String, duration: TimeInterval) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        self.album = album.trimmingCharacters(in: .whitespacesAndNewlines)
        self.duration = duration
    }

    public var stableID: String {
        let durationSeconds = Int(duration.rounded())
        let rawID = "\(artist)|\(title)|\(album)|\(durationSeconds)"
        return rawID.normalizedForLookup()
    }
}

public struct LyricLine: Equatable, Sendable {
    public let time: TimeInterval
    public let text: String

    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

public struct Lyrics: Equatable, Sendable {
    public let trackName: String
    public let artistName: String
    public let plainLyrics: String?
    public let syncedLyrics: String
    public let syncedLines: [LyricLine]

    public init(
        trackName: String,
        artistName: String,
        plainLyrics: String?,
        syncedLyrics: String,
        syncedLines: [LyricLine]
    ) {
        self.trackName = trackName
        self.artistName = artistName
        self.plainLyrics = plainLyrics
        self.syncedLyrics = syncedLyrics
        self.syncedLines = syncedLines
    }
}

public struct DisplayLyrics: Equatable, Sendable {
    public let currentLine: String
    public let nextLine: String?

    public init(currentLine: String, nextLine: String?) {
        self.currentLine = currentLine
        self.nextLine = nextLine
    }
}

public enum LyricsStatus: Equatable, Sendable {
    case waitingForSpotify
    case loading(trackTitle: String, artist: String)
    case ready(trackTitle: String, artist: String, lyrics: DisplayLyrics, isPlaying: Bool)
    case noSyncedLyrics(trackTitle: String, artist: String)
    case retryingInBackground(trackTitle: String, artist: String, message: String)
    case error(message: String)
}

public enum SpotifyError: Error, Equatable, Sendable {
    case notRunning
    case noTrack
    case scriptFailed(String)
}

public enum LyricsLookupError: Error, Equatable, Sendable {
    case noResult
    case noSyncedLyrics
    case badResponse
}

extension String {
    func normalizedForLookup() -> String {
        folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}

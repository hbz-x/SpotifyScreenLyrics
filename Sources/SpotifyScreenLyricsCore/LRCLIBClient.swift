import Foundation

public protocol LyricsFetching: Sendable {
    func fetchLyrics(for track: TrackLookupKey) async throws -> Lyrics
}

public final class LRCLIBClient: LyricsFetching, @unchecked Sendable {
    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let timeoutInterval: TimeInterval

    public init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://lrclib.net/api/get")!,
        timeoutInterval: TimeInterval = 20
    ) {
        self.session = session
        self.baseURL = baseURL
        self.decoder = JSONDecoder()
        self.timeoutInterval = timeoutInterval
    }

    public func fetchLyrics(for track: TrackLookupKey) async throws -> Lyrics {
        let requestStartedAt = ContinuousClock.now
        let durationSeconds = Int(track.duration.rounded())
        let trackSummary = LyricsDebugLog.trackSummary(track)
        LyricsDebugLog.write("LRCLIB fetch started \(trackSummary)")

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(durationSeconds))
        ]

        guard let url = components?.url else {
            LyricsDebugLog.write("LRCLIB fetch failed before request \(trackSummary): bad URL")
            throw LyricsLookupError.badResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutInterval
        request.setValue("SpotifyScreenLyrics/0.1.0 (https://lrclib.net)", forHTTPHeaderField: "User-Agent")

        LyricsDebugLog.write("LRCLIB request \(trackSummary) URL=\(url.absoluteString) timeout=\(String(format: "%.1fs", timeoutInterval))")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let elapsed = ContinuousClock.now.elapsedMilliseconds(since: requestStartedAt)
            LyricsDebugLog.write("LRCLIB request failed \(trackSummary) after \(elapsed): \(error.localizedDescription)")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            let elapsed = ContinuousClock.now.elapsedMilliseconds(since: requestStartedAt)
            LyricsDebugLog.write("LRCLIB request returned non-HTTP response \(trackSummary) after \(elapsed)")
            throw LyricsLookupError.badResponse
        }

        let responseElapsed = ContinuousClock.now.elapsedMilliseconds(since: requestStartedAt)
        LyricsDebugLog.write(
            "LRCLIB response \(trackSummary) status=\(httpResponse.statusCode) bytes=\(data.count) elapsed=\(responseElapsed)"
        )

        switch httpResponse.statusCode {
        case 200:
            let response = try decoder.decode(LRCLIBResponse.self, from: data)
            let syncedLyrics = response.syncedLyrics ?? ""
            let syncedLines = LRCParser.parse(syncedLyrics)
            guard !syncedLines.isEmpty else {
                let elapsed = ContinuousClock.now.elapsedMilliseconds(since: requestStartedAt)
                LyricsDebugLog.write(
                    "LRCLIB response had no synced lyric lines \(trackSummary) plainLyrics=\(response.plainLyrics != nil) syncedCharacters=\(syncedLyrics.count) elapsed=\(elapsed)"
                )
                throw LyricsLookupError.noSyncedLyrics
            }

            let elapsed = ContinuousClock.now.elapsedMilliseconds(since: requestStartedAt)
            LyricsDebugLog.write(
                    "LRCLIB fetch succeeded \(trackSummary) responseTitle=\"\(response.trackName)\" responseArtist=\"\(response.artistName)\" syncedLines=\(syncedLines.count) syncedCharacters=\(syncedLyrics.count) elapsed=\(elapsed)"
                )

            return Lyrics(
                trackName: response.trackName,
                artistName: response.artistName,
                plainLyrics: response.plainLyrics,
                syncedLyrics: syncedLyrics,
                syncedLines: syncedLines
            )
        case 404:
            let elapsed = ContinuousClock.now.elapsedMilliseconds(since: requestStartedAt)
            LyricsDebugLog.write("LRCLIB fetch completed with no result \(trackSummary) after \(elapsed)")
            throw LyricsLookupError.noResult
        default:
            let elapsed = ContinuousClock.now.elapsedMilliseconds(since: requestStartedAt)
            LyricsDebugLog.write("LRCLIB fetch failed \(trackSummary) with bad status=\(httpResponse.statusCode) after \(elapsed)")
            throw LyricsLookupError.badResponse
        }
    }
}

public struct LRCLIBResponse: Decodable, Equatable, Sendable {
    public let id: Int?
    public let trackName: String
    public let artistName: String
    public let albumName: String?
    public let duration: Double?
    public let plainLyrics: String?
    public let syncedLyrics: String?

    public init(
        id: Int?,
        trackName: String,
        artistName: String,
        albumName: String?,
        duration: Double?,
        plainLyrics: String?,
        syncedLyrics: String?
    ) {
        self.id = id
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.plainLyrics = plainLyrics
        self.syncedLyrics = syncedLyrics
    }
}

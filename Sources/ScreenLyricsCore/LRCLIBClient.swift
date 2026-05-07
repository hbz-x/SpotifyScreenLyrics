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
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))
        ]

        guard let url = components?.url else {
            throw LyricsLookupError.badResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutInterval
        request.setValue("ScreenLyrics/0.1.0 (https://lrclib.net)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricsLookupError.badResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let response = try decoder.decode(LRCLIBResponse.self, from: data)
            let syncedLyrics = response.syncedLyrics ?? ""
            let syncedLines = LRCParser.parse(syncedLyrics)
            guard !syncedLines.isEmpty else {
                throw LyricsLookupError.noSyncedLyrics
            }

            return Lyrics(
                trackName: response.trackName,
                artistName: response.artistName,
                plainLyrics: response.plainLyrics,
                syncedLyrics: syncedLyrics,
                syncedLines: syncedLines
            )
        case 404:
            throw LyricsLookupError.noResult
        default:
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

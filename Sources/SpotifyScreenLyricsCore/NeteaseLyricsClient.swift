import Foundation

public final class NeteaseLyricsClient: LyricsFetching, @unchecked Sendable {
    private let session: URLSession
    private let searchURL: URL
    private let lyricsURL: URL
    private let decoder: JSONDecoder
    private let timeoutInterval: TimeInterval
    private let searchLimit: Int

    public init(
        session: URLSession = .shared,
        searchURL: URL = URL(string: "https://music.163.com/api/search/get/web")!,
        lyricsURL: URL = URL(string: "https://music.163.com/api/song/lyric")!,
        timeoutInterval: TimeInterval = 15,
        searchLimit: Int = 10
    ) {
        self.session = session
        self.searchURL = searchURL
        self.lyricsURL = lyricsURL
        self.decoder = JSONDecoder()
        self.timeoutInterval = timeoutInterval
        self.searchLimit = searchLimit
    }

    public func fetchLyrics(for track: TrackLookupKey) async throws -> Lyrics {
        let requestStartedAt = ContinuousClock.now
        let trackSummary = LyricsDebugLog.trackSummary(track)
        LyricsDebugLog.write("NetEase fetch started \(trackSummary)")

        let songs = try await searchSongs(for: track, requestStartedAt: requestStartedAt)
        guard let song = bestMatch(in: songs, for: track) else {
            let elapsed = ContinuousClock.now.elapsedMilliseconds(since: requestStartedAt)
            LyricsDebugLog.write(
                "NetEase search found no confident match \(trackSummary) candidates=\(songs.count) elapsed=\(elapsed)"
            )
            throw LyricsLookupError.noResult
        }

        let response = try await fetchLyrics(forSongID: song.id, track: track, requestStartedAt: requestStartedAt)
        let syncedLyrics = response.lrc?.lyric.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let syncedLines = LRCParser.parse(syncedLyrics)
        guard !syncedLines.isEmpty else {
            let elapsed = ContinuousClock.now.elapsedMilliseconds(since: requestStartedAt)
            LyricsDebugLog.write(
                "NetEase response had no synced lyric lines \(trackSummary) songID=\(song.id) elapsed=\(elapsed)"
            )
            throw LyricsLookupError.noSyncedLyrics
        }

        let elapsed = ContinuousClock.now.elapsedMilliseconds(since: requestStartedAt)
        LyricsDebugLog.write(
            "NetEase fetch succeeded \(trackSummary) songID=\(song.id) responseTitle=\"\(song.name)\" responseArtist=\"\(song.artistNames.joined(separator: ", "))\" syncedLines=\(syncedLines.count) syncedCharacters=\(syncedLyrics.count) elapsed=\(elapsed)"
        )

        return Lyrics(
            trackName: song.name,
            artistName: song.artistNames.joined(separator: ", "),
            plainLyrics: nil,
            syncedLyrics: syncedLyrics,
            syncedLines: syncedLines,
            source: "netease"
        )
    }

    private func searchSongs(
        for track: TrackLookupKey,
        requestStartedAt: ContinuousClock.Instant
    ) async throws -> [NeteaseSong] {
        var request = URLRequest(url: searchURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.httpBody = formEncodedBody([
            ("s", "\(track.title) \(track.artist)"),
            ("type", "1"),
            ("offset", "0"),
            ("total", "true"),
            ("limit", String(searchLimit))
        ])
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        applyCommonHeaders(to: &request)

        let data = try await data(for: request, serviceName: "NetEase search", track: track, startedAt: requestStartedAt)
        let response = try decoder.decode(NeteaseSearchResponse.self, from: data)
        guard response.code == nil || response.code == 200 else {
            LyricsDebugLog.write("NetEase search returned code=\(response.code ?? -1) \(LyricsDebugLog.trackSummary(track))")
            throw LyricsLookupError.badResponse
        }

        return response.result?.songs ?? []
    }

    private func fetchLyrics(
        forSongID songID: Int,
        track: TrackLookupKey,
        requestStartedAt: ContinuousClock.Instant
    ) async throws -> NeteaseLyricsResponse {
        var components = URLComponents(url: lyricsURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "id", value: String(songID)),
            URLQueryItem(name: "lv", value: "-1"),
            URLQueryItem(name: "tv", value: "-1")
        ]

        guard let url = components?.url else {
            throw LyricsLookupError.badResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutInterval
        applyCommonHeaders(to: &request)

        let data = try await data(for: request, serviceName: "NetEase lyric", track: track, startedAt: requestStartedAt)
        let response = try decoder.decode(NeteaseLyricsResponse.self, from: data)
        guard response.code == nil || response.code == 200 else {
            LyricsDebugLog.write("NetEase lyric returned code=\(response.code ?? -1) \(LyricsDebugLog.trackSummary(track))")
            throw LyricsLookupError.badResponse
        }
        if response.nolyric == true || response.uncollected == true {
            throw LyricsLookupError.noSyncedLyrics
        }
        return response
    }

    private func data(
        for request: URLRequest,
        serviceName: String,
        track: TrackLookupKey,
        startedAt: ContinuousClock.Instant
    ) async throws -> Data {
        let trackSummary = LyricsDebugLog.trackSummary(track)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let elapsed = ContinuousClock.now.elapsedMilliseconds(since: startedAt)
            LyricsDebugLog.write("\(serviceName) request failed \(trackSummary) after \(elapsed): \(error.localizedDescription)")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            let elapsed = ContinuousClock.now.elapsedMilliseconds(since: startedAt)
            LyricsDebugLog.write("\(serviceName) request returned non-HTTP response \(trackSummary) after \(elapsed)")
            throw LyricsLookupError.badResponse
        }

        let elapsed = ContinuousClock.now.elapsedMilliseconds(since: startedAt)
        LyricsDebugLog.write(
            "\(serviceName) response \(trackSummary) status=\(httpResponse.statusCode) bytes=\(data.count) elapsed=\(elapsed)"
        )

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw httpResponse.statusCode == 404 ? LyricsLookupError.noResult : LyricsLookupError.badResponse
        }

        return data
    }

    private func bestMatch(in songs: [NeteaseSong], for track: TrackLookupKey) -> NeteaseSong? {
        songs
            .compactMap { song -> (song: NeteaseSong, score: Int)? in
                let score = matchScore(song: song, track: track)
                return score >= 7 ? (song, score) : nil
            }
            .max { lhs, rhs in lhs.score < rhs.score }?
            .song
    }

    private func matchScore(song: NeteaseSong, track: TrackLookupKey) -> Int {
        guard let titleScore = titleScore(candidate: song.name, expected: track.title),
              let artistScore = artistScore(candidateArtists: song.artistNames, expected: track.artist) else {
            return 0
        }

        var score = titleScore + artistScore

        if let duration = song.durationSeconds, track.duration > 0 {
            let delta = abs(duration - track.duration)
            switch delta {
            case ...2:
                score += 3
            case ...5:
                score += 2
            case ...10:
                score += 1
            case 15...:
                score -= 4
            default:
                break
            }
        }

        if albumMatches(candidate: song.albumName, expected: track.album) {
            score += 1
        }

        return score
    }

    private func titleScore(candidate: String, expected: String) -> Int? {
        let candidate = candidate.normalizedForLookup()
        let expected = expected.normalizedForLookup()
        let looseCandidate = looseTitle(candidate)
        let looseExpected = looseTitle(expected)

        if candidate == expected || looseCandidate == looseExpected {
            return 5
        }
        if isPrefixVariant(candidate: candidate, expected: expected) ||
            isPrefixVariant(candidate: looseCandidate, expected: looseExpected) {
            return 3
        }
        return nil
    }

    private func artistScore(candidateArtists: [String], expected: String) -> Int? {
        let expected = expected.normalizedForLookup()
        let expectedParts = artistParts(expected)
        let candidates = candidateArtists
            .map { $0.normalizedForLookup() }
            .filter { !$0.isEmpty }
        let joinedCandidates = candidates.joined(separator: " ")

        if joinedCandidates == expected {
            return 4
        }

        if !expectedParts.isEmpty && candidates.contains(where: { expectedParts.contains($0) }) {
            return 3
        }

        if candidates.contains(where: { candidate in isPrefixVariant(candidate: candidate, expected: expected) }) ||
            candidates.contains(where: { candidate in
                expectedParts.contains(where: { part in isPrefixVariant(candidate: candidate, expected: part) })
            }) {
            return 2
        }

        return nil
    }

    private func albumMatches(candidate: String?, expected: String) -> Bool {
        guard let candidate else {
            return false
        }
        let normalizedCandidate = candidate.normalizedForLookup()
        let normalizedExpected = expected.normalizedForLookup()
        guard !normalizedCandidate.isEmpty && !normalizedExpected.isEmpty else {
            return false
        }
        return normalizedCandidate == normalizedExpected ||
            normalizedCandidate.contains(normalizedExpected) ||
            normalizedExpected.contains(normalizedCandidate)
    }

    private func looseTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[[^]]*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+-\\s+.*$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isPrefixVariant(candidate: String, expected: String) -> Bool {
        guard candidate.count >= 3, expected.count >= 3 else {
            return false
        }

        return candidate.hasPrefix("\(expected) ") ||
            expected.hasPrefix("\(candidate) ")
    }

    private func artistParts(_ artist: String) -> Set<String> {
        let parts = artist
            .replacingOccurrences(of: "\\b(feat|featuring|ft)\\.?\\b", with: ",", options: .regularExpression)
            .components(separatedBy: CharacterSet(charactersIn: ",/&+;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Set(parts)
    }

    private func formEncodedBody(_ fields: [(String, String)]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private func applyCommonHeaders(to request: inout URLRequest) {
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 SpotifyScreenLyrics/0.1.0",
            forHTTPHeaderField: "User-Agent"
        )
    }
}

private struct NeteaseSearchResponse: Decodable, Sendable {
    let code: Int?
    let result: NeteaseSearchResult?
}

private struct NeteaseSearchResult: Decodable, Sendable {
    let songs: [NeteaseSong]?
}

private struct NeteaseSong: Decodable, Sendable {
    let id: Int
    let name: String
    let durationMilliseconds: Int?
    let artistNames: [String]
    let albumName: String?

    var durationSeconds: TimeInterval? {
        durationMilliseconds.map { TimeInterval($0) / 1000 }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case durationMilliseconds = "duration"
        case alternateDurationMilliseconds = "dt"
        case artists
        case alternateArtists = "ar"
        case album
        case alternateAlbum = "al"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        durationMilliseconds = try container.decodeIfPresent(Int.self, forKey: .durationMilliseconds)
            ?? container.decodeIfPresent(Int.self, forKey: .alternateDurationMilliseconds)

        let artists = try container.decodeIfPresent([NeteaseArtist].self, forKey: .artists)
            ?? container.decodeIfPresent([NeteaseArtist].self, forKey: .alternateArtists)
            ?? []
        artistNames = artists.map(\.name)

        albumName = try container.decodeIfPresent(NeteaseAlbum.self, forKey: .album)?.name
            ?? container.decodeIfPresent(NeteaseAlbum.self, forKey: .alternateAlbum)?.name
    }
}

private struct NeteaseArtist: Decodable, Sendable {
    let name: String
}

private struct NeteaseAlbum: Decodable, Sendable {
    let name: String
}

private struct NeteaseLyricsResponse: Decodable, Sendable {
    let code: Int?
    let lrc: NeteaseLyricPayload?
    let nolyric: Bool?
    let uncollected: Bool?
}

private struct NeteaseLyricPayload: Decodable, Sendable {
    let lyric: String
}

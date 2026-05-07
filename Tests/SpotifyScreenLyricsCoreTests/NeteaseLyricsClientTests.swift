import Foundation
import Testing
@testable import SpotifyScreenLyricsCore

@Test
func neteaseLyricsClientSearchesThenFetchesSyncedLyrics() async throws {
    let host = "netease-success.example.test"
    let session = URLSession(configuration: makeURLSessionConfiguration(
        host: host,
        responses: [
            StubHTTPResponse(
                path: "/search",
                statusCode: 200,
                body: """
                {
                  "code": 200,
                  "result": {
                    "songs": [
                      {
                        "id": 123,
                        "name": "Song",
                        "duration": 100000,
                        "artists": [{ "name": "Artist" }],
                        "album": { "name": "Album" }
                      }
                    ]
                  }
                }
                """
            ),
            StubHTTPResponse(
                path: "/lyric",
                statusCode: 200,
                body: """
                {
                  "code": 200,
                  "lrc": { "lyric": "[00:01.00]First\\n[00:02.50]Second" }
                }
                """
            )
        ]
    ))
    let client = NeteaseLyricsClient(
        session: session,
        searchURL: URL(string: "https://\(host)/search")!,
        lyricsURL: URL(string: "https://\(host)/lyric")!
    )

    let lyrics = try await client.fetchLyrics(
        for: TrackLookupKey(title: "Song", artist: "Artist", album: "Album", duration: 100)
    )

    #expect(lyrics.source == "netease")
    #expect(lyrics.trackName == "Song")
    #expect(lyrics.artistName == "Artist")
    #expect(lyrics.syncedLines == [
        LyricLine(time: 1, text: "First"),
        LyricLine(time: 2.5, text: "Second")
    ])
}

@Test
func neteaseLyricsClientRejectsWeakSearchMatches() async {
    let host = "netease-weak-match.example.test"
    let session = URLSession(configuration: makeURLSessionConfiguration(
        host: host,
        responses: [
            StubHTTPResponse(
                path: "/search",
                statusCode: 200,
                body: """
                {
                  "code": 200,
                  "result": {
                    "songs": [
                      {
                        "id": 123,
                        "name": "Different Song",
                        "duration": 100000,
                        "artists": [{ "name": "Different Artist" }],
                        "album": { "name": "Album" }
                      }
                    ]
                  }
                }
                """
            )
        ]
    ))
    let client = NeteaseLyricsClient(
        session: session,
        searchURL: URL(string: "https://\(host)/search")!,
        lyricsURL: URL(string: "https://\(host)/lyric")!
    )

    do {
        _ = try await client.fetchLyrics(
            for: TrackLookupKey(title: "Song", artist: "Artist", album: "Album", duration: 100)
        )
        Issue.record("Expected weak NetEase match to be rejected")
    } catch {
        #expect(error as? LyricsLookupError == .noResult)
    }
}

@Test
func neteaseLyricsClientRetriesChineseSearchWithSimplifiedQuery() async throws {
    let host = "netease-simplified-search.example.test"
    let session = URLSession(configuration: makeURLSessionConfiguration(
        host: host,
        responses: [
            StubHTTPResponse(
                path: "/search",
                statusCode: 200,
                body: """
                {
                  "code": 200,
                  "result": { "songs": [] }
                }
                """
            ),
            StubHTTPResponse(
                path: "/search",
                statusCode: 200,
                body: """
                {
                  "code": 200,
                  "result": {
                    "songs": [
                      {
                        "id": 456,
                        "name": "男儿当自强",
                        "duration": 256000,
                        "artists": [{ "name": "林子祥" }],
                        "album": { "name": "林子祥 24K Mastersonic Compilation" }
                      }
                    ]
                  }
                }
                """
            ),
            StubHTTPResponse(
                path: "/lyric",
                statusCode: 200,
                body: """
                {
                  "code": 200,
                  "lrc": { "lyric": "[00:01.00]傲氣面對萬重浪" }
                }
                """
            )
        ]
    ))
    let client = NeteaseLyricsClient(
        session: session,
        searchURL: URL(string: "https://\(host)/search")!,
        lyricsURL: URL(string: "https://\(host)/lyric")!
    )

    let lyrics = try await client.fetchLyrics(
        for: TrackLookupKey(
            title: "男兒當自強",
            artist: "林子祥",
            album: "林子祥 24K Mastersonic Compilation",
            duration: 256
        )
    )
    let searchQueries = StubURLProtocol.requestBodies(for: host, path: "/search")
        .compactMap { formValue(named: "s", in: $0) }

    #expect(searchQueries == [
        "男兒當自強 林子祥",
        "男儿当自强 林子祥"
    ])
    #expect(lyrics.trackName == "男儿当自强")
    #expect(lyrics.syncedLines == [LyricLine(time: 1, text: "傲氣面對萬重浪")])
}

@Test
func neteaseLyricsClientKeepsFirstBestMatchWhenScoresTie() async throws {
    let host = "netease-tied-match.example.test"
    let session = URLSession(configuration: makeURLSessionConfiguration(
        host: host,
        responses: [
            StubHTTPResponse(
                path: "/search",
                statusCode: 200,
                body: """
                {
                  "code": 200,
                  "result": {
                    "songs": [
                      {
                        "id": 111,
                        "name": "Song",
                        "duration": 100000,
                        "artists": [{ "name": "Artist" }],
                        "album": { "name": "Album" }
                      },
                      {
                        "id": 222,
                        "name": "Song",
                        "duration": 100000,
                        "artists": [{ "name": "Artist" }],
                        "album": { "name": "Album" }
                      }
                    ]
                  }
                }
                """
            ),
            StubHTTPResponse(
                path: "/lyric",
                statusCode: 200,
                body: """
                {
                  "code": 200,
                  "lrc": { "lyric": "[00:01.00]First candidate" }
                }
                """
            )
        ]
    ))
    let client = NeteaseLyricsClient(
        session: session,
        searchURL: URL(string: "https://\(host)/search")!,
        lyricsURL: URL(string: "https://\(host)/lyric")!
    )

    let lyrics = try await client.fetchLyrics(
        for: TrackLookupKey(title: "Song", artist: "Artist", album: "Album", duration: 100)
    )
    let lyricURL = StubURLProtocol.requestURLs(for: host, path: "/lyric").first
    let songID = lyricURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
        .queryItems?
        .first { $0.name == "id" }?
        .value

    #expect(songID == "111")
    #expect(lyrics.syncedLines == [LyricLine(time: 1, text: "First candidate")])
}

private struct StubHTTPResponse {
    let path: String
    let statusCode: Int
    let body: String
}

private func formValue(named name: String, in body: String) -> String? {
    var components = URLComponents()
    components.percentEncodedQuery = body
    return components.queryItems?.first { $0.name == name }?.value
}

private func makeURLSessionConfiguration(host: String, responses: [StubHTTPResponse]) -> URLSessionConfiguration {
    StubURLProtocol.setResponses(responses, for: host)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return configuration
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responsesByHost: [String: [StubHTTPResponse]] = [:]
    nonisolated(unsafe) private static var requestBodiesByHostAndPath: [String: [String: [String]]] = [:]
    nonisolated(unsafe) private static var requestURLsByHostAndPath: [String: [String: [URL]]] = [:]

    static func setResponses(_ responses: [StubHTTPResponse], for host: String) {
        lock.lock()
        responsesByHost[host] = responses
        requestBodiesByHostAndPath[host] = [:]
        requestURLsByHostAndPath[host] = [:]
        lock.unlock()
    }

    static func requestBodies(for host: String, path: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return requestBodiesByHostAndPath[host]?[path] ?? []
    }

    static func requestURLs(for host: String, path: String) -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requestURLsByHostAndPath[host]?[path] ?? []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.recordRequest(request, for: url)

        guard let stub = Self.takeResponse(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func takeResponse(for url: URL) -> StubHTTPResponse? {
        guard let host = url.host else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        guard var responses = responsesByHost[host],
              let index = responses.firstIndex(where: { $0.path == url.path }) else {
            return nil
        }

        let response = responses.remove(at: index)
        responsesByHost[host] = responses
        return response
    }

    private static func recordRequest(_ request: URLRequest, for url: URL) {
        guard let host = url.host else {
            return
        }
        let body = request.httpBody.map { String(decoding: $0, as: UTF8.self) } ??
            request.httpBodyStream.flatMap(Self.stringBody(from:)) ??
            ""

        lock.lock()
        requestBodiesByHostAndPath[host, default: [:]][url.path, default: []].append(body)
        requestURLsByHostAndPath[host, default: [:]][url.path, default: []].append(url)
        lock.unlock()
    }

    private static func stringBody(from stream: InputStream) -> String {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

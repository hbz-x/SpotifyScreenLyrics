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

private struct StubHTTPResponse {
    let path: String
    let statusCode: Int
    let body: String
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

    static func setResponses(_ responses: [StubHTTPResponse], for host: String) {
        lock.lock()
        responsesByHost[host] = responses
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let stub = Self.takeResponse(for: url) else {
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
}

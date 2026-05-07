import Foundation
import Testing
@testable import SpotifyScreenLyricsCore

@Test
func fallbackLyricsFetcherUsesNextFetcherAfterLookupMiss() async throws {
    let lyrics = Lyrics(
        trackName: "Song",
        artistName: "Artist",
        plainLyrics: nil,
        syncedLyrics: "[00:01.00]Line",
        syncedLines: [LyricLine(time: 1, text: "Line")],
        source: "second"
    )
    let first = SequencedLyricsFetcher(results: [.failure(LyricsLookupError.noResult)])
    let second = SequencedLyricsFetcher(results: [.success(lyrics)])
    let fetcher = FallbackLyricsFetcher([first, second])

    let result = try await fetcher.fetchLyrics(
        for: TrackLookupKey(title: "Song", artist: "Artist", album: "Album", duration: 100)
    )

    #expect(result == lyrics)
    #expect(await first.fetchCount == 1)
    #expect(await second.fetchCount == 1)
}

@Test
func fallbackLyricsFetcherStopsOnServiceFailure() async {
    let first = SequencedLyricsFetcher(results: [.failure(URLError(.timedOut))])
    let second = SequencedLyricsFetcher(results: [
        .success(Lyrics(
            trackName: "Song",
            artistName: "Artist",
            plainLyrics: nil,
            syncedLyrics: "[00:01.00]Line",
            syncedLines: [LyricLine(time: 1, text: "Line")]
        ))
    ])
    let fetcher = FallbackLyricsFetcher([first, second])

    do {
        _ = try await fetcher.fetchLyrics(
            for: TrackLookupKey(title: "Song", artist: "Artist", album: "Album", duration: 100)
        )
        Issue.record("Expected first service failure to be returned")
    } catch {
        #expect((error as? URLError)?.code == .timedOut)
    }

    #expect(await first.fetchCount == 1)
    #expect(await second.fetchCount == 0)
}

private actor SequencedLyricsFetcher: LyricsFetching {
    private(set) var fetchCount = 0
    private var results: [Result<Lyrics, Error>]

    init(results: [Result<Lyrics, Error>]) {
        self.results = results
    }

    func fetchLyrics(for track: TrackLookupKey) async throws -> Lyrics {
        fetchCount += 1
        guard !results.isEmpty else {
            throw LyricsLookupError.noResult
        }
        return try results.removeFirst().get()
    }
}

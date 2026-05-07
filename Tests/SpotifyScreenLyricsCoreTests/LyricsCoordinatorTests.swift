import Foundation
import Testing
@testable import SpotifyScreenLyricsCore

@Test
func refreshReusesSingleInFlightLyricsRequestForSameTrack() async {
    let track = SpotifyTrack(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 100,
        position: 1,
        isPlaying: true
    )
    let spotify = StubSpotifyReader(track: track)
    let fetcher = CountingLyricsFetcher(
        result: .success(
            Lyrics(
                trackName: "Song",
                artistName: "Artist",
                plainLyrics: nil,
                syncedLyrics: "[00:00.00]Line",
                syncedLines: [LyricLine(time: 0, text: "Line")]
            )
        ),
        delayNanoseconds: 100_000_000
    )
    let coordinator = LyricsCoordinator(
        spotifyReader: spotify,
        lyricsFetcher: fetcher,
        lyricsCache: MemoryLyricsCache()
    )

    async let first = coordinator.refresh()
    async let second = coordinator.refresh()
    _ = await (first, second)
    try? await Task.sleep(nanoseconds: 10_000_000)

    #expect(await fetcher.fetchCount == 1)
}

@Test
func refreshDoesNotRestartRequestWhenOnlyDurationPrecisionChanges() async {
    let spotify = SequencedSpotifyReader(tracks: [
        SpotifyTrack(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 100.2,
            position: 1,
            isPlaying: true
        ),
        SpotifyTrack(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 100.3,
            position: 2,
            isPlaying: true
        )
    ])
    let fetcher = CountingLyricsFetcher(
        result: .success(
            Lyrics(
                trackName: "Song",
                artistName: "Artist",
                plainLyrics: nil,
                syncedLyrics: "[00:00.00]Line",
                syncedLines: [LyricLine(time: 0, text: "Line")]
            )
        ),
        delayNanoseconds: 100_000_000
    )
    let coordinator = LyricsCoordinator(
        spotifyReader: spotify,
        lyricsFetcher: fetcher,
        lyricsCache: MemoryLyricsCache()
    )

    _ = await coordinator.refresh()
    _ = await coordinator.refresh()
    try? await Task.sleep(nanoseconds: 10_000_000)

    #expect(await fetcher.fetchCount == 1)
}

@Test
func refreshSwitchesSlowForegroundLoadToBackgroundMessage() async {
    let track = SpotifyTrack(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 100,
        position: 1,
        isPlaying: true
    )
    let spotify = StubSpotifyReader(track: track)
    let fetcher = CountingLyricsFetcher(
        result: .success(
            Lyrics(
                trackName: "Song",
                artistName: "Artist",
                plainLyrics: nil,
                syncedLyrics: "[00:00.00]Line",
                syncedLines: [LyricLine(time: 0, text: "Line")]
            )
        ),
        delayNanoseconds: 100_000_000
    )
    let coordinator = LyricsCoordinator(
        spotifyReader: spotify,
        lyricsFetcher: fetcher,
        lyricsCache: MemoryLyricsCache(),
        foregroundLoadingLimit: .milliseconds(1)
    )

    _ = await coordinator.refresh()
    try? await Task.sleep(nanoseconds: 10_000_000)
    let status = await coordinator.refresh()

    #expect(status == .retryingInBackground(
        trackTitle: "Song",
        artist: "Artist",
        message: "Downloading lyrics in background"
    ))
    #expect(await fetcher.fetchCount == 1)
}

@Test
func refreshCachesNoSyncedLyricsForSameTrack() async {
    let track = SpotifyTrack(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 100,
        position: 1,
        isPlaying: true
    )
    let spotify = StubSpotifyReader(track: track)
    let fetcher = CountingLyricsFetcher(result: .failure(LyricsLookupError.noResult))
    let coordinator = LyricsCoordinator(
        spotifyReader: spotify,
        lyricsFetcher: fetcher,
        lyricsCache: MemoryLyricsCache()
    )

    _ = await coordinator.refresh()
    _ = await coordinator.refresh()
    _ = await coordinator.refresh()
    try? await Task.sleep(nanoseconds: 10_000_000)

    #expect(await fetcher.fetchCount == 1)
}

@Test
func timeoutDisplaysBackgroundDownloadMessage() async {
    let track = SpotifyTrack(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 100,
        position: 1,
        isPlaying: true
    )
    let spotify = StubSpotifyReader(track: track)
    let fetcher = CountingLyricsFetcher(result: .failure(URLError(.timedOut)))
    let coordinator = LyricsCoordinator(
        spotifyReader: spotify,
        lyricsFetcher: fetcher,
        lyricsCache: MemoryLyricsCache()
    )

    _ = await coordinator.refresh()
    try? await Task.sleep(nanoseconds: 10_000_000)
    let status = await coordinator.refresh()

    #expect(status == .retryingInBackground(
        trackTitle: "Song",
        artist: "Artist",
        message: "Downloading lyrics in background"
    ))
}

@Test
func failedLyricsLoadWaitsForRetryIntervalBeforeRetrying() async {
    let track = SpotifyTrack(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 100,
        position: 1,
        isPlaying: true
    )
    let spotify = StubSpotifyReader(track: track)
    let fetcher = CountingLyricsFetcher(result: .failure(URLError(.timedOut)))
    let coordinator = LyricsCoordinator(
        spotifyReader: spotify,
        lyricsFetcher: fetcher,
        lyricsCache: MemoryLyricsCache(),
        retrySchedule: [0.05, 0.05, 0.05]
    )

    _ = await coordinator.refresh()
    try? await Task.sleep(nanoseconds: 10_000_000)
    _ = await coordinator.refresh()

    #expect(await fetcher.fetchCount == 1)

    try? await Task.sleep(nanoseconds: 60_000_000)
    _ = await coordinator.refresh()
    try? await Task.sleep(nanoseconds: 10_000_000)

    #expect(await fetcher.fetchCount == 2)
}

@Test
func failedLyricsLoadStopsAfterThreeRetries() async {
    let track = SpotifyTrack(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 100,
        position: 1,
        isPlaying: true
    )
    let spotify = StubSpotifyReader(track: track)
    let fetcher = CountingLyricsFetcher(result: .failure(URLError(.timedOut)))
    let coordinator = LyricsCoordinator(
        spotifyReader: spotify,
        lyricsFetcher: fetcher,
        lyricsCache: MemoryLyricsCache(),
        retrySchedule: [0, 0, 0]
    )

    for _ in 0..<5 {
        _ = await coordinator.refresh()
        try? await Task.sleep(nanoseconds: 10_000_000)
    }

    let status = await coordinator.refresh()

    #expect(await fetcher.fetchCount == 4)
    #expect(status == .error(message: URLError(.timedOut).localizedDescription))
}

@Test
func reloadIgnoresLateResultFromCancelledSameTrackLoad() async {
    let track = SpotifyTrack(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 100,
        position: 1,
        isPlaying: true
    )
    let spotify = StubSpotifyReader(track: track)
    let fetcher = SequencedDelayedLyricsFetcher(results: [
        DelayedLyricsResult(
            lyrics: Lyrics(
                trackName: "Song",
                artistName: "Artist",
                plainLyrics: nil,
                syncedLyrics: "[00:00.00]Old line",
                syncedLines: [LyricLine(time: 0, text: "Old line")]
            ),
            delayNanoseconds: 120_000_000
        ),
        DelayedLyricsResult(
            lyrics: Lyrics(
                trackName: "Song",
                artistName: "Artist",
                plainLyrics: nil,
                syncedLyrics: "[00:00.00]New line",
                syncedLines: [LyricLine(time: 0, text: "New line")]
            ),
            delayNanoseconds: 10_000_000
        )
    ])
    let coordinator = LyricsCoordinator(
        spotifyReader: spotify,
        lyricsFetcher: fetcher,
        lyricsCache: MemoryLyricsCache()
    )

    _ = await coordinator.refresh()
    try? await Task.sleep(nanoseconds: 10_000_000)
    await coordinator.reload()
    _ = await coordinator.refresh()
    try? await Task.sleep(nanoseconds: 180_000_000)

    let status = await coordinator.refresh()

    #expect(status == .ready(
        trackTitle: "Song",
        artist: "Artist",
        lyrics: DisplayLyrics(currentLine: "New line", nextLine: nil),
        isPlaying: true
    ))
    #expect(await fetcher.fetchCount == 2)
}

final class StubSpotifyReader: SpotifyReading, @unchecked Sendable {
    private let track: SpotifyTrack

    init(track: SpotifyTrack) {
        self.track = track
    }

    func currentTrack() async throws -> SpotifyTrack {
        track
    }
}

actor SequencedSpotifyReader: SpotifyReading {
    private let tracks: [SpotifyTrack]
    private var index = 0

    init(tracks: [SpotifyTrack]) {
        self.tracks = tracks
    }

    func currentTrack() async throws -> SpotifyTrack {
        let track = tracks[min(index, tracks.count - 1)]
        index += 1
        return track
    }
}

actor CountingLyricsFetcher: LyricsFetching {
    private(set) var fetchCount = 0
    private let delayNanoseconds: UInt64
    private let result: Result<Lyrics, Error>

    init(result: Result<Lyrics, Error>, delayNanoseconds: UInt64 = 0) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func fetchLyrics(for track: TrackLookupKey) async throws -> Lyrics {
        fetchCount += 1
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try result.get()
    }
}

struct DelayedLyricsResult: Sendable {
    let lyrics: Lyrics
    let delayNanoseconds: UInt64
}

actor SequencedDelayedLyricsFetcher: LyricsFetching {
    private(set) var fetchCount = 0
    private var results: [DelayedLyricsResult]

    init(results: [DelayedLyricsResult]) {
        self.results = results
    }

    func fetchLyrics(for track: TrackLookupKey) async throws -> Lyrics {
        fetchCount += 1
        guard !results.isEmpty else {
            throw LyricsLookupError.noResult
        }
        let result = results.removeFirst()
        if result.delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: result.delayNanoseconds)
        }
        return result.lyrics
    }
}

actor MemoryLyricsCache: LyricsCaching {
    nonisolated let cacheDirectory = URL(fileURLWithPath: "/tmp/SpotifyScreenLyricsMemoryCache", isDirectory: true)
    private var storage: [String: Lyrics] = [:]

    func loadLyrics(for key: TrackLookupKey) async -> Lyrics? {
        storage[key.stableID]
    }

    func saveLyrics(_ lyrics: Lyrics, for key: TrackLookupKey) async throws {
        storage[key.stableID] = lyrics
    }

    func importLyrics(from folderURL: URL) async throws -> LyricsImportResult {
        LyricsImportResult(imported: 0, skipped: 0, failed: 0)
    }

    func exportLyrics(to folderURL: URL) async throws -> LyricsImportResult {
        LyricsImportResult(imported: storage.count, skipped: 0, failed: 0)
    }
}

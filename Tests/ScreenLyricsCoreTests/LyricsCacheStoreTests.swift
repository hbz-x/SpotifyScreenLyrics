import Foundation
import Testing
@testable import ScreenLyricsCore

@Test
func saveAndLoadLyricsFromCache() async throws {
    let cache = LyricsCacheStore(cacheDirectory: temporaryDirectory())
    let key = TrackLookupKey(title: "Song", artist: "Artist", album: "Album", duration: 100)
    let lyrics = Lyrics(
        trackName: "Song",
        artistName: "Artist",
        plainLyrics: nil,
        syncedLyrics: "[00:00.00]Cached line",
        syncedLines: [LyricLine(time: 0, text: "Cached line")]
    )

    try await cache.saveLyrics(lyrics, for: key)
    let loaded = await cache.loadLyrics(for: key)

    #expect(loaded?.syncedLyrics == "[00:00.00]Cached line")
    #expect(loaded?.syncedLines == [LyricLine(time: 0, text: "Cached line")])
}

@Test
func coordinatorUsesCacheBeforeNetwork() async throws {
    let cache = LyricsCacheStore(cacheDirectory: temporaryDirectory())
    let key = TrackLookupKey(title: "Song", artist: "Artist", album: "Album", duration: 100)
    try await cache.saveLyrics(
        Lyrics(
            trackName: "Song",
            artistName: "Artist",
            plainLyrics: nil,
            syncedLyrics: "[00:00.00]Cached line",
            syncedLines: [LyricLine(time: 0, text: "Cached line")]
        ),
        for: key
    )

    let spotify = StubSpotifyReader(track: SpotifyTrack(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 100,
        position: 1,
        isPlaying: true
    ))
    let fetcher = CountingLyricsFetcher(result: .failure(LyricsLookupError.badResponse))
    let coordinator = LyricsCoordinator(spotifyReader: spotify, lyricsFetcher: fetcher, lyricsCache: cache)

    _ = await coordinator.refresh()
    try await Task.sleep(nanoseconds: 10_000_000)
    let status = await coordinator.refresh()

    #expect(status == .ready(
        trackTitle: "Song",
        artist: "Artist",
        lyrics: DisplayLyrics(currentLine: "Cached line", nextLine: nil),
        isPlaying: true
    ))
    #expect(await fetcher.fetchCount == 0)
}

@Test
func coordinatorFallsBackToNetworkWhenCacheMisses() async throws {
    let cache = LyricsCacheStore(cacheDirectory: temporaryDirectory())
    let spotify = StubSpotifyReader(track: SpotifyTrack(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 100,
        position: 1,
        isPlaying: true
    ))
    let fetcher = CountingLyricsFetcher(result: .success(Lyrics(
        trackName: "Song",
        artistName: "Artist",
        plainLyrics: nil,
        syncedLyrics: "[00:00.00]Downloaded line",
        syncedLines: [LyricLine(time: 0, text: "Downloaded line")]
    )))
    let coordinator = LyricsCoordinator(spotifyReader: spotify, lyricsFetcher: fetcher, lyricsCache: cache)

    _ = await coordinator.refresh()
    try await Task.sleep(nanoseconds: 10_000_000)
    let status = await coordinator.refresh()
    let cached = await cache.loadLyrics(for: TrackLookupKey(title: "Song", artist: "Artist", album: "Album", duration: 100))

    #expect(await fetcher.fetchCount == 1)
    #expect(status == .ready(
        trackTitle: "Song",
        artist: "Artist",
        lyrics: DisplayLyrics(currentLine: "Downloaded line", nextLine: nil),
        isPlaying: true
    ))
    #expect(cached?.syncedLyrics == "[00:00.00]Downloaded line")
}

@Test
func importPlainLRCFolderSkipsExisting() async throws {
    let cache = LyricsCacheStore(cacheDirectory: temporaryDirectory())
    let folder = temporaryDirectory()
    let lrcURL = folder.appendingPathComponent("Artist - Song.lrc")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try "[00:00.00]Imported line".write(to: lrcURL, atomically: true, encoding: .utf8)

    let first = try await cache.importLyrics(from: folder)
    let second = try await cache.importLyrics(from: folder)

    #expect(first.imported == 1)
    #expect(first.skipped == 0)
    #expect(second.imported == 0)
    #expect(second.skipped == 1)
}

@Test
func exportFolderCanBeImportedAgain() async throws {
    let sourceCache = LyricsCacheStore(cacheDirectory: temporaryDirectory())
    let key = TrackLookupKey(title: "Song", artist: "Artist", album: "Album", duration: 100)
    try await sourceCache.saveLyrics(
        Lyrics(
            trackName: "Song",
            artistName: "Artist",
            plainLyrics: nil,
            syncedLyrics: "[00:00.00]Exported line",
            syncedLines: [LyricLine(time: 0, text: "Exported line")]
        ),
        for: key
    )

    let exportFolder = temporaryDirectory()
    let exportResult = try await sourceCache.exportLyrics(to: exportFolder)

    let importedCache = LyricsCacheStore(cacheDirectory: temporaryDirectory())
    let importResult = try await importedCache.importLyrics(from: exportFolder)
    let loaded = await importedCache.loadLyrics(for: key)

    #expect(exportResult.imported == 1)
    #expect(importResult.imported == 1)
    #expect(loaded?.syncedLines == [LyricLine(time: 0, text: "Exported line")])
}

@Test
func importManifestRejectsPathTraversalFileName() async throws {
    let importFolder = temporaryDirectory()
    let lyricsFolder = importFolder.appendingPathComponent("lyrics", isDirectory: true)
    try FileManager.default.createDirectory(at: lyricsFolder, withIntermediateDirectories: true)
    try "[00:00.00]Outside".write(
        to: importFolder.appendingPathComponent("outside.lrc"),
        atomically: true,
        encoding: .utf8
    )
    let manifest = """
    {
      "version": 1,
      "entries": [
        {
          "id": "artist|song||0",
          "title": "Song",
          "artist": "Artist",
          "album": "",
          "duration": 0,
          "fileName": "../outside.lrc",
          "source": "import",
          "savedAt": 0
        }
      ]
    }
    """
    try manifest.write(
        to: importFolder.appendingPathComponent("manifest.json"),
        atomically: true,
        encoding: .utf8
    )

    let cache = LyricsCacheStore(cacheDirectory: temporaryDirectory())
    let result = try await cache.importLyrics(from: importFolder)
    let loaded = await cache.loadLyrics(for: TrackLookupKey(title: "Song", artist: "Artist", album: "", duration: 0))

    #expect(result.imported == 0)
    #expect(result.failed == 1)
    #expect(loaded == nil)
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ScreenLyricsTests-\(UUID().uuidString)", isDirectory: true)
}

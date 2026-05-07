import Foundation

public actor LyricsCoordinator {
    private static let timeoutRetryMessage = "Downloading lyrics in background"
    private let spotifyReader: SpotifyReading
    private let lyricsFetcher: LyricsFetching
    private let lyricsCache: LyricsCaching
    private let retrySchedule: [TimeInterval]
    private let foregroundLoadingLimit: Duration
    private var cachedKey: TrackLookupKey?
    private var lyricState: CachedLyricState = .empty
    private var loadingTask: Task<Void, Never>?
    private var loadingStartedAt: ContinuousClock.Instant?
    private var retryState: [String: RetryState] = [:]

    public init(
        spotifyReader: SpotifyReading,
        lyricsFetcher: LyricsFetching,
        lyricsCache: LyricsCaching = LyricsCacheStore(),
        retrySchedule: [TimeInterval] = [30, 120, 300],
        foregroundLoadingLimit: Duration = .seconds(3)
    ) {
        self.spotifyReader = spotifyReader
        self.lyricsFetcher = lyricsFetcher
        self.lyricsCache = lyricsCache
        self.retrySchedule = retrySchedule
        self.foregroundLoadingLimit = foregroundLoadingLimit
    }

    public func reload() {
        cachedKey = nil
        lyricState = .empty
        loadingTask?.cancel()
        loadingTask = nil
        loadingStartedAt = nil
    }

    public var cacheDirectory: URL {
        lyricsCache.cacheDirectory
    }

    public func importLyrics(from folderURL: URL) async throws -> LyricsImportResult {
        let result = try await lyricsCache.importLyrics(from: folderURL)
        reload()
        return result
    }

    public func exportLyrics(to folderURL: URL) async throws -> LyricsImportResult {
        try await lyricsCache.exportLyrics(to: folderURL)
    }

    public func refresh() async -> LyricsStatus {
        let track: SpotifyTrack
        do {
            track = try await spotifyReader.currentTrack()
        } catch SpotifyError.notRunning {
            return .waitingForSpotify
        } catch SpotifyError.noTrack {
            return .waitingForSpotify
        } catch {
            return .error(message: readableMessage(for: error))
        }

        let key = track.lookupKey
        if cachedKey != key {
            LyricsDebugLog.write("Track changed \(LyricsDebugLog.trackSummary(key))")
            cachedKey = key
            lyricState = .empty
            loadingTask?.cancel()
            loadingTask = nil
            loadingStartedAt = nil
        }

        switch lyricState {
        case .empty:
            startLyricsLoad(for: key)
            return .loading(trackTitle: track.title, artist: track.artist)
        case .loading:
            if let loadingTask, loadingTask.isCancelled == false {
                if hasExceededForegroundLoadingLimit() {
                    return .retryingInBackground(
                        trackTitle: track.title,
                        artist: track.artist,
                        message: Self.timeoutRetryMessage
                    )
                }
                return .loading(trackTitle: track.title, artist: track.artist)
            } else {
                lyricState = .empty
                loadingStartedAt = nil
                return .loading(trackTitle: track.title, artist: track.artist)
            }
        case .lyrics:
            break
        case .noSyncedLyrics:
            return .noSyncedLyrics(trackTitle: track.title, artist: track.artist)
        case .failed:
            if shouldRetry(for: key) {
                startLyricsLoad(for: key)
                return .retryingInBackground(
                    trackTitle: track.title,
                    artist: track.artist,
                    message: Self.timeoutRetryMessage
                )
            }
            return .retryingInBackground(
                trackTitle: track.title,
                artist: track.artist,
                message: Self.timeoutRetryMessage
            )
        }

        guard case .lyrics(let lyrics) = lyricState,
              let displayLyrics = LyricsTimeline.displayLines(for: track.position, lines: lyrics.syncedLines) else {
            return .noSyncedLyrics(trackTitle: track.title, artist: track.artist)
        }

        return .ready(
            trackTitle: track.title,
            artist: track.artist,
            lyrics: displayLyrics,
            isPlaying: track.isPlaying
        )
    }

    private func startLyricsLoad(for key: TrackLookupKey) {
        lyricState = .loading
        loadingStartedAt = ContinuousClock.now
        let trackSummary = LyricsDebugLog.trackSummary(key)
        LyricsDebugLog.write("Lyrics load started \(trackSummary)")
        loadingTask = Task { [lyricsCache, lyricsFetcher] in
            let loadStartedAt = ContinuousClock.now
            let cacheStartedAt = ContinuousClock.now
            if let cachedLyrics = await lyricsCache.loadLyrics(for: key) {
                let cacheElapsed = ContinuousClock.now.elapsedMilliseconds(since: cacheStartedAt)
                let totalElapsed = ContinuousClock.now.elapsedMilliseconds(since: loadStartedAt)
                LyricsDebugLog.write(
                    "Lyrics cache hit \(trackSummary) syncedLines=\(cachedLyrics.syncedLines.count) cacheElapsed=\(cacheElapsed) totalElapsed=\(totalElapsed)"
                )
                await finishLyricsLoad(.lyrics(cachedLyrics), for: key, loadStartedAt: loadStartedAt)
                return
            }

            let cacheElapsed = ContinuousClock.now.elapsedMilliseconds(since: cacheStartedAt)
            LyricsDebugLog.write("Lyrics cache miss \(trackSummary) cacheElapsed=\(cacheElapsed)")

            do {
                let fetchStartedAt = ContinuousClock.now
                let lyrics = try await lyricsFetcher.fetchLyrics(for: key)
                let fetchElapsed = ContinuousClock.now.elapsedMilliseconds(since: fetchStartedAt)
                LyricsDebugLog.write(
                    "Lyrics fetch returned \(trackSummary) syncedLines=\(lyrics.syncedLines.count) fetchElapsed=\(fetchElapsed)"
                )

                let saveStartedAt = ContinuousClock.now
                do {
                    try await lyricsCache.saveLyrics(lyrics, for: key)
                    let saveElapsed = ContinuousClock.now.elapsedMilliseconds(since: saveStartedAt)
                    LyricsDebugLog.write("Lyrics cache save succeeded \(trackSummary) saveElapsed=\(saveElapsed)")
                } catch {
                    let saveElapsed = ContinuousClock.now.elapsedMilliseconds(since: saveStartedAt)
                    LyricsDebugLog.write(
                        "Lyrics cache save failed \(trackSummary) saveElapsed=\(saveElapsed): \(error.localizedDescription)"
                    )
                }

                await finishLyricsLoad(.lyrics(lyrics), for: key, loadStartedAt: loadStartedAt)
            } catch LyricsLookupError.noSyncedLyrics {
                LyricsDebugLog.write("Lyrics load found no synced lyrics \(trackSummary)")
                await finishLyricsLoad(.noSyncedLyrics, for: key, loadStartedAt: loadStartedAt)
            } catch LyricsLookupError.noResult {
                LyricsDebugLog.write("Lyrics load found no LRCLIB result \(trackSummary)")
                await finishLyricsLoad(.noSyncedLyrics, for: key, loadStartedAt: loadStartedAt)
            } catch is CancellationError {
                LyricsDebugLog.write("Lyrics load cancelled \(trackSummary)")
                await finishLyricsLoad(.empty, for: key, loadStartedAt: loadStartedAt)
            } catch {
                LyricsDebugLog.write(
                    "Lyrics load failed \(trackSummary): \(error.localizedDescription)"
                )
                await finishLyricsLoad(
                    .failed(readableMessage(for: error)),
                    for: key,
                    didFail: true,
                    loadStartedAt: loadStartedAt
                )
            }
        }
    }

    private func finishLyricsLoad(
        _ state: CachedLyricState,
        for key: TrackLookupKey,
        didFail: Bool = false,
        loadStartedAt: ContinuousClock.Instant? = nil
    ) async {
        guard cachedKey == key else {
            LyricsDebugLog.write("Ignoring stale lyrics load result \(LyricsDebugLog.trackSummary(key))")
            return
        }
        if didFail {
            recordFailure(for: key)
        }
        lyricState = state
        loadingTask = nil
        loadingStartedAt = nil
        let elapsed = loadStartedAt.map { ContinuousClock.now.elapsedMilliseconds(since: $0) } ?? "unknown"
        LyricsDebugLog.write(
            "Lyrics load finished state=\(state.debugName) \(LyricsDebugLog.trackSummary(key)) elapsed=\(elapsed)"
        )
    }

    private func hasExceededForegroundLoadingLimit() -> Bool {
        guard let loadingStartedAt else {
            return false
        }

        return loadingStartedAt.duration(to: ContinuousClock.now) >= foregroundLoadingLimit
    }

    private func recordFailure(for key: TrackLookupKey) {
        let current = retryState[key.stableID] ?? RetryState(failureCount: 0, nextRetryAt: .distantPast)
        let failureCount = current.failureCount + 1
        let delayIndex = min(failureCount - 1, max(retrySchedule.count - 1, 0))
        let delay = retrySchedule.isEmpty ? 300 : retrySchedule[delayIndex]
        retryState[key.stableID] = RetryState(
            failureCount: failureCount,
            nextRetryAt: Date().addingTimeInterval(delay)
        )
        LyricsDebugLog.write(
            "Lyrics load retry scheduled \(LyricsDebugLog.trackSummary(key)) failureCount=\(failureCount) delay=\(String(format: "%.0fs", delay))"
        )
    }

    private func shouldRetry(for key: TrackLookupKey) -> Bool {
        guard let state = retryState[key.stableID] else {
            return true
        }
        return Date() >= state.nextRetryAt
    }

    private func readableMessage(for error: Error) -> String {
        if let spotifyError = error as? SpotifyError {
            switch spotifyError {
            case .notRunning, .noTrack:
                return "Waiting for Spotify"
            case .scriptFailed(let message):
                return message
            }
        }

        if let lookupError = error as? LyricsLookupError {
            switch lookupError {
            case .noResult, .noSyncedLyrics:
                return "No synced lyrics found"
            case .badResponse:
                return "Lyrics service returned an invalid response"
            }
        }

        return error.localizedDescription
    }
}

private enum CachedLyricState: Sendable {
    case empty
    case loading
    case lyrics(Lyrics)
    case noSyncedLyrics
    case failed(String)

    var debugName: String {
        switch self {
        case .empty:
            return "empty"
        case .loading:
            return "loading"
        case .lyrics:
            return "lyrics"
        case .noSyncedLyrics:
            return "noSyncedLyrics"
        case .failed:
            return "failed"
        }
    }
}

private struct RetryState: Sendable {
    let failureCount: Int
    let nextRetryAt: Date
}

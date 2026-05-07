import Foundation

public actor LyricsCoordinator {
    private let spotifyReader: SpotifyReading
    private let lyricsFetcher: LyricsFetching
    private let lyricsCache: LyricsCaching
    private let retrySchedule: [TimeInterval]
    private var cachedKey: TrackLookupKey?
    private var lyricState: CachedLyricState = .empty
    private var loadingTask: Task<Void, Never>?
    private var retryState: [String: RetryState] = [:]

    public init(
        spotifyReader: SpotifyReading,
        lyricsFetcher: LyricsFetching,
        lyricsCache: LyricsCaching = LyricsCacheStore(),
        retrySchedule: [TimeInterval] = [30, 120, 300]
    ) {
        self.spotifyReader = spotifyReader
        self.lyricsFetcher = lyricsFetcher
        self.lyricsCache = lyricsCache
        self.retrySchedule = retrySchedule
    }

    public func reload() {
        cachedKey = nil
        lyricState = .empty
        loadingTask?.cancel()
        loadingTask = nil
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
            cachedKey = key
            lyricState = .empty
            loadingTask?.cancel()
            loadingTask = nil
        }

        switch lyricState {
        case .empty:
            startLyricsLoad(for: key)
            return .loading(trackTitle: track.title, artist: track.artist)
        case .loading:
            if let loadingTask, loadingTask.isCancelled == false {
                return .loading(trackTitle: track.title, artist: track.artist)
            } else {
                lyricState = .empty
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
                    message: "Downloading lyrics from LRCLIB"
                )
            }
            return .retryingInBackground(
                trackTitle: track.title,
                artist: track.artist,
                message: "LRCLIB timed out; will retry in background"
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
        loadingTask = Task { [lyricsCache, lyricsFetcher] in
            if let cachedLyrics = await lyricsCache.loadLyrics(for: key) {
                await finishLyricsLoad(.lyrics(cachedLyrics), for: key)
                return
            }

            do {
                let lyrics = try await lyricsFetcher.fetchLyrics(for: key)
                try? await lyricsCache.saveLyrics(lyrics, for: key)
                await finishLyricsLoad(.lyrics(lyrics), for: key)
            } catch LyricsLookupError.noSyncedLyrics {
                await finishLyricsLoad(.noSyncedLyrics, for: key)
            } catch LyricsLookupError.noResult {
                await finishLyricsLoad(.noSyncedLyrics, for: key)
            } catch is CancellationError {
                await finishLyricsLoad(.empty, for: key)
            } catch {
                await finishLyricsLoad(.failed(readableMessage(for: error)), for: key, didFail: true)
            }
        }
    }

    private func finishLyricsLoad(_ state: CachedLyricState, for key: TrackLookupKey, didFail: Bool = false) {
        guard cachedKey == key else {
            return
        }
        if didFail {
            recordFailure(for: key)
        }
        lyricState = state
        loadingTask = nil
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
}

private struct RetryState: Sendable {
    let failureCount: Int
    let nextRetryAt: Date
}

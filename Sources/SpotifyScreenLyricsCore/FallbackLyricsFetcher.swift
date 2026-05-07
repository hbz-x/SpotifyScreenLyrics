import Foundation

public final class FallbackLyricsFetcher: LyricsFetching, @unchecked Sendable {
    private let fetchers: [LyricsFetching]

    public init(_ fetchers: [LyricsFetching]) {
        self.fetchers = fetchers
    }

    public func fetchLyrics(for track: TrackLookupKey) async throws -> Lyrics {
        guard !fetchers.isEmpty else {
            throw LyricsLookupError.noResult
        }

        var lastLookupMiss: LyricsLookupError?

        for fetcher in fetchers {
            do {
                return try await fetcher.fetchLyrics(for: track)
            } catch LyricsLookupError.noResult {
                lastLookupMiss = .noResult
                continue
            } catch LyricsLookupError.noSyncedLyrics {
                lastLookupMiss = .noSyncedLyrics
                continue
            }
        }

        throw lastLookupMiss ?? LyricsLookupError.noResult
    }
}

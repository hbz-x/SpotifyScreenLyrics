import Foundation

public struct LyricsImportResult: Equatable, Sendable {
    public let imported: Int
    public let skipped: Int
    public let failed: Int

    public init(imported: Int, skipped: Int, failed: Int) {
        self.imported = imported
        self.skipped = skipped
        self.failed = failed
    }
}

public protocol LyricsCaching: Sendable {
    nonisolated var cacheDirectory: URL { get }
    func loadLyrics(for key: TrackLookupKey) async -> Lyrics?
    func saveLyrics(_ lyrics: Lyrics, for key: TrackLookupKey) async throws
    func importLyrics(from folderURL: URL) async throws -> LyricsImportResult
    func exportLyrics(to folderURL: URL) async throws -> LyricsImportResult
}

public actor LyricsCacheStore: LyricsCaching {
    public nonisolated let cacheDirectory: URL
    private let manifestURL: URL
    private let lyricsDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var manifest: LyricsCacheManifest

    public init(cacheDirectory: URL? = nil) {
        let root = cacheDirectory ?? Self.defaultCacheDirectory()
        self.cacheDirectory = root
        self.manifestURL = root.appendingPathComponent("manifest.json")
        self.lyricsDirectory = root.appendingPathComponent("lyrics", isDirectory: true)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.manifest = LyricsCacheManifest(version: 1, entries: [])
    }

    public static func defaultCacheDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("SpotifyScreenLyrics", isDirectory: true)
            .appendingPathComponent("LyricsCache", isDirectory: true)
    }

    public func loadLyrics(for key: TrackLookupKey) async -> Lyrics? {
        do {
            try ensureLoaded()
            guard let entry = entry(for: key) else {
                return nil
            }
            let fileURL = lyricsDirectory.appendingPathComponent(entry.fileName)
            let syncedLyrics = try String(contentsOf: fileURL, encoding: .utf8)
            let syncedLines = LRCParser.parse(syncedLyrics)
            guard !syncedLines.isEmpty else {
                return nil
            }
            return Lyrics(
                trackName: entry.title,
                artistName: entry.artist,
                plainLyrics: nil,
                syncedLyrics: syncedLyrics,
                syncedLines: syncedLines
            )
        } catch {
            return nil
        }
    }

    public func saveLyrics(_ lyrics: Lyrics, for key: TrackLookupKey) async throws {
        try ensureLoaded()
        try ensureDirectories()

        let fileName = fileName(for: key)
        let fileURL = lyricsDirectory.appendingPathComponent(fileName)
        try lyrics.syncedLyrics.write(to: fileURL, atomically: true, encoding: .utf8)

        let entry = LyricsCacheEntry(
            id: key.stableID,
            title: key.title,
            artist: key.artist,
            album: key.album,
            duration: Int(key.duration.rounded()),
            fileName: fileName,
            source: "lrclib",
            savedAt: Date()
        )
        upsert(entry)
        try saveManifest()
    }

    public func importLyrics(from folderURL: URL) async throws -> LyricsImportResult {
        try ensureLoaded()
        try ensureDirectories()

        if FileManager.default.fileExists(atPath: folderURL.appendingPathComponent("manifest.json").path) {
            return try importSpotifyScreenLyricsFolder(from: folderURL)
        }

        return try importPlainLRCFolder(from: folderURL)
    }

    public func exportLyrics(to folderURL: URL) async throws -> LyricsImportResult {
        try ensureLoaded()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let exportLyricsDirectory = folderURL.appendingPathComponent("lyrics", isDirectory: true)
        try FileManager.default.createDirectory(at: exportLyricsDirectory, withIntermediateDirectories: true)

        var exportedEntries: [LyricsCacheEntry] = []
        var failed = 0

        for entry in manifest.entries {
            let sourceURL = lyricsDirectory.appendingPathComponent(entry.fileName)
            let destinationURL = exportLyricsDirectory.appendingPathComponent(entry.fileName)
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                exportedEntries.append(entry)
            } catch {
                failed += 1
            }
        }

        let exportManifest = LyricsCacheManifest(version: 1, entries: exportedEntries)
        let data = try encoder.encode(exportManifest)
        try data.write(to: folderURL.appendingPathComponent("manifest.json"), options: .atomic)
        return LyricsImportResult(imported: exportedEntries.count, skipped: 0, failed: failed)
    }

    private func importSpotifyScreenLyricsFolder(from folderURL: URL) throws -> LyricsImportResult {
        let importManifestURL = folderURL.appendingPathComponent("manifest.json")
        let importLyricsDirectory = folderURL.appendingPathComponent("lyrics", isDirectory: true)
        let data = try Data(contentsOf: importManifestURL)
        let importedManifest = try decoder.decode(LyricsCacheManifest.self, from: data)

        var imported = 0
        var skipped = 0
        var failed = 0

        for entry in importedManifest.entries {
            if self.entry(id: entry.id) != nil {
                skipped += 1
                continue
            }

            guard isSafeImportedFileName(entry.fileName) else {
                failed += 1
                continue
            }

            let sourceURL = importLyricsDirectory.appendingPathComponent(entry.fileName)
            let syncedLyrics: String
            do {
                syncedLyrics = try String(contentsOf: sourceURL, encoding: .utf8)
                guard !LRCParser.parse(syncedLyrics).isEmpty else {
                    failed += 1
                    continue
                }
                let key = TrackLookupKey(
                    title: entry.title,
                    artist: entry.artist,
                    album: entry.album,
                    duration: TimeInterval(entry.duration)
                )
                let fileName = fileName(for: key)
                try syncedLyrics.write(to: lyricsDirectory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
                upsert(entry.copy(fileName: fileName, savedAt: Date()))
                imported += 1
            } catch {
                failed += 1
            }
        }

        try saveManifest()
        return LyricsImportResult(imported: imported, skipped: skipped, failed: failed)
    }

    private func importPlainLRCFolder(from folderURL: URL) throws -> LyricsImportResult {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "lrc" }

        var imported = 0
        var skipped = 0
        var failed = 0

        for url in urls {
            guard let parsed = parsePlainLRCFileName(url.deletingPathExtension().lastPathComponent) else {
                failed += 1
                continue
            }

            let key = TrackLookupKey(title: parsed.title, artist: parsed.artist, album: "", duration: 0)
            if entry(for: key) != nil {
                skipped += 1
                continue
            }

            do {
                let syncedLyrics = try String(contentsOf: url, encoding: .utf8)
                guard !LRCParser.parse(syncedLyrics).isEmpty else {
                    failed += 1
                    continue
                }
                let fileName = fileName(for: key)
                try syncedLyrics.write(to: lyricsDirectory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
                upsert(LyricsCacheEntry(
                    id: key.stableID,
                    title: key.title,
                    artist: key.artist,
                    album: key.album,
                    duration: Int(key.duration.rounded()),
                    fileName: fileName,
                    source: "import",
                    savedAt: Date()
                ))
                imported += 1
            } catch {
                failed += 1
            }
        }

        try saveManifest()
        return LyricsImportResult(imported: imported, skipped: skipped, failed: failed)
    }

    private func ensureLoaded() throws {
        try ensureDirectories()
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            manifest = LyricsCacheManifest(version: 1, entries: [])
            try saveManifest()
            return
        }

        let data = try Data(contentsOf: manifestURL)
        manifest = try decoder.decode(LyricsCacheManifest.self, from: data)
    }

    private func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: lyricsDirectory, withIntermediateDirectories: true)
    }

    private func saveManifest() throws {
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    private func entry(for key: TrackLookupKey) -> LyricsCacheEntry? {
        if let exact = entry(id: key.stableID) {
            return exact
        }

        let title = key.title.normalizedForLookup()
        let artist = key.artist.normalizedForLookup()
        return manifest.entries.first {
            $0.title.normalizedForLookup() == title &&
            $0.artist.normalizedForLookup() == artist
        }
    }

    private func entry(id: String) -> LyricsCacheEntry? {
        manifest.entries.first { $0.id == id }
    }

    private func upsert(_ entry: LyricsCacheEntry) {
        if let index = manifest.entries.firstIndex(where: { $0.id == entry.id }) {
            manifest.entries[index] = entry
        } else {
            manifest.entries.append(entry)
        }
    }

    private func fileName(for key: TrackLookupKey) -> String {
        let readableName = "\(key.artist) - \(key.title)"
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(readableName)-\(shortHash(key.stableID)).lrc"
    }

    private func isSafeImportedFileName(_ fileName: String) -> Bool {
        return !fileName.contains("/") &&
            !fileName.contains("\\") &&
            !fileName.isEmpty &&
            fileName != "." &&
            fileName != ".." &&
            !fileName.contains("..") &&
            fileName.lowercased().hasSuffix(".lrc")
    }

    private func parsePlainLRCFileName(_ name: String) -> (artist: String, title: String)? {
        let separators = [" - ", "-", "–", "—"]
        for separator in separators {
            let parts = name.components(separatedBy: separator)
            if parts.count >= 2 {
                let artist = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let title = parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
                if !artist.isEmpty && !title.isEmpty {
                    return (artist, title)
                }
            }
        }
        return nil
    }

    private func shortHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private struct LyricsCacheManifest: Codable, Sendable {
    var version: Int
    var entries: [LyricsCacheEntry]
}

private struct LyricsCacheEntry: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Int
    var fileName: String
    var source: String
    var savedAt: Date

    func copy(fileName: String, savedAt: Date) -> LyricsCacheEntry {
        LyricsCacheEntry(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            fileName: fileName,
            source: source,
            savedAt: savedAt
        )
    }
}

import AppKit
import ScreenLyricsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var overlayController: OverlayWindowController?
    private var refreshTimer: Timer?
    private let lyricsCache = LyricsCacheStore()
    private lazy var coordinator = LyricsCoordinator(
        spotifyReader: SpotifyAppleScriptClient(),
        lyricsFetcher: LRCLIBClient(),
        lyricsCache: lyricsCache
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlayController = OverlayWindowController()
        overlayController?.showWindow(nil)
        configureMenu()
        startPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    private func configureMenu() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Lyrics"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Lyrics", action: #selector(showLyrics), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide Lyrics", action: #selector(hideLyrics), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Reload Lyrics", action: #selector(reloadLyrics), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Import Lyrics Folder...", action: #selector(importLyricsFolder), keyEquivalent: "i"))
        menu.addItem(NSMenuItem(title: "Export Lyrics Folder...", action: #selector(exportLyricsFolder), keyEquivalent: "e"))
        menu.addItem(NSMenuItem(title: "Open Lyrics Cache Folder", action: #selector(openLyricsCacheFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit ScreenLyrics", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 0.8,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
        refresh()
    }

    @objc private func timerFired() {
        refresh()
    }

    private func refresh() {
        let coordinator = coordinator
        Task {
            let status = await coordinator.refresh()
            await MainActor.run {
                self.overlayController?.render(status)
            }
        }
    }

    @objc private func showLyrics() {
        overlayController?.showWindow(nil)
    }

    @objc private func hideLyrics() {
        overlayController?.window?.orderOut(nil)
    }

    @objc private func reloadLyrics() {
        let coordinator = coordinator
        Task {
            await coordinator.reload()
            await MainActor.run {
                self.refresh()
            }
        }
    }

    @objc private func importLyricsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose a ScreenLyrics export folder or a folder containing Artist - Title.lrc files."

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return
        }

        let coordinator = coordinator
        Task {
            do {
                let result = try await coordinator.importLyrics(from: folderURL)
                await MainActor.run {
                    self.showImportExportAlert(
                        title: "Lyrics Imported",
                        message: "\(result.imported) imported, \(result.skipped) skipped, \(result.failed) failed."
                    )
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.showImportExportAlert(title: "Import Failed", message: error.localizedDescription)
                }
            }
        }
    }

    @objc private func exportLyricsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose a folder where ScreenLyrics should export manifest.json and lyrics/*.lrc."

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return
        }

        let coordinator = coordinator
        Task {
            do {
                let result = try await coordinator.exportLyrics(to: folderURL)
                await MainActor.run {
                    self.showImportExportAlert(
                        title: "Lyrics Exported",
                        message: "\(result.imported) exported, \(result.failed) failed."
                    )
                }
            } catch {
                await MainActor.run {
                    self.showImportExportAlert(title: "Export Failed", message: error.localizedDescription)
                }
            }
        }
    }

    @objc private func openLyricsCacheFolder() {
        let url = lyricsCache.cacheDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func showImportExportAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

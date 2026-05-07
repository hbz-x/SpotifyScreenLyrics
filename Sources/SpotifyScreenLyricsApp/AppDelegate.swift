import AppKit
import SpotifyScreenLyricsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let adaptiveContrastMenuTitle = "Adaptive Lyric Contrast"
    private static let adaptiveContrastPermissionMenuTitle = "Adaptive Lyric Contrast (needs Screen Recording)"

    private var statusItem: NSStatusItem?
    private var overlayController: OverlayWindowController?
    private var adaptiveContrastSampler: AdaptiveContrastSampler?
    private var refreshTimer: Timer?
    private var backgroundOpacityItems: [NSMenuItem] = []
    private var adaptiveContrastItem: NSMenuItem?
    private let lyricsCache = LyricsCacheStore()
    private lazy var coordinator = LyricsCoordinator(
        spotifyReader: SpotifyAppleScriptClient(),
        lyricsFetcher: LRCLIBClient(),
        lyricsCache: lyricsCache
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlayController = OverlayWindowController()
        overlayController?.showWindow(nil)
        configureAdaptiveContrastSampler()
        configureMenu()
        updateAdaptiveContrast(requestPermission: false)
        startPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        adaptiveContrastSampler?.stop()
    }

    private func configureMenu() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Lyrics"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Lyrics", action: #selector(showLyrics), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide Lyrics", action: #selector(hideLyrics), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(backgroundOpacityMenuItem())
        let adaptiveContrastItem = NSMenuItem(
            title: Self.adaptiveContrastMenuTitle,
            action: #selector(toggleAdaptiveLyricContrast(_:)),
            keyEquivalent: ""
        )
        adaptiveContrastItem.target = self
        menu.addItem(adaptiveContrastItem)
        self.adaptiveContrastItem = adaptiveContrastItem
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Reload Lyrics", action: #selector(reloadLyrics), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Import Lyrics Folder...", action: #selector(importLyricsFolder), keyEquivalent: "i"))
        menu.addItem(NSMenuItem(title: "Export Lyrics Folder...", action: #selector(exportLyricsFolder), keyEquivalent: "e"))
        menu.addItem(NSMenuItem(title: "Open Lyrics Cache Folder", action: #selector(openLyricsCacheFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit SpotifyScreenLyrics", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        statusItem.menu = menu
        self.statusItem = statusItem
        updateBackgroundOpacityMenuState()
        updateAdaptiveContrastMenuState()
    }

    private func backgroundOpacityMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Background Opacity", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        backgroundOpacityItems = [
            opacityMenuItem(title: "Transparent", value: 0),
            opacityMenuItem(title: "25%", value: 0.25),
            opacityMenuItem(title: "50%", value: 0.5),
            opacityMenuItem(title: "75%", value: 0.75),
            opacityMenuItem(title: "100%", value: 1)
        ]
        backgroundOpacityItems.forEach { submenu.addItem($0) }
        item.submenu = submenu
        return item
    }

    private func opacityMenuItem(title: String, value: Double) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(setBackgroundOpacity(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = value
        return item
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

    private func configureAdaptiveContrastSampler() {
        let sampler = AdaptiveContrastSampler(
            backgroundOpacity: AppSettings.backgroundOpacity,
            sampleRectProvider: { [weak self] in
                self?.overlayController?.overlaySampleRectInScreen()
            }
        )
        sampler.onStyleChanged = { [weak self] style in
            self?.overlayController?.setContrastStyle(style)
        }
        sampler.onScreenCaptureAccessChanged = { [weak self] hasAccess in
            self?.updateAdaptiveContrastMenuState(hasScreenCaptureAccess: hasAccess)
        }
        adaptiveContrastSampler = sampler
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

    @objc private func setBackgroundOpacity(_ sender: NSMenuItem) {
        guard let opacity = sender.representedObject as? Double else {
            return
        }
        AppSettings.backgroundOpacity = opacity
        overlayController?.setBackgroundOpacity(opacity)
        adaptiveContrastSampler?.backgroundOpacity = opacity
        updateBackgroundOpacityMenuState()
    }

    private func updateBackgroundOpacityMenuState() {
        let currentOpacity = AppSettings.backgroundOpacity
        for item in backgroundOpacityItems {
            let itemOpacity = item.representedObject as? Double
            item.state = itemOpacity == currentOpacity ? .on : .off
        }
    }

    @objc private func toggleAdaptiveLyricContrast(_ sender: NSMenuItem) {
        AppSettings.adaptiveLyricContrastEnabled.toggle()
        updateAdaptiveContrast(requestPermission: AppSettings.adaptiveLyricContrastEnabled)
    }

    private func updateAdaptiveContrast(requestPermission: Bool) {
        if AppSettings.adaptiveLyricContrastEnabled {
            adaptiveContrastSampler?.start(requestPermission: requestPermission)
        } else {
            adaptiveContrastSampler?.stop()
        }
        updateAdaptiveContrastMenuState()
    }

    private func updateAdaptiveContrastMenuState(hasScreenCaptureAccess: Bool? = nil) {
        adaptiveContrastItem?.state = AppSettings.adaptiveLyricContrastEnabled ? .on : .off
        if AppSettings.adaptiveLyricContrastEnabled, hasScreenCaptureAccess == false {
            adaptiveContrastItem?.title = Self.adaptiveContrastPermissionMenuTitle
        } else {
            adaptiveContrastItem?.title = Self.adaptiveContrastMenuTitle
        }
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
        panel.message = "Choose a SpotifyScreenLyrics export folder or a folder containing Artist - Title.lrc files."

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
        panel.message = "Choose a folder where SpotifyScreenLyrics should export manifest.json and lyrics/*.lrc."

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

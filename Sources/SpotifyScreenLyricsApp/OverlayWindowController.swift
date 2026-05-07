import AppKit
import SpotifyScreenLyricsCore

final class OverlayWindowController: NSWindowController {
    private let overlayView = LyricsOverlayView()

    init() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let width: CGFloat = min(900, screenFrame.width - LyricsOverlayView.screenHorizontalPadding * 2)
        let height: CGFloat = 150
        let origin = NSPoint(
            x: screenFrame.midX - width / 2,
            y: screenFrame.minY + 90
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = overlayView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        super.init(window: panel)
        render(.waitingForSpotify)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(_ status: LyricsStatus) {
        overlayView.render(status)
        resizeForCurrentLyrics()
    }

    func setBackgroundOpacity(_ opacity: Double) {
        overlayView.setBackgroundOpacity(opacity)
    }

    func setContrastStyle(_ style: LyricsOverlayView.ContrastStyle) {
        overlayView.setContrastStyle(style)
    }

    func overlaySampleRectInScreen() -> CGRect? {
        guard let window else {
            return nil
        }
        let rectInWindow = overlayView.containerFrameInWindow()
        return window.convertToScreen(rectInWindow)
    }

    private func resizeForCurrentLyrics() {
        guard let window else {
            return
        }

        let screenFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let preferredSize = overlayView.preferredWindowSize(in: screenFrame)
        let currentFrame = window.frame
        guard abs(currentFrame.width - preferredSize.width) >= 1
            || abs(currentFrame.height - preferredSize.height) >= 1 else {
            return
        }

        let minimumX = screenFrame.minX + LyricsOverlayView.screenHorizontalPadding
        let maximumX = screenFrame.maxX - LyricsOverlayView.screenHorizontalPadding - preferredSize.width
        let centeredX = currentFrame.midX - preferredSize.width / 2
        let clampedX = min(max(centeredX, minimumX), max(minimumX, maximumX))
        let frame = NSRect(
            x: clampedX,
            y: currentFrame.minY,
            width: preferredSize.width,
            height: preferredSize.height
        )

        window.setFrame(frame, display: true, animate: false)
    }
}

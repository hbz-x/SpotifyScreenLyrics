import AppKit
import ScreenLyricsCore

final class OverlayWindowController: NSWindowController {
    private let overlayView = LyricsOverlayView()

    init() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let width: CGFloat = min(900, screenFrame.width - 80)
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
    }

    func setBackgroundOpacity(_ opacity: Double) {
        overlayView.setBackgroundOpacity(opacity)
    }
}

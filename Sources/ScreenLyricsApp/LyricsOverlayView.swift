import AppKit
import ScreenLyricsCore

final class LyricsOverlayView: NSView {
    private let container = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let currentLineLabel = NSTextField(labelWithString: "")
    private let nextLineLabel = NSTextField(labelWithString: "")
    private let statusDot = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool {
        true
    }

    func render(_ status: LyricsStatus) {
        switch status {
        case .waitingForSpotify:
            titleLabel.stringValue = "Spotify"
            currentLineLabel.stringValue = "Waiting for Spotify to play"
            nextLineLabel.stringValue = ""
            setDotColor(.systemGray)
        case .loading(let trackTitle, let artist):
            titleLabel.stringValue = "\(trackTitle) - \(artist)"
            currentLineLabel.stringValue = "Loading synced lyrics"
            nextLineLabel.stringValue = ""
            setDotColor(.systemYellow)
        case .ready(let trackTitle, let artist, let lyrics, let isPlaying):
            titleLabel.stringValue = "\(trackTitle) - \(artist)"
            currentLineLabel.stringValue = lyrics.currentLine
            nextLineLabel.stringValue = lyrics.nextLine ?? ""
            setDotColor(isPlaying ? .systemGreen : .systemOrange)
        case .noSyncedLyrics(let trackTitle, let artist):
            titleLabel.stringValue = "\(trackTitle) - \(artist)"
            currentLineLabel.stringValue = "No synced lyrics found"
            nextLineLabel.stringValue = ""
            setDotColor(.systemGray)
        case .retryingInBackground(let trackTitle, let artist, let message):
            titleLabel.stringValue = "\(trackTitle) - \(artist)"
            currentLineLabel.stringValue = message
            nextLineLabel.stringValue = ""
            setDotColor(.systemYellow)
        case .error(let message):
            titleLabel.stringValue = "ScreenLyrics"
            currentLineLabel.stringValue = message
            nextLineLabel.stringValue = ""
            setDotColor(.systemRed)
        }
    }

    private func setupViews() {
        container.translatesAutoresizingMaskIntoConstraints = false
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        addSubview(container)

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentView)

        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        contentView.addSubview(statusDot)

        configure(label: titleLabel, font: .systemFont(ofSize: 13, weight: .medium), color: .secondaryLabelColor)
        configure(label: currentLineLabel, font: .systemFont(ofSize: 30, weight: .semibold), color: .labelColor)
        configure(label: nextLineLabel, font: .systemFont(ofSize: 18, weight: .regular), color: .tertiaryLabelColor)

        titleLabel.maximumNumberOfLines = 1
        currentLineLabel.maximumNumberOfLines = 2
        nextLineLabel.maximumNumberOfLines = 1

        contentView.addSubview(titleLabel)
        contentView.addSubview(currentLineLabel)
        contentView.addSubview(nextLineLabel)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            container.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            contentView.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),

            statusDot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusDot.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),

            titleLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor),

            currentLineLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            currentLineLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            currentLineLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),

            nextLineLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            nextLineLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            nextLineLabel.topAnchor.constraint(equalTo: currentLineLabel.bottomAnchor, constant: 6),
            nextLineLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])

        setDotColor(.systemGray)
    }

    private func configure(label: NSTextField, font: NSFont, color: NSColor) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = font
        label.textColor = color
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.allowsDefaultTighteningForTruncation = true
    }

    private func setDotColor(_ color: NSColor) {
        statusDot.layer?.backgroundColor = color.cgColor
    }
}

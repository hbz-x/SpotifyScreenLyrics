import AppKit
import SpotifyScreenLyricsCore

final class LyricsOverlayView: NSView {
    enum ContrastStyle: Equatable {
        case system
        case lightText
        case darkText
    }

    static let screenHorizontalPadding: CGFloat = 40

    private enum Metrics {
        static let baseMaximumWindowWidth: CGFloat = 900
        static let minimumWindowHeight: CGFloat = 150
        static let containerHorizontalInset: CGFloat = 16
        static let containerVerticalInset: CGFloat = 12
        static let contentHorizontalInset: CGFloat = 22
        static let contentVerticalInset: CGFloat = 16
        static let titleToCurrentSpacing: CGFloat = 10
        static let currentToNextSpacing: CGFloat = 6
        static let currentLineLimit = 2

        static var windowToTextHorizontalInset: CGFloat {
            (containerHorizontalInset + contentHorizontalInset) * 2
        }

        static var windowToTextVerticalInset: CGFloat {
            (containerVerticalInset + contentVerticalInset) * 2
        }
    }

    private let container = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let currentLineLabel = NSTextField(labelWithString: "")
    private let nextLineLabel = NSTextField(labelWithString: "")
    private let statusDot = NSView()
    private var contrastStyle: ContrastStyle = .system

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupViews()
        setBackgroundOpacity(AppSettings.backgroundOpacity)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        currentLineLabel.preferredMaxLayoutWidth = max(1, currentLineLabel.bounds.width)
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
            titleLabel.stringValue = "SpotifyScreenLyrics"
            currentLineLabel.stringValue = message
            nextLineLabel.stringValue = ""
            setDotColor(.systemRed)
        }
        [titleLabel, currentLineLabel, nextLineLabel].forEach { $0.invalidateIntrinsicContentSize() }
    }

    func setBackgroundOpacity(_ opacity: Double) {
        let clampedOpacity = min(max(opacity, 0), 1)
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(clampedOpacity).cgColor
        container.layer?.borderColor = NSColor.white.withAlphaComponent(clampedOpacity > 0 ? 0.12 : 0).cgColor
        container.layer?.borderWidth = clampedOpacity > 0 ? 1 : 0
    }

    func setContrastStyle(_ style: ContrastStyle) {
        guard contrastStyle != style else {
            return
        }
        contrastStyle = style
        applyContrastStyle()
    }

    func containerFrameInWindow() -> NSRect {
        convert(container.frame, to: nil)
    }

    func preferredWindowSize(in screenFrame: NSRect) -> NSSize {
        let maximumWidth = max(1, screenFrame.width - Self.screenHorizontalPadding * 2)
        let baseWidth = min(Metrics.baseMaximumWindowWidth, maximumWidth)
        let currentLineWidth = singleLineTextWidth(for: currentLineLabel)
        let targetWidth = min(max(baseWidth, currentLineWidth + Metrics.windowToTextHorizontalInset), maximumWidth)
        let contentWidth = max(1, targetWidth - Metrics.windowToTextHorizontalInset)
        let targetHeight = max(Metrics.minimumWindowHeight, preferredWindowHeight(forContentWidth: contentWidth))

        currentLineLabel.preferredMaxLayoutWidth = contentWidth
        return NSSize(width: ceil(targetWidth), height: ceil(targetHeight))
    }

    private func setupViews() {
        container.translatesAutoresizingMaskIntoConstraints = false
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
        currentLineLabel.lineBreakMode = .byWordWrapping
        currentLineLabel.usesSingleLineMode = false
        currentLineLabel.cell?.usesSingleLineMode = false
        currentLineLabel.cell?.wraps = true
        currentLineLabel.cell?.isScrollable = false
        currentLineLabel.cell?.truncatesLastVisibleLine = true

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
        applyContrastStyle()
    }

    private func configure(label: NSTextField, font: NSFont, color: NSColor) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = font
        label.textColor = color
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.allowsDefaultTighteningForTruncation = true
        label.usesSingleLineMode = true
        label.cell?.usesSingleLineMode = true
        label.cell?.truncatesLastVisibleLine = true
    }

    private func preferredWindowHeight(forContentWidth contentWidth: CGFloat) -> CGFloat {
        let titleHeight = singleLineHeight(for: titleLabel)
        let currentLineHeight = wrappedCurrentLineHeight(forContentWidth: contentWidth)
        let nextLineHeight = nextLineLabel.stringValue.isEmpty ? 0 : singleLineHeight(for: nextLineLabel)
        let contentHeight = titleHeight
            + Metrics.titleToCurrentSpacing
            + currentLineHeight
            + Metrics.currentToNextSpacing
            + nextLineHeight
        return contentHeight + Metrics.windowToTextVerticalInset
    }

    private func singleLineTextWidth(for label: NSTextField) -> CGFloat {
        let text = label.stringValue.replacingOccurrences(of: "\n", with: " ")
        guard !text.isEmpty else {
            return 0
        }
        return ceil((text as NSString).size(withAttributes: [.font: font(for: label)]).width)
    }

    private func singleLineHeight(for label: NSTextField) -> CGFloat {
        lineHeight(for: font(for: label))
    }

    private func wrappedCurrentLineHeight(forContentWidth contentWidth: CGFloat) -> CGFloat {
        let font = font(for: currentLineLabel)
        let lineHeight = lineHeight(for: font)
        let text = currentLineLabel.stringValue
        guard !text.isEmpty else {
            return lineHeight
        }

        let attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle(for: currentLineLabel.lineBreakMode)
            ]
        )
        let boundingRect = attributedText.boundingRect(
            with: NSSize(width: max(1, contentWidth), height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let maximumHeight = lineHeight * CGFloat(Metrics.currentLineLimit)
        return min(max(lineHeight, ceil(boundingRect.height)), maximumHeight)
    }

    private func font(for label: NSTextField) -> NSFont {
        label.font ?? .systemFont(ofSize: NSFont.systemFontSize)
    }

    private func lineHeight(for font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    private func paragraphStyle(for lineBreakMode: NSLineBreakMode) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = lineBreakMode
        return style
    }

    private func setDotColor(_ color: NSColor) {
        statusDot.layer?.backgroundColor = color.cgColor
    }

    private func applyContrastStyle() {
        switch contrastStyle {
        case .system:
            titleLabel.textColor = NSColor.white.withAlphaComponent(0.72)
            currentLineLabel.textColor = .white
            nextLineLabel.textColor = NSColor.white.withAlphaComponent(0.55)
            applyTextShadow(color: .black, alpha: 0.85, blurRadius: 3, offset: NSSize(width: 0, height: -1))
        case .lightText:
            titleLabel.textColor = NSColor.white.withAlphaComponent(0.72)
            currentLineLabel.textColor = .white
            nextLineLabel.textColor = NSColor.white.withAlphaComponent(0.55)
            applyTextShadow(color: .black, alpha: 0.85, blurRadius: 3, offset: NSSize(width: 0, height: -1))
        case .darkText:
            titleLabel.textColor = NSColor.black.withAlphaComponent(0.66)
            currentLineLabel.textColor = .black
            nextLineLabel.textColor = NSColor.black.withAlphaComponent(0.48)
            applyTextShadow(color: .white, alpha: 0.8, blurRadius: 2, offset: NSSize(width: 0, height: -1))
        }
    }

    private func applyTextShadow(color: NSColor, alpha: CGFloat, blurRadius: CGFloat, offset: NSSize) {
        let shadow = NSShadow()
        shadow.shadowColor = color.withAlphaComponent(alpha)
        shadow.shadowBlurRadius = blurRadius
        shadow.shadowOffset = offset
        [titleLabel, currentLineLabel, nextLineLabel].forEach { $0.shadow = shadow }
    }
}

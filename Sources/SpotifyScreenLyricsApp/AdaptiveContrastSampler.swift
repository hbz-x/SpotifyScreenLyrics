import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

@MainActor
final class AdaptiveContrastSampler {
    var backgroundOpacity: Double {
        get {
            clampedBackgroundOpacity
        }
        set {
            clampedBackgroundOpacity = min(max(newValue, 0), 1)
        }
    }

    var onStyleChanged: ((LyricsOverlayView.ContrastStyle) -> Void)?
    var onScreenCaptureAccessChanged: ((Bool) -> Void)?

    private let sampleRectProvider: () -> CGRect?
    private var clampedBackgroundOpacity: Double
    private var timer: Timer?
    private var isSampling = false
    private var samplingGeneration = 0
    private var lastStyle: LyricsOverlayView.ContrastStyle = .system

    init(backgroundOpacity: Double, sampleRectProvider: @escaping () -> CGRect?) {
        self.clampedBackgroundOpacity = min(max(backgroundOpacity, 0), 1)
        self.sampleRectProvider = sampleRectProvider
    }

    func start(requestPermission: Bool) {
        guard timer == nil else {
            if requestPermission {
                requestScreenCaptureAccessIfNeeded()
            }
            return
        }

        if requestPermission {
            requestScreenCaptureAccessIfNeeded()
        }

        samplingGeneration += 1
        timer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
        sample()
    }

    func stop() {
        samplingGeneration += 1
        timer?.invalidate()
        timer = nil
        isSampling = false
        apply(style: .system)
    }

    @objc private func timerFired() {
        sample()
    }

    private func sample() {
        guard !isSampling else {
            return
        }
        guard CGPreflightScreenCaptureAccess(), let sampleRect = sampleRectProvider(), !sampleRect.isEmpty else {
            onScreenCaptureAccessChanged?(false)
            apply(style: .system)
            return
        }
        onScreenCaptureAccessChanged?(true)

        isSampling = true
        let generation = samplingGeneration
        Task {
            defer {
                Task { @MainActor in
                    guard self.samplingGeneration == generation else {
                        return
                    }
                    self.isSampling = false
                }
            }

            do {
                let content = try await SCShareableContent.current
                guard let display = bestDisplay(for: sampleRect, displays: content.displays) else {
                    await applyOnMain(style: .system, generation: generation)
                    return
                }

                let excludedApplications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(
                    display: display,
                    excludingApplications: excludedApplications,
                    exceptingWindows: []
                )
                if #available(macOS 14.2, *) {
                    filter.includeMenuBar = true
                }

                let rect = sampleRect.intersection(display.frame)
                guard !rect.isEmpty else {
                    await applyOnMain(style: .system, generation: generation)
                    return
                }

                let config = SCStreamConfiguration()
                config.sourceRect = rect
                config.width = 96
                config.height = min(96, max(24, Int(round(rect.height / max(rect.width, 1) * 96))))
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false
                config.capturesAudio = false

                let image = try await Self.captureImage(contentFilter: filter, configuration: config)
                guard let luminance = Self.averageLuminance(from: image) else {
                    await applyOnMain(style: .system, generation: generation)
                    return
                }

                await applyOnMain(style: luminance >= 0.56 ? .darkText : .lightText, generation: generation)
            } catch {
                await applyOnMain(style: .system, generation: generation)
            }
        }
    }

    private func requestScreenCaptureAccessIfNeeded() {
        guard !CGPreflightScreenCaptureAccess() else {
            onScreenCaptureAccessChanged?(true)
            return
        }
        _ = CGRequestScreenCaptureAccess()
        onScreenCaptureAccessChanged?(CGPreflightScreenCaptureAccess())
    }

    private func applyOnMain(style: LyricsOverlayView.ContrastStyle, generation: Int) async {
        await MainActor.run {
            guard samplingGeneration == generation else {
                return
            }
            apply(style: style)
        }
    }

    private func apply(style: LyricsOverlayView.ContrastStyle) {
        guard lastStyle != style else {
            return
        }
        lastStyle = style
        onStyleChanged?(style)
    }

    nonisolated private static func captureImage(
        contentFilter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? AdaptiveContrastSamplerError.captureFailed)
                }
            }
        }
    }

    nonisolated private static func averageLuminance(from image: CGImage) -> Double? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var luminanceSum = 0.0
        var sampleCount = 0
        let pixelStride = max(1, min(width, height) / 24)

        for y in stride(from: 0, to: height, by: pixelStride) {
            for x in stride(from: 0, to: width, by: pixelStride) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let blue = Double(pixels[offset]) / 255
                let green = Double(pixels[offset + 1]) / 255
                let red = Double(pixels[offset + 2]) / 255
                luminanceSum += 0.2126 * red + 0.7152 * green + 0.0722 * blue
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return nil
        }
        return luminanceSum / Double(sampleCount)
    }

    nonisolated private func bestDisplay(for rect: CGRect, displays: [SCDisplay]) -> SCDisplay? {
        displays.max { first, second in
            first.frame.intersection(rect).area < second.frame.intersection(rect).area
        }
    }
}

private enum AdaptiveContrastSamplerError: Error {
    case captureFailed
}

private extension CGRect {
    var area: CGFloat {
        guard !isEmpty else {
            return 0
        }
        return width * height
    }
}

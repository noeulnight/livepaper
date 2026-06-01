import AppKit
import CoreImage
import Foundation
import QuartzCore

@MainActor
final class MusicWallpaperView: NSView {
    private static let backgroundSpinAnimationKey = "livepaper.music.backgroundSpin"
    private static let backgroundSpinDuration: CFTimeInterval = 160
    private static let artworkTransitionDuration: TimeInterval = 0.85
    private static let progressClockInterval: Duration = .milliseconds(250)
    private static let backgroundBlurRadius: CGFloat = 42
    private static let backgroundImageContext = CIContext(options: [.cacheIntermediates: false])

    var style: MusicWallpaperStyle {
        didSet {
            applyStyle(animated: true)
            updateBackgroundSpin(isActive: currentArtwork != nil)
        }
    }

    private let backgroundArtworkView = MusicBackgroundArtworkView()
    private let gradientView = NSView()
    private let scrimView = NSView()
    private let coverContainerView = NSView()
    private let coverImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressTrackView = NSView()
    private let progressFillView = NSView()
    private let elapsedTimeLabel = NSTextField(labelWithString: "")
    private let durationTimeLabel = NSTextField(labelWithString: "")
    private let gradientLayer = CAGradientLayer()
    private let vignetteLayer = CAGradientLayer()

    private var currentArtwork: NSImage?
    private var currentProgressFraction: CGFloat?
    private var currentElapsedTimeText = ""
    private var currentDurationTimeText = ""
    private var progressClockTask: Task<Void, Never>?
    private var progressBasePosition: TimeInterval?
    private var progressDuration: TimeInterval?
    private var progressUpdatedAt: Date?
    private var isBackgroundSpinPaused = false
    private var artworkTransitionID = 0

    init(frame frameRect: NSRect, style: MusicWallpaperStyle) {
        self.style = style
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        self.style = .ambient
        super.init(coder: coder)
        configure()
    }

    deinit {
        progressClockTask?.cancel()
    }

    override func layout() {
        super.layout()

        layoutBackgroundArtworkView(backgroundArtworkView)
        subviews
            .compactMap { $0 as? MusicBackgroundArtworkTransitionView }
            .forEach(layoutBackgroundArtworkView)
        gradientView.frame = bounds
        scrimView.frame = bounds
        gradientLayer.frame = gradientView.bounds
        vignetteLayer.frame = gradientView.bounds

        layoutContent()
    }

    func showPlaceholder(title: String, subtitle: String) {
        currentArtwork = nil
        setImages(nil, animated: true)
        titleLabel.stringValue = title
        detailLabel.stringValue = subtitle
        statusLabel.stringValue = ""
        clearProgress()
        applyStyle(animated: true)
        needsLayout = true
    }

    func update(snapshot: NowPlayingAlbumSnapshot, artwork: NSImage?) {
        currentArtwork = artwork
        setImages(artwork, animated: true)
        updateText(snapshot: snapshot)
        applyStyle(animated: true)
    }

    func updateText(snapshot: NowPlayingAlbumSnapshot) {
        titleLabel.stringValue = snapshot.trackTitle
        if let albumTitle = snapshot.albumTitle.nilIfBlank {
            detailLabel.stringValue = "\(snapshot.artistName) - \(albumTitle)"
        } else {
            detailLabel.stringValue = snapshot.artistName
        }
        updateProgress(snapshot: snapshot)
        switch snapshot.playbackState {
        case .playing:
            statusLabel.stringValue = ""
        case .paused:
            statusLabel.stringValue = ""
        case .stopped:
            statusLabel.stringValue = "Stopped"
        case .unavailable:
            statusLabel.stringValue = "Waiting for playback"
        }
    }

    func pauseBackgroundSpin() {
        isBackgroundSpinPaused = true
        updateBackgroundSpin(isActive: false)
    }

    func resumeBackgroundSpin() {
        isBackgroundSpinPaused = false
        updateBackgroundSpin(isActive: currentArtwork != nil)
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        addSubview(backgroundArtworkView)

        gradientView.wantsLayer = true
        gradientView.layer?.addSublayer(gradientLayer)
        gradientView.layer?.addSublayer(vignetteLayer)
        addSubview(gradientView)

        scrimView.wantsLayer = true
        addSubview(scrimView)

        coverContainerView.wantsLayer = true
        coverContainerView.layer?.shadowColor = NSColor.black.cgColor
        coverContainerView.layer?.shadowOffset = CGSize(width: 0, height: -18)
        coverContainerView.layer?.shadowRadius = 34
        coverContainerView.layer?.shadowOpacity = 0.34
        addSubview(coverContainerView)

        coverImageView.imageScaling = .scaleProportionallyUpOrDown
        coverImageView.wantsLayer = true
        coverImageView.layer?.cornerRadius = 22
        coverImageView.layer?.masksToBounds = true
        coverImageView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        coverContainerView.addSubview(coverImageView)

        configureLabel(titleLabel, font: .systemFont(ofSize: 30, weight: .bold), alpha: 0.94)
        configureLabel(detailLabel, font: .systemFont(ofSize: 18, weight: .semibold), alpha: 0.76)
        configureLabel(statusLabel, font: .systemFont(ofSize: 14, weight: .medium), alpha: 0.56)
        configureLabel(elapsedTimeLabel, font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium), alpha: 0.58)
        configureLabel(durationTimeLabel, font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium), alpha: 0.58)
        elapsedTimeLabel.alignment = .left
        durationTimeLabel.alignment = .right
        configureProgressBar()
        applyStyle(animated: false)
    }

    private func configureLabel(_ label: NSTextField, font: NSFont, alpha: CGFloat) {
        label.font = font
        label.textColor = NSColor.white.withAlphaComponent(alpha)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.shadow = textShadow
        addSubview(label)
    }

    private func configureProgressBar() {
        progressTrackView.wantsLayer = true
        progressTrackView.layer?.cornerRadius = 2
        progressTrackView.layer?.masksToBounds = true
        progressTrackView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        addSubview(progressTrackView)

        progressFillView.wantsLayer = true
        progressFillView.layer?.cornerRadius = 2
        progressFillView.layer?.masksToBounds = true
        progressFillView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.76).cgColor
        progressTrackView.addSubview(progressFillView)
    }

    private var textShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.62)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = CGSize(width: 0, height: -2)
        return shadow
    }

    private func setImages(_ image: NSImage?, animated: Bool) {
        artworkTransitionID += 1
        let transitionID = artworkTransitionID
        removeArtworkFadeAnimations()
        removeArtworkTransitionViews()
        let backgroundImage = image.flatMap(blurredBackgroundImage) ?? image
        let finalBackgroundAlpha = backgroundAlpha
        let finalCoverAlpha = coverAlpha
        let fadeOutDuration = Self.artworkTransitionDuration * 0.58
        let fadeInDuration = Self.artworkTransitionDuration * 0.42
        let crossfadeDuration = Self.artworkTransitionDuration
        let updates = {
            self.backgroundArtworkView.image = backgroundImage
            self.coverImageView.image = image
            self.coverImageView.alphaValue = 1
            self.coverContainerView.alphaValue = image == nil && self.style != .minimal ? 0.18 : 1
            self.updateBackgroundSpin(isActive: image != nil)
        }

        guard animated else {
            updates()
            return
        }

        guard let image else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fadeOutDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.backgroundArtworkView.animator().alphaValue = 0
                self.coverContainerView.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    guard transitionID == self.artworkTransitionID else {
                        return
                    }

                    updates()
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = fadeInDuration
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        self.backgroundArtworkView.animator().alphaValue = finalBackgroundAlpha
                        self.coverContainerView.animator().alphaValue = finalCoverAlpha
                    }
                }
            }
            return
        }

        let spinAngle = currentBackgroundSpinAngle()
        let backgroundOverlay = backgroundArtworkView.image.map { previousImage in
            let overlay = MusicBackgroundArtworkTransitionView(frame: .zero)
            overlay.image = previousImage
            layoutBackgroundArtworkView(overlay)
            overlay.alphaValue = finalBackgroundAlpha
            addSubview(overlay, positioned: .above, relativeTo: backgroundArtworkView)
            updateBackgroundSpin(
                isActive: !isBackgroundSpinPaused,
                on: overlay,
                startingAngle: spinAngle
            )
            return overlay
        }

        let coverOverlay = transitionImageView(image: image)
        coverOverlay.frame = coverImageView.frame
        coverOverlay.layer?.cornerRadius = coverImageView.layer?.cornerRadius ?? 0
        coverOverlay.alphaValue = 0
        coverContainerView.addSubview(coverOverlay)

        backgroundArtworkView.image = backgroundImage
        backgroundArtworkView.alphaValue = finalBackgroundAlpha
        updateBackgroundSpin(isActive: true)
        coverImageView.alphaValue = 1
        coverContainerView.alphaValue = finalCoverAlpha
        NSAnimationContext.runAnimationGroup { context in
            context.duration = crossfadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            backgroundOverlay?.animator().alphaValue = 0
            self.coverImageView.animator().alphaValue = 0
            coverOverlay.animator().alphaValue = 1
        } completionHandler: {
            MainActor.assumeIsolated {
                guard transitionID == self.artworkTransitionID else {
                    backgroundOverlay?.removeFromSuperview()
                    coverOverlay.removeFromSuperview()
                    return
                }

                self.coverImageView.image = image
                self.coverContainerView.alphaValue = 1
                self.backgroundArtworkView.alphaValue = finalBackgroundAlpha
                self.coverImageView.alphaValue = 1
                self.coverContainerView.alphaValue = finalCoverAlpha
                backgroundOverlay?.removeFromSuperview()
                coverOverlay.removeFromSuperview()
            }
        }
    }

    private func blurredBackgroundImage(from image: NSImage) -> NSImage? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let displayedLength = max(backgroundArtworkView.bounds.width, backgroundArtworkView.bounds.height, 1)
        let renderLength = min(max(displayedLength, 512), 1536)
        guard let tiledImage = Self.tiledBackgroundImage(from: cgImage, length: renderLength) else {
            return nil
        }

        let source = CIImage(cgImage: tiledImage)
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return nil
        }

        let renderScale = renderLength / displayedLength
        blurFilter.setValue(source.clampedToExtent(), forKey: kCIInputImageKey)
        blurFilter.setValue(max(4, Self.backgroundBlurRadius * renderScale), forKey: kCIInputRadiusKey)
        guard let blurredImage = blurFilter.outputImage?.cropped(to: source.extent),
              let renderedImage = Self.backgroundImageContext.createCGImage(blurredImage, from: source.extent) else {
            return nil
        }

        return NSImage(cgImage: renderedImage, size: NSSize(width: renderLength, height: renderLength))
    }

    private static func tiledBackgroundImage(from image: CGImage, length: CGFloat) -> CGImage? {
        let pixelLength = max(Int(length.rounded(.up)), 1)
        let tileLength = CGFloat(pixelLength) / 3
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelLength,
            height: pixelLength,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        for row in 0..<3 {
            for column in 0..<3 {
                let rect = CGRect(
                    x: CGFloat(column) * tileLength,
                    y: CGFloat(row) * tileLength,
                    width: tileLength,
                    height: tileLength
                )
                context.draw(image, in: rect)
            }
        }

        return context.makeImage()
    }

    private func removeArtworkFadeAnimations() {
        [backgroundArtworkView, coverContainerView, coverImageView].forEach {
            $0.layer?.removeAnimation(forKey: "opacity")
            $0.layer?.removeAnimation(forKey: "alphaValue")
        }
    }

    private func removeArtworkTransitionViews() {
        subviews
            .compactMap { $0 as? MusicBackgroundArtworkTransitionView }
            .forEach { $0.removeFromSuperview() }
        coverContainerView.subviews
            .compactMap { $0 as? MusicArtworkTransitionImageView }
            .forEach { $0.removeFromSuperview() }
        backgroundArtworkView.alphaValue = backgroundAlpha
        coverImageView.alphaValue = 1
    }

    private func transitionImageView(image: NSImage) -> MusicArtworkTransitionImageView {
        let imageView = MusicArtworkTransitionImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.contentsGravity = .resizeAspect
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        return imageView
    }

    private func layoutBackgroundArtworkView(_ view: NSView) {
        let spinCenter = CGPoint(
            x: bounds.minX + bounds.width * 0.16,
            y: bounds.midY + bounds.height * 0.06
        )
        let farthestCornerDistance = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.maxX, y: bounds.maxY)
        ]
            .map { hypot($0.x - spinCenter.x, $0.y - spinCenter.y) }
            .max() ?? hypot(bounds.width, bounds.height)
        let backgroundLength = farthestCornerDistance * 2 + 420
        let frame = NSRect(
            x: spinCenter.x - backgroundLength / 2,
            y: spinCenter.y - backgroundLength / 2,
            width: backgroundLength,
            height: backgroundLength
        )
        view.frame = frame
        view.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        view.layer?.position = spinCenter
    }

    private func updateBackgroundSpin(isActive: Bool) {
        updateBackgroundSpin(isActive: isActive, on: backgroundArtworkView)
    }

    private func updateBackgroundSpin(
        isActive: Bool,
        on view: NSView,
        startingAngle: Double? = nil
    ) {
        guard let layer = view.layer else {
            return
        }

        guard isActive, !isBackgroundSpinPaused, allowsBackgroundSpin else {
            layer.removeAnimation(forKey: Self.backgroundSpinAnimationKey)
            layer.transform = CATransform3DIdentity
            return
        }

        guard layer.animation(forKey: Self.backgroundSpinAnimationKey) == nil else {
            return
        }

        let angle = startingAngle ?? 0
        layer.transform = CATransform3DMakeRotation(CGFloat(angle), 0, 0, 1)
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = angle
        animation.toValue = angle + Double.pi * 2
        animation.duration = Self.backgroundSpinDuration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: Self.backgroundSpinAnimationKey)
    }

    private var allowsBackgroundSpin: Bool {
        style != .minimal
    }

    private func currentBackgroundSpinAngle() -> Double {
        guard let layer = backgroundArtworkView.layer else {
            return 0
        }

        let transform = layer.presentation()?.transform ?? layer.transform
        return Double(atan2(transform.m12, transform.m11))
    }

    private func applyStyle(animated: Bool) {
        let updates = {
            self.gradientLayer.colors = self.gradientColors
            self.gradientLayer.startPoint = CGPoint(x: 0.12, y: 0.1)
            self.gradientLayer.endPoint = CGPoint(x: 0.86, y: 0.92)
            self.vignetteLayer.colors = [
                NSColor.clear.cgColor,
                NSColor.black.withAlphaComponent(0.28).cgColor,
                NSColor.black.withAlphaComponent(0.72).cgColor
            ]
            self.vignetteLayer.locations = [0, 0.58, 1]
            self.vignetteLayer.startPoint = CGPoint(x: 0.5, y: 0.34)
            self.vignetteLayer.endPoint = CGPoint(x: 0.5, y: 1)
            self.scrimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(self.scrimAlpha).cgColor
            self.backgroundArtworkView.alphaValue = self.backgroundAlpha
            self.coverContainerView.alphaValue = self.coverAlpha
            self.titleLabel.alphaValue = self.textAlpha
            self.detailLabel.alphaValue = self.textAlpha * 0.78
            self.statusLabel.alphaValue = self.statusLabel.stringValue.isEmpty ? 0 : 0.56
            self.progressTrackView.alphaValue = self.progressVisibleAlpha
            self.elapsedTimeLabel.alphaValue = self.progressVisibleAlpha
            self.durationTimeLabel.alphaValue = self.progressVisibleAlpha
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
        }

        guard animated else {
            updates()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            updates()
        }
    }

    private var gradientColors: [CGColor] {
        [
            NSColor.black.withAlphaComponent(0.04).cgColor,
            NSColor.black.withAlphaComponent(0.12).cgColor,
            NSColor.black.withAlphaComponent(0.38).cgColor
        ]
    }

    private var backgroundAlpha: CGFloat {
        switch style {
        case .ambient:
            return 0.88
        case .focus:
            return 0.68
        case .minimal:
            return 0.68
        }
    }

    private var scrimAlpha: CGFloat {
        switch style {
        case .ambient:
            return 0.18
        case .focus:
            return 0.42
        case .minimal:
            return 0.42
        }
    }

    private var coverAlpha: CGFloat {
        switch style {
        case .ambient:
            return currentArtwork == nil ? 0.18 : 0.82
        case .focus:
            return currentArtwork == nil ? 0.22 : 1
        case .minimal:
            return currentArtwork == nil ? 0.22 : 1
        }
    }

    private var textAlpha: CGFloat {
        switch style {
        case .ambient:
            return 0.82
        case .focus:
            return 0.96
        case .minimal:
            return 0.96
        }
    }

    private var progressAlpha: CGFloat {
        0.58
    }

    private var progressVisibleAlpha: CGFloat {
        currentProgressFraction == nil ? 0 : progressAlpha
    }

    private func clearProgress() {
        stopProgressClock()
        progressBasePosition = nil
        progressDuration = nil
        progressUpdatedAt = nil
        updateProgress(fraction: nil, elapsed: nil, duration: nil)
    }

    private func updateProgress(snapshot: NowPlayingAlbumSnapshot) {
        currentProgressFraction = snapshot.progressFraction
        currentElapsedTimeText = snapshot.playbackPositionText ?? ""
        currentDurationTimeText = snapshot.playbackDurationText ?? ""
        progressBasePosition = snapshot.playbackPosition
        progressDuration = snapshot.playbackDuration
        progressUpdatedAt = Date()

        if snapshot.playbackState == .playing,
           snapshot.progressFraction != nil {
            startProgressClock()
        } else {
            stopProgressClock()
        }

        renderProgress()
    }

    private func updateProgress(fraction: CGFloat?, elapsed: String?, duration: String?) {
        currentProgressFraction = fraction
        currentElapsedTimeText = elapsed ?? ""
        currentDurationTimeText = duration ?? ""
        renderProgress()
    }

    private func renderProgress() {
        elapsedTimeLabel.stringValue = currentElapsedTimeText
        durationTimeLabel.stringValue = currentDurationTimeText

        let progress = currentProgressFraction ?? 0
        progressFillView.frame.size.width = progressTrackView.bounds.width * progress
        progressTrackView.alphaValue = progressVisibleAlpha
        elapsedTimeLabel.alphaValue = progressVisibleAlpha
        durationTimeLabel.alphaValue = progressVisibleAlpha
    }

    private func startProgressClock() {
        guard progressClockTask == nil else {
            return
        }

        progressClockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.progressClockInterval)
                guard !Task.isCancelled else {
                    return
                }
                self?.tickProgressClock()
            }
        }
    }

    private func stopProgressClock() {
        progressClockTask?.cancel()
        progressClockTask = nil
    }

    private func tickProgressClock() {
        guard let progressBasePosition,
              let progressDuration,
              progressDuration > 0,
              let progressUpdatedAt else {
            stopProgressClock()
            return
        }

        let position = min(progressBasePosition + Date().timeIntervalSince(progressUpdatedAt), progressDuration)
        currentProgressFraction = CGFloat(position / progressDuration)
        currentElapsedTimeText = NowPlayingAlbumSnapshot.formattedPlaybackTime(position) ?? ""
        currentDurationTimeText = NowPlayingAlbumSnapshot.formattedPlaybackTime(progressDuration) ?? ""
        renderProgress()

        if position >= progressDuration {
            stopProgressClock()
        }
    }

    private func layoutContent() {
        let safeBounds = bounds.insetBy(dx: 72, dy: 72)
        let minSide = max(1, min(bounds.width, bounds.height))
        let labelWidth = min(bounds.width - 96, style == .minimal ? 520 : 760)

        switch style {
        case .ambient:
            setLabelAlignment(.center)
            titleLabel.alignment = .center
            detailLabel.alignment = .center
            statusLabel.alignment = .center
            let coverLength = min(max(minSide * 0.3, 190), 360)
            positionCover(
                NSRect(
                    x: bounds.midX - coverLength / 2,
                    y: bounds.midY - coverLength / 2 + 54,
                    width: coverLength,
                    height: coverLength
                ),
                cornerRadius: 22
            )
            layoutCenteredLabels(width: labelWidth, topY: coverContainerView.frame.minY - 58)
            layoutCenteredProgress(width: min(labelWidth * 0.46, 320), topY: detailLabel.frame.minY - 24)

        case .focus:
            setLabelAlignment(.center)
            titleLabel.alignment = .center
            detailLabel.alignment = .center
            statusLabel.alignment = .center
            let coverLength = min(max(minSide * 0.39, 240), 500)
            positionCover(
                NSRect(
                    x: bounds.midX - coverLength / 2,
                    y: bounds.midY - coverLength / 2 + 68,
                    width: coverLength,
                    height: coverLength
                ),
                cornerRadius: 24
            )
            layoutCenteredLabels(width: labelWidth, topY: coverContainerView.frame.minY - 64)
            layoutCenteredProgress(width: min(labelWidth * 0.52, 360), topY: detailLabel.frame.minY - 26)

        case .minimal:
            setLabelAlignment(.left)
            titleLabel.alignment = .left
            detailLabel.alignment = .left
            statusLabel.alignment = .left
            let coverLength = min(max(minSide * 0.16, 96), 170)
            positionCover(
                NSRect(
                    x: safeBounds.minX,
                    y: safeBounds.minY,
                    width: coverLength,
                    height: coverLength
                ),
                cornerRadius: 14
            )
            let textX = coverContainerView.frame.maxX + 24
            let textWidth = max(220, min(labelWidth, safeBounds.maxX - textX))
            titleLabel.frame = NSRect(x: textX, y: safeBounds.minY + 68, width: textWidth, height: 42)
            detailLabel.frame = NSRect(x: textX, y: safeBounds.minY + 44, width: textWidth, height: 26)
            layoutProgressRow(x: textX, y: safeBounds.minY + 30, width: min(textWidth, 330))
            statusLabel.frame = NSRect(x: textX, y: safeBounds.minY + 4, width: textWidth, height: 20)
        }
        renderProgress()
    }

    private func positionCover(_ frame: NSRect, cornerRadius: CGFloat) {
        coverContainerView.frame = frame
        coverImageView.frame = coverContainerView.bounds
        coverImageView.layer?.cornerRadius = cornerRadius
        coverContainerView.subviews
            .compactMap { $0 as? MusicArtworkTransitionImageView }
            .forEach {
                $0.frame = coverContainerView.bounds
                $0.layer?.cornerRadius = cornerRadius
            }
    }

    private func layoutCenteredLabels(width: CGFloat, topY: CGFloat) {
        titleLabel.frame = NSRect(x: bounds.midX - width / 2, y: topY - 4, width: width, height: 42)
        detailLabel.frame = NSRect(x: bounds.midX - width / 2, y: titleLabel.frame.minY - 30, width: width, height: 26)
        statusLabel.frame = NSRect(x: bounds.midX - width / 2, y: detailLabel.frame.minY - 28, width: width, height: 22)
    }

    private func layoutCenteredProgress(width: CGFloat, topY: CGFloat) {
        layoutProgressRow(x: bounds.midX - width / 2, y: topY, width: width)
    }

    private func layoutProgressRow(x: CGFloat, y: CGFloat, width: CGFloat) {
        let labelY = y - 22
        progressTrackView.frame = NSRect(x: x, y: y, width: width, height: 4)
        elapsedTimeLabel.frame = NSRect(x: x, y: labelY, width: width / 2, height: 18)
        durationTimeLabel.frame = NSRect(x: x + width / 2, y: labelY, width: width / 2, height: 18)
        progressFillView.frame = NSRect(
            x: 0,
            y: 0,
            width: progressFillView.frame.width,
            height: progressTrackView.bounds.height
        )
    }

    private func setLabelAlignment(_ alignment: NSTextAlignment) {
        [titleLabel, detailLabel, statusLabel].forEach { label in
            label.alignment = alignment
            label.cell?.alignment = alignment
            label.needsDisplay = true
        }
    }
}

private class MusicBackgroundArtworkView: NSView {
    var image: NSImage? {
        didSet {
            imageView.image = image
        }
    }

    private let imageView: NSImageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.contentsGravity = .resizeAspectFill
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = NSColor.black.cgColor
        return imageView
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = false

        addSubview(imageView)
    }
}

private final class MusicBackgroundArtworkTransitionView: MusicBackgroundArtworkView {}

private final class MusicArtworkTransitionImageView: NSImageView {
}

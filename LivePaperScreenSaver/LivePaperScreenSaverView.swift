import AVFoundation
import ScreenSaver

@objc(LivePaperScreenSaverView)
final class LivePaperScreenSaverView: ScreenSaverView {
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var securityScopedURL: URL?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func startAnimation() {
        super.startAnimation()
        startPlayback()
    }

    override func stopAnimation() {
        stopPlayback()
        super.stopAnimation()
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 1 / 30
    }

    private func startPlayback() {
        stopPlayback()

        guard let config = LivePaperScreenSaverConfig.load() else {
            return
        }

        let resolvedURL = config.resolvedVideoURL
        if resolvedURL.startAccessingSecurityScopedResource() {
            securityScopedURL = resolvedURL
        }

        let item = AVPlayerItem(url: resolvedURL)
        let player = AVQueuePlayer()
        player.isMuted = true
        let looper = AVPlayerLooper(player: player, templateItem: item)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds

        self.layer?.addSublayer(layer)
        self.queuePlayer = player
        self.playerLooper = looper
        self.playerLayer = layer

        player.play()
    }

    private func stopPlayback() {
        queuePlayer?.pause()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        playerLooper = nil
        queuePlayer = nil
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }
}

private struct LivePaperScreenSaverConfig: Decodable {
    let videoURL: URL
    let bookmarkData: Data?

    var resolvedVideoURL: URL {
        guard let bookmarkData else {
            return videoURL
        }

        var isStale = false
        return (try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )) ?? videoURL
    }

    static func load() -> LivePaperScreenSaverConfig? {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let configURL = appSupportURL
            .appendingPathComponent("LivePaper")
            .appendingPathComponent("ScreenSaverConfig.json")
        guard let data = try? Data(contentsOf: configURL) else {
            return nil
        }
        return try? JSONDecoder().decode(LivePaperScreenSaverConfig.self, from: data)
    }
}

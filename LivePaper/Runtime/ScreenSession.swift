import AppKit

@MainActor
protocol VideoPlaybackGroupProviding: AnyObject {
    func attachVideo(config: WallpaperConfig, in contentView: NSView) -> VideoPlaybackAttachment?
    func applyVideo(config: WallpaperConfig, attachment: VideoPlaybackAttachment?) -> VideoPlaybackAttachment?
    func pauseVideo(attachment: VideoPlaybackAttachment?)
    func resumeVideo(attachment: VideoPlaybackAttachment?)
    func detachVideo(attachment: VideoPlaybackAttachment?)
}

@MainActor
final class ScreenSession {
    private var config: WallpaperConfig
    private let screen: NSScreen
    private weak var videoGroups: VideoPlaybackGroupProviding?
    private var wallpaperWindow: WallpaperWindow?
    private var videoAttachment: VideoPlaybackAttachment?
    private var webController: WebWallpaperController?
    private var musicController: MusicWallpaperController?
    private var accessedContentURLs: [URL: Bool] = [:]
    private var isVisible = false
    private(set) var isPaused = false

    init(config: WallpaperConfig, screen: NSScreen, videoGroups: VideoPlaybackGroupProviding) {
        self.config = config
        self.screen = screen
        self.videoGroups = videoGroups
    }

    func start() {
        ensureContentAccess()

        let wallpaperWindow = wallpaperWindow ?? WallpaperWindow(screen: screen)
        startContent(in: wallpaperWindow.contentView)
        wallpaperWindow.showBehindDesktopIcons()

        self.wallpaperWindow = wallpaperWindow
        isVisible = true
        isPaused = false
    }

    func update(config: WallpaperConfig) {
        let previousContent = self.config.content
        self.config = config

        guard previousContent == config.content else {
            start()
            releaseContentAccess(keeping: contentAccessURL(for: config.content))
            return
        }

        if wallpaperWindow == nil || activeControllerIsMissing {
            start()
        } else {
            ensureContentAccess()
            applyContent(config: config)
            showRuntimeSurface()
        }
    }

    func pause() {
        pauseContent()
        isPaused = true
    }

    func resume() {
        if wallpaperWindow == nil || activeControllerIsMissing {
            start()
        } else {
            showRuntimeSurface()
            isPaused = false
        }
    }

    func stop() {
        videoGroups?.detachVideo(attachment: videoAttachment)
        webController?.stop()
        musicController?.stop()
        wallpaperWindow?.close()
        releaseContentAccess()
        videoAttachment = nil
        webController = nil
        musicController = nil
        wallpaperWindow = nil
        isVisible = false
        isPaused = false
    }

    func reattachVideoIfNeeded() {
        guard config.content.kind == .video,
              let contentView = wallpaperWindow?.contentView else {
            return
        }

        videoGroups?.detachVideo(attachment: videoAttachment)
        videoAttachment = videoGroups?.attachVideo(config: config, in: contentView)
        if isPaused {
            videoGroups?.pauseVideo(attachment: videoAttachment)
        }
    }

    private func pauseContent() {
        videoGroups?.pauseVideo(attachment: videoAttachment)
        webController?.pause()
        musicController?.pause()
    }

    private func showRuntimeSurface() {
        isPaused = false
        videoGroups?.resumeVideo(attachment: videoAttachment)
        webController?.resume()
        musicController?.resume()

        guard !isVisible else {
            return
        }
        wallpaperWindow?.showBehindDesktopIcons()
        isVisible = true
    }

    private var activeControllerIsMissing: Bool {
        switch config.content.kind {
        case .video:
            videoAttachment == nil
        case .web:
            webController == nil
        case .music:
            musicController == nil
        }
    }

    private func startContent(in contentView: NSView) {
        videoGroups?.detachVideo(attachment: videoAttachment)
        webController?.stop()
        musicController?.stop()

        switch config.content.kind {
        case .video:
            videoAttachment = videoGroups?.attachVideo(config: config, in: contentView)
            webController = nil
            musicController = nil
        case .web:
            let webController = WebWallpaperController()
            webController.start(config: config, in: contentView)
            self.webController = webController
            videoAttachment = nil
            musicController = nil
        case .music:
            let musicController = MusicWallpaperController()
            musicController.start(config: config, in: contentView)
            self.musicController = musicController
            videoAttachment = nil
            webController = nil
        }
    }

    private func applyContent(config: WallpaperConfig) {
        switch config.content.kind {
        case .video:
            videoAttachment = videoGroups?.applyVideo(config: config, attachment: videoAttachment)
        case .web:
            webController?.apply(config: config)
        case .music:
            musicController?.apply(config: config)
        }
    }

    private func ensureContentAccess() {
        let accessURL = contentAccessURL(for: config.content)
        guard accessURL.isFileURL, accessedContentURLs[accessURL] == nil else {
            return
        }
        accessedContentURLs[accessURL] = accessURL.startAccessingSecurityScopedResource()
    }

    private func releaseContentAccess(keeping retainedURL: URL? = nil) {
        for (url, didStartAccessing) in accessedContentURLs where url != retainedURL && didStartAccessing {
            url.stopAccessingSecurityScopedResource()
        }
        accessedContentURLs = accessedContentURLs.filter { $0.key == retainedURL }
    }

    private func contentAccessURL(for content: WallpaperContent) -> URL {
        content.readAccessURL ?? content.url
    }
}

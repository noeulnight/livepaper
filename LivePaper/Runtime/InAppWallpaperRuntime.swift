import AppKit

@MainActor
final class InAppWallpaperRuntime: WallpaperRuntime {
    private var sessions: [DisplayID: ScreenSession] = [:]

    func start(config: WallpaperConfig) async throws {
        let screen = try screen(for: config.displayID)
        let session = ScreenSession(config: config, screen: screen)
        sessions[config.displayID] = session
        session.start()
    }

    func stop(displayID: DisplayID) async {
        sessions[displayID]?.stop()
        sessions.removeValue(forKey: displayID)
    }

    func stopAll() async {
        for session in sessions.values {
            session.stop()
        }
        sessions.removeAll()
    }

    func update(config: WallpaperConfig) async throws {
        if let session = sessions[config.displayID] {
            session.update(config: config)
        } else {
            try await start(config: config)
        }
    }

    func pause(displayID: DisplayID) async {
        sessions[displayID]?.pause()
    }

    func resume(displayID: DisplayID) async {
        sessions[displayID]?.resume()
    }

    private func screen(for displayID: DisplayID) throws -> NSScreen {
        if let screen = NSScreen.screens.first(where: { $0.livePaperDisplayID == displayID }) {
            return screen
        }
        throw WallpaperRuntimeError.displayNotFound(displayID.uuid)
    }
}

enum WallpaperRuntimeError: LocalizedError {
    case displayNotFound(String)
    case missingContentView

    var errorDescription: String? {
        switch self {
        case .displayNotFound(let uuid):
            "Display not found: \(uuid)"
        case .missingContentView:
            "Wallpaper window has no content view."
        }
    }
}

@MainActor
private final class ScreenSession {
    private var config: WallpaperConfig
    private let screen: NSScreen
    private var wallpaperWindow: WallpaperWindow?
    private var playbackController: VideoPlaybackController?
    private var webController: WebWallpaperController?
    private var accessedContentURLs: [URL: Bool] = [:]
    private var isVisible = false

    init(config: WallpaperConfig, screen: NSScreen) {
        self.config = config
        self.screen = screen
    }

    func start() {
        ensureContentAccess()

        let wallpaperWindow = wallpaperWindow ?? WallpaperWindow(screen: screen)
        startContent(in: wallpaperWindow.contentView)
        wallpaperWindow.showBehindDesktopIcons()

        self.wallpaperWindow = wallpaperWindow
        isVisible = true
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
        hideRuntimeSurface()
    }

    func resume() {
        if wallpaperWindow == nil || activeControllerIsMissing {
            start()
        } else {
            showRuntimeSurface()
        }
    }

    func stop() {
        playbackController?.stop()
        webController?.stop()
        wallpaperWindow?.close()
        releaseContentAccess()
        playbackController = nil
        webController = nil
        wallpaperWindow = nil
        isVisible = false
    }

    private func hideRuntimeSurface() {
        guard isVisible else {
            return
        }
        playbackController?.pause()
        webController?.pause()
        wallpaperWindow?.hide()
        isVisible = false
    }

    private func showRuntimeSurface() {
        guard !isVisible else {
            playbackController?.resume()
            webController?.resume()
            return
        }
        playbackController?.resume()
        webController?.resume()
        wallpaperWindow?.showBehindDesktopIcons()
        isVisible = true
    }

    private var activeControllerIsMissing: Bool {
        switch config.content.kind {
        case .video:
            playbackController == nil
        case .web:
            webController == nil
        }
    }

    private func startContent(in contentView: NSView) {
        playbackController?.stop()
        webController?.stop()

        switch config.content.kind {
        case .video:
            let playbackController = VideoPlaybackController()
            playbackController.start(config: config, in: contentView)
            self.playbackController = playbackController
            self.webController = nil
        case .web:
            let webController = WebWallpaperController()
            webController.start(config: config, in: contentView)
            self.webController = webController
            self.playbackController = nil
        }
    }

    private func applyContent(config: WallpaperConfig) {
        switch config.content.kind {
        case .video:
            playbackController?.apply(config: config)
        case .web:
            webController?.apply(config: config)
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

extension NSScreen {
    var livePaperDisplayID: DisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        let uuidString = CFUUIDCreateString(nil, uuid) as String?
        return uuidString.map(DisplayID.init(uuid:))
    }
}

import AppKit

@MainActor
final class InAppWallpaperRuntime: WallpaperRuntime {
    private static let synchronizationInterval: Duration = .seconds(2)

    private var sessions: [DisplayID: ScreenSession] = [:]
    private var synchronizesMatchingWallpapers = true
    private var matchingWallpaperAudioLeaderDisplayID: DisplayID?
    private var synchronizationTask: Task<Void, Never>?

    func setMatchingWallpaperAudioLeader(_ displayID: DisplayID?) async {
        guard matchingWallpaperAudioLeaderDisplayID != displayID else {
            return
        }

        matchingWallpaperAudioLeaderDisplayID = displayID
        if synchronizesMatchingWallpapers {
            synchronizeMatchingVideoSessions()
        }
    }

    func setSynchronizesMatchingWallpapers(_ isEnabled: Bool) async {
        let wasEnabled = synchronizesMatchingWallpapers
        synchronizesMatchingWallpapers = isEnabled
        if isEnabled && !wasEnabled {
            synchronizeMatchingVideoSessions()
        }
        updateSynchronizationLoop()
    }

    func start(config: WallpaperConfig) async throws {
        let screen = try screen(for: config.displayID)
        let session = ScreenSession(config: config, screen: screen)
        sessions[config.displayID] = session
        session.start()
        synchronizeMatchingVideoSession(for: config.displayID)
        updateSynchronizationLoop()
    }

    func stop(displayID: DisplayID) async {
        sessions[displayID]?.stop()
        sessions.removeValue(forKey: displayID)
        updateSynchronizationLoop()
    }

    func stopAll() async {
        for session in sessions.values {
            session.stop()
        }
        sessions.removeAll()
        updateSynchronizationLoop()
    }

    func update(config: WallpaperConfig) async throws {
        if let session = sessions[config.displayID] {
            session.update(config: config)
        } else {
            try await start(config: config)
            return
        }
        synchronizeMatchingVideoSession(for: config.displayID)
        updateSynchronizationLoop()
    }

    func pause(displayID: DisplayID) async {
        sessions[displayID]?.pause()
        updateSynchronizationLoop()
    }

    func resume(displayID: DisplayID) async {
        sessions[displayID]?.resume()
        synchronizeMatchingVideoSession(for: displayID)
        updateSynchronizationLoop()
    }

    private func screen(for displayID: DisplayID) throws -> NSScreen {
        if let screen = NSScreen.screens.first(where: { $0.livePaperDisplayID == displayID }) {
            return screen
        }
        throw WallpaperRuntimeError.displayNotFound(displayID.uuid)
    }

    private func updateSynchronizationLoop() {
        guard synchronizesMatchingWallpapers, hasMatchingVideoSessions else {
            synchronizationTask?.cancel()
            synchronizationTask = nil
            return
        }

        guard synchronizationTask == nil else {
            return
        }

        synchronizationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.synchronizationInterval)
                guard !Task.isCancelled else {
                    return
                }
                self?.synchronizeMatchingVideoSessions()
                self?.updateSynchronizationLoop()
            }
        }
    }

    private var hasMatchingVideoSessions: Bool {
        matchingVideoSessionGroups.contains { $0.value.count > 1 }
    }

    private var matchingVideoSessionGroups: [String: [(displayID: DisplayID, session: ScreenSession)]] {
        Dictionary(grouping: activeVideoSessions, by: { $0.session.videoSynchronizationKey ?? "" })
            .filter { !$0.key.isEmpty }
    }

    private var activeVideoSessions: [(displayID: DisplayID, session: ScreenSession)] {
        sessions
            .filter { !$0.value.isPaused && $0.value.videoSynchronizationKey != nil }
            .map { (displayID: $0.key, session: $0.value) }
            .sorted { $0.displayID.uuid < $1.displayID.uuid }
    }

    private func synchronizeMatchingVideoSession(for displayID: DisplayID) {
        guard synchronizesMatchingWallpapers,
              let targetSession = sessions[displayID],
              !targetSession.isPaused,
              let synchronizationKey = targetSession.videoSynchronizationKey,
              let group = matchingVideoSessionGroups[synchronizationKey],
              group.count > 1 else {
            return
        }

        synchronizeMatchingVideoSessionGroup(group)
    }

    private func synchronizeMatchingVideoSessions() {
        guard synchronizesMatchingWallpapers else {
            return
        }

        for group in matchingVideoSessionGroups.values where group.count > 1 {
            synchronizeMatchingVideoSessionGroup(group)
        }
    }

    private func synchronizeMatchingVideoSessionGroup(
        _ group: [(displayID: DisplayID, session: ScreenSession)]
    ) {
        let displayIDs = group.map(\.displayID)
        guard let referenceDisplayID = Self.synchronizationReferenceDisplayID(
            in: displayIDs,
            audioLeaderDisplayID: matchingWallpaperAudioLeaderDisplayID
        ),
              let reference = group.first(where: { $0.displayID == referenceDisplayID })?.session,
              let snapshot = reference.videoSynchronizationSnapshot else {
            return
        }

        for follower in group where follower.displayID != referenceDisplayID {
            follower.session.synchronizeVideoTimeline(to: snapshot)
        }
    }

    nonisolated static func synchronizationReferenceDisplayID(
        in displayIDs: [DisplayID],
        audioLeaderDisplayID: DisplayID?
    ) -> DisplayID? {
        if let audioLeaderDisplayID, displayIDs.contains(audioLeaderDisplayID) {
            return audioLeaderDisplayID
        }

        return displayIDs.first
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
    private var musicController: MusicWallpaperController?
    private var accessedContentURLs: [URL: Bool] = [:]
    private var isVisible = false
    private(set) var isPaused = false

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
        playbackController?.stop()
        webController?.stop()
        musicController?.stop()
        wallpaperWindow?.close()
        releaseContentAccess()
        playbackController = nil
        webController = nil
        musicController = nil
        wallpaperWindow = nil
        isVisible = false
        isPaused = false
    }

    var videoSynchronizationKey: String? {
        guard config.content.kind == .video else {
            return nil
        }
        return config.content.galleryID
    }

    var videoSynchronizationSnapshot: VideoPlaybackSyncSnapshot? {
        playbackController?.synchronizationSnapshot
    }

    func synchronizeVideoTimeline(to snapshot: VideoPlaybackSyncSnapshot) {
        playbackController?.synchronizeTimeline(to: snapshot)
    }

    private func pauseContent() {
        playbackController?.pause()
        webController?.pause()
        musicController?.pause()
    }

    private func showRuntimeSurface() {
        isPaused = false
        guard !isVisible else {
            playbackController?.resume()
            webController?.resume()
            musicController?.resume()
            return
        }
        playbackController?.resume()
        webController?.resume()
        musicController?.resume()
        wallpaperWindow?.showBehindDesktopIcons()
        isVisible = true
    }

    private var activeControllerIsMissing: Bool {
        switch config.content.kind {
        case .video:
            playbackController == nil
        case .web:
            webController == nil
        case .music:
            musicController == nil
        }
    }

    private func startContent(in contentView: NSView) {
        playbackController?.stop()
        webController?.stop()
        musicController?.stop()

        switch config.content.kind {
        case .video:
            let playbackController = VideoPlaybackController()
            playbackController.start(config: config, in: contentView)
            self.playbackController = playbackController
            self.webController = nil
            self.musicController = nil
        case .web:
            let webController = WebWallpaperController()
            webController.start(config: config, in: contentView)
            self.webController = webController
            self.playbackController = nil
            self.musicController = nil
        case .music:
            let musicController = MusicWallpaperController()
            musicController.start(config: config, in: contentView)
            self.musicController = musicController
            self.playbackController = nil
            self.webController = nil
        }
    }

    private func applyContent(config: WallpaperConfig) {
        switch config.content.kind {
        case .video:
            playbackController?.apply(config: config)
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

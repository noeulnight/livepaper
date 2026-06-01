import XCTest
@testable import LivePaper

@MainActor
final class WallpaperCoordinatorMusicSyncTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "LivePaperMusicSyncTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMusicSyncRestoresPreviousWallpaperWithoutSavingMusicContent() async throws {
        let runtime = RecordingWallpaperRuntime()
        let store = WallpaperSettingsStore(defaults: defaults)
        let monitor = MutableNowPlayingMonitor(playbackState: .playing)
        let coordinator = WallpaperCoordinator(
            runtime: runtime,
            store: store,
            loginItemController: LoginItemController(service: TestLoginItemService()),
            nowPlayingMonitor: monitor
        )
        guard let displayID = coordinator.displays.first?.id else {
            throw XCTSkip("No display available in test environment.")
        }

        coordinator.applyLockScreenAutomatically = false
        coordinator.selectedDisplayIDs = [displayID]
        coordinator.selectVideo(url: URL(fileURLWithPath: "/tmp/original.mov"))
        await coordinator.applySelectedContent()

        XCTAssertEqual(runtime.updateCalls.last?.content.kind, .video)
        XCTAssertEqual(store.loadSavedConfigs()[displayID]?.content.kind, .video)

        await coordinator.setMusicSyncSource(.spotify)
        await coordinator.setMusicSyncEnabled(true)

        XCTAssertTrue(coordinator.isMusicSyncEnabled)
        XCTAssertEqual(runtime.updateCalls.last?.content.kind, .music)
        XCTAssertEqual(runtime.updateCalls.last?.content.musicSource, .spotify)
        XCTAssertEqual(store.loadSavedConfigs()[displayID]?.content.kind, .video)

        await coordinator.setMusicSyncEnabled(false)

        XCTAssertFalse(coordinator.isMusicSyncEnabled)
        XCTAssertEqual(runtime.updateCalls.last?.content.kind, .video)
        XCTAssertEqual(store.loadSavedConfigs()[displayID]?.content.kind, .video)
    }

    func testMusicSyncStopsRuntimeWhenThereWasNoPreviousWallpaper() async throws {
        let runtime = RecordingWallpaperRuntime()
        let monitor = MutableNowPlayingMonitor(playbackState: .playing)
        let coordinator = WallpaperCoordinator(
            runtime: runtime,
            store: WallpaperSettingsStore(defaults: defaults),
            loginItemController: LoginItemController(service: TestLoginItemService()),
            nowPlayingMonitor: monitor
        )
        guard let displayID = coordinator.displays.first?.id else {
            throw XCTSkip("No display available in test environment.")
        }

        coordinator.selectedDisplayIDs = [displayID]
        await coordinator.setMusicSyncEnabled(true)
        await coordinator.setMusicSyncEnabled(false)

        XCTAssertEqual(runtime.updateCalls.map(\.content.kind), [.music])
        XCTAssertEqual(runtime.stopCalls, [displayID])
    }

    func testMusicSyncShowsOriginalWallpaperWhilePlaybackIsPaused() async throws {
        let runtime = RecordingWallpaperRuntime()
        let monitor = MutableNowPlayingMonitor(playbackState: .paused)
        let coordinator = WallpaperCoordinator(
            runtime: runtime,
            store: WallpaperSettingsStore(defaults: defaults),
            loginItemController: LoginItemController(service: TestLoginItemService()),
            nowPlayingMonitor: monitor
        )
        guard let displayID = coordinator.displays.first?.id else {
            throw XCTSkip("No display available in test environment.")
        }

        coordinator.applyLockScreenAutomatically = false
        coordinator.selectedDisplayIDs = [displayID]
        coordinator.selectVideo(url: URL(fileURLWithPath: "/tmp/original.mov"))
        await coordinator.applySelectedContent()

        await coordinator.setMusicSyncEnabled(true)

        XCTAssertTrue(coordinator.isMusicSyncEnabled)
        XCTAssertEqual(runtime.updateCalls.last?.content.kind, .video)

        monitor.playbackState = .playing
        await coordinator.setMusicWallpaperStyle(.focus)

        XCTAssertEqual(runtime.updateCalls.last?.content.kind, .music)
        XCTAssertEqual(runtime.updateCalls.last?.musicStyle, .focus)

        monitor.playbackState = .paused
        await coordinator.setMusicWallpaperStyle(.minimal)

        XCTAssertEqual(runtime.updateCalls.last?.content.kind, .video)

        await coordinator.setMusicSyncEnabled(false)
    }

    func testApplyingWallpaperKeepsMusicSyncEnabledAndUpdatesStandbyWallpaper() async throws {
        let runtime = RecordingWallpaperRuntime()
        let store = WallpaperSettingsStore(defaults: defaults)
        let monitor = MutableNowPlayingMonitor(playbackState: .playing)
        let coordinator = WallpaperCoordinator(
            runtime: runtime,
            store: store,
            loginItemController: LoginItemController(service: TestLoginItemService()),
            nowPlayingMonitor: monitor
        )
        guard let displayID = coordinator.displays.first?.id else {
            throw XCTSkip("No display available in test environment.")
        }

        coordinator.applyLockScreenAutomatically = false
        coordinator.selectedDisplayIDs = [displayID]
        coordinator.selectVideo(url: URL(fileURLWithPath: "/tmp/original.mov"))
        await coordinator.applySelectedContent()
        await coordinator.setMusicSyncEnabled(true)

        XCTAssertTrue(coordinator.isMusicSyncEnabled)
        XCTAssertEqual(runtime.updateCalls.last?.content.kind, .music)

        coordinator.selectVideo(url: URL(fileURLWithPath: "/tmp/replacement.mov"))
        await coordinator.applySelectedContent()

        XCTAssertTrue(coordinator.isMusicSyncEnabled)
        XCTAssertTrue(store.loadRuntimePreferences().isMusicSyncEnabled)
        XCTAssertEqual(runtime.updateCalls.last?.content.kind, .music)
        XCTAssertEqual(store.loadSavedConfigs()[displayID]?.content.url.path, "/tmp/replacement.mov")

        await coordinator.setMusicSyncEnabled(false)

        XCTAssertFalse(coordinator.isMusicSyncEnabled)
        XCTAssertEqual(runtime.updateCalls.last?.content.kind, .video)
        XCTAssertEqual(runtime.updateCalls.last?.content.url.path, "/tmp/replacement.mov")
        XCTAssertEqual(store.loadSavedConfigs()[displayID]?.content.url.path, "/tmp/replacement.mov")
    }

    func testMusicSyncMonitorReadsSelectedSource() async throws {
        let runtime = RecordingWallpaperRuntime()
        let monitor = MutableNowPlayingMonitor(playbackState: .playing)
        let coordinator = WallpaperCoordinator(
            runtime: runtime,
            store: WallpaperSettingsStore(defaults: defaults),
            loginItemController: LoginItemController(service: TestLoginItemService()),
            nowPlayingMonitor: monitor
        )
        guard let displayID = coordinator.displays.first?.id else {
            throw XCTSkip("No display available in test environment.")
        }

        coordinator.selectedDisplayIDs = [displayID]
        await coordinator.setMusicSyncEnabled(true)
        await coordinator.setMusicWallpaperStyle(.focus)

        XCTAssertTrue(monitor.currentAlbumSources.contains(.appleMusic))

        await coordinator.setMusicSyncSource(.spotify)

        XCTAssertEqual(monitor.currentAlbumSources.last, .spotify)

        await coordinator.setMusicSyncEnabled(false)
    }
}

private struct TestLoginItemService: LoginItemServiceManaging {
    var status: LoginItemStatus.RegistrationStatus { .notRegistered }
    func register() throws {}
    func unregister() throws {}
}

private final class MutableNowPlayingMonitor: NowPlayingAlbumMonitoring {
    var playbackState: MusicPlaybackState
    private(set) var currentAlbumSources: [WallpaperContent.MusicSource] = []

    init(playbackState: MusicPlaybackState) {
        self.playbackState = playbackState
    }

    func currentAlbum(source: WallpaperContent.MusicSource) async -> NowPlayingAlbumSnapshot? {
        currentAlbumSources.append(source)
        return snapshot(source: source)
    }

    func subscribe(
        source: WallpaperContent.MusicSource,
        handler: @escaping @MainActor (NowPlayingAlbumSnapshot?) -> Void
    ) -> NowPlayingAlbumSubscription {
        handler(snapshot(source: source))
        return NowPlayingAlbumSubscription {}
    }

    private func snapshot(source: WallpaperContent.MusicSource) -> NowPlayingAlbumSnapshot {
        NowPlayingAlbumSnapshot(
            source: source,
            playbackState: playbackState,
            trackID: "track-id",
            trackTitle: "Track",
            artistName: "Artist",
            albumTitle: "Album",
            artworkURL: nil,
            artworkFileURL: nil,
            playbackPosition: 12,
            playbackDuration: 120
        )
    }
}

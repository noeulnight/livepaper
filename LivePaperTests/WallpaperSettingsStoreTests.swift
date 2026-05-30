import XCTest
@testable import LivePaper

@MainActor
final class WallpaperSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "LivePaperTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDecodesLegacyVideoURLSavedConfig() throws {
        let displayID = DisplayID(uuid: "display-a")
        let legacyConfig = LegacySavedWallpaperConfig(
            displayID: displayID,
            videoURL: URL(fileURLWithPath: "/tmp/legacy.mov"),
            scaleMode: .fit,
            volume: 0.4,
            muted: true,
            pauseOnBattery: false,
            pauseOnFullscreen: true
        )
        defaults.set(try JSONEncoder().encode([legacyConfig]), forKey: "wallpaper.configs")

        let configs = WallpaperSettingsStore(defaults: defaults).loadSavedConfigs()

        XCTAssertEqual(configs[displayID]?.content, .video(URL(fileURLWithPath: "/tmp/legacy.mov")))
        XCTAssertEqual(configs[displayID]?.scaleMode, .fit)
        XCTAssertEqual(configs[displayID]?.volume, 0.4)
        XCTAssertEqual(configs[displayID]?.muted, true)
        XCTAssertEqual(configs[displayID]?.muteOnFullscreen, false)
    }

    func testRuntimePreferenceDefaults() {
        let preferences = WallpaperSettingsStore(defaults: defaults).loadRuntimePreferences()

        XCTAssertEqual(preferences.scaleMode, .fill)
        XCTAssertFalse(preferences.muted)
        XCTAssertEqual(preferences.volume, 1)
        XCTAssertNil(preferences.audioDisplayID)
        XCTAssertTrue(preferences.pauseOnBattery)
        XCTAssertTrue(preferences.pauseOnFullscreen)
        XCTAssertFalse(preferences.muteOnFullscreen)
        XCTAssertTrue(preferences.applyLockScreenAutomatically)
        XCTAssertTrue(preferences.synchronizeMatchingWallpapers)
        XCTAssertEqual(preferences.musicSyncSource, .appleMusic)
        XCTAssertFalse(preferences.isMusicSyncEnabled)
        XCTAssertEqual(preferences.musicWallpaperStyle, .ambient)
    }

    func testRuntimePreferencesPersistPlaybackSettings() {
        let store = WallpaperSettingsStore(defaults: defaults)

        store.saveRuntimePreferences(
            RuntimePreferences(
                scaleMode: .fit,
                muted: true,
                volume: 0.2,
                audioDisplayID: nil,
                pauseOnBattery: false,
                pauseOnFullscreen: false,
                muteOnFullscreen: true,
                applyLockScreenAutomatically: false,
                synchronizeMatchingWallpapers: false,
                musicSyncSource: .spotify,
                isMusicSyncEnabled: true,
                musicWallpaperStyle: .minimal
            )
        )

        let preferences = store.loadRuntimePreferences()
        XCTAssertFalse(preferences.applyLockScreenAutomatically)
        XCTAssertFalse(preferences.synchronizeMatchingWallpapers)
        XCTAssertEqual(preferences.musicSyncSource, .spotify)
        XCTAssertTrue(preferences.isMusicSyncEnabled)
        XCTAssertEqual(preferences.musicWallpaperStyle, .minimal)
    }

    func testFirstLaunchIntroDefaultsToVisibleForNewUsers() {
        let store = WallpaperSettingsStore(defaults: defaults)

        XCTAssertTrue(store.shouldShowFirstLaunchIntro(hasExistingWallpapers: false))
    }

    func testMarkFirstLaunchIntroCompletedHidesIntro() {
        let store = WallpaperSettingsStore(defaults: defaults)

        store.markFirstLaunchIntroCompleted()

        XCTAssertFalse(store.shouldShowFirstLaunchIntro(hasExistingWallpapers: false))
    }

    func testExistingWallpapersCompleteFirstLaunchIntro() {
        let store = WallpaperSettingsStore(defaults: defaults)

        XCTAssertFalse(store.shouldShowFirstLaunchIntro(hasExistingWallpapers: true))
        XCTAssertFalse(store.shouldShowFirstLaunchIntro(hasExistingWallpapers: false))
    }
}

private struct LegacySavedWallpaperConfig: Codable {
    let displayID: DisplayID
    let videoURL: URL
    let scaleMode: ScaleMode
    let volume: Double
    let muted: Bool
    let pauseOnBattery: Bool
    let pauseOnFullscreen: Bool
}

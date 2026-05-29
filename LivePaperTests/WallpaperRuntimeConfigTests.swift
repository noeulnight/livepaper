import XCTest
@testable import LivePaper

@MainActor
final class WallpaperRuntimeConfigTests: XCTestCase {
    func testDisplaySelectionChoosesConfiguredAudioOwner() {
        let displayA = DisplayID(uuid: "display-a")
        let displayB = DisplayID(uuid: "display-b")
        let selection = DisplaySelectionModel()
        selection.audioDisplayID = displayB

        XCTAssertEqual(
            selection.audioOwnerID(activeDisplayIDs: [displayA, displayB], muted: false),
            displayB
        )
        XCTAssertNil(selection.audioOwnerID(activeDisplayIDs: [displayA, displayB], muted: true))
    }

    func testRuntimeConfigMutesNonAudioOwnerAndFullscreenMutedDisplay() {
        let displayA = DisplayID(uuid: "display-a")
        let displayB = DisplayID(uuid: "display-b")
        let config = WallpaperConfig(
            displayID: displayA,
            content: .web(URL(string: "https://example.com")!),
            muted: false,
            muteOnFullscreen: true
        )

        XCTAssertTrue(
            WallpaperRuntimeController.shouldMute(
                config: config,
                audioOwnerID: displayB,
                fullscreenDisplayIDs: []
            )
        )
        XCTAssertTrue(
            WallpaperRuntimeController.shouldMute(
                config: config,
                audioOwnerID: displayA,
                fullscreenDisplayIDs: [displayA]
            )
        )
        XCTAssertFalse(
            WallpaperRuntimeController.shouldMute(
                config: config,
                audioOwnerID: displayA,
                fullscreenDisplayIDs: []
            )
        )
    }

    func testSavedConfigRoundTripFromRuntimeConfig() {
        let config = WallpaperConfig(
            displayID: DisplayID(uuid: "display-a"),
            content: .video(URL(fileURLWithPath: "/tmp/wallpaper.mov")),
            scaleMode: .center,
            volume: 0.25,
            muted: true,
            pauseOnBattery: false,
            pauseOnFullscreen: false,
            muteOnFullscreen: true
        )

        let savedConfig = WallpaperRuntimeController.savedConfig(from: config)
        let restoredConfig = WallpaperRuntimeController.desiredConfig(from: savedConfig)

        XCTAssertEqual(restoredConfig, config)
    }

    func testApplyRuntimeConfigsSkipsRuntimeUpdateForPausedDisplays() async throws {
        let runtime = RecordingWallpaperRuntime()
        let controller = WallpaperRuntimeController(runtime: runtime)
        let displayID = DisplayID(uuid: "display-a")
        let config = WallpaperConfig(
            displayID: displayID,
            content: .video(URL(fileURLWithPath: "/tmp/wallpaper.mov"))
        )

        try await controller.applyRuntimeConfigs(
            [displayID: config],
            audioOwnerID: displayID,
            fullscreenDisplayIDs: [displayID],
            pausedDisplayIDs: [displayID],
            orderedDisplayIDs: { Array($0) }
        )

        XCTAssertEqual(controller.activeConfigs[displayID], config)
        XCTAssertEqual(controller.pausedDisplayIDs, [displayID])
        XCTAssertEqual(runtime.pauseCalls, [displayID])
        XCTAssertTrue(runtime.updateCalls.isEmpty)
    }

    func testApplyRuntimeConfigsUpdatesRuntimeAfterPausedDisplayBecomesActive() async throws {
        let runtime = RecordingWallpaperRuntime()
        let controller = WallpaperRuntimeController(runtime: runtime)
        let displayID = DisplayID(uuid: "display-a")
        let config = WallpaperConfig(
            displayID: displayID,
            content: .video(URL(fileURLWithPath: "/tmp/wallpaper.mov"))
        )

        try await controller.applyRuntimeConfigs(
            [displayID: config],
            audioOwnerID: displayID,
            fullscreenDisplayIDs: [displayID],
            pausedDisplayIDs: [displayID],
            orderedDisplayIDs: { Array($0) }
        )
        try await controller.applyRuntimeConfigs(
            [displayID: config],
            audioOwnerID: displayID,
            fullscreenDisplayIDs: [],
            orderedDisplayIDs: { Array($0) }
        )

        XCTAssertTrue(controller.pausedDisplayIDs.isEmpty)
        XCTAssertEqual(runtime.pauseCalls, [displayID])
        XCTAssertEqual(runtime.updateCalls.map(\.displayID), [displayID])
    }
}

@MainActor
private final class RecordingWallpaperRuntime: WallpaperRuntime {
    private(set) var updateCalls: [WallpaperConfig] = []
    private(set) var pauseCalls: [DisplayID] = []

    func start(config: WallpaperConfig) async throws {
        updateCalls.append(config)
    }

    func stop(displayID: DisplayID) async {}

    func stopAll() async {}

    func update(config: WallpaperConfig) async throws {
        updateCalls.append(config)
    }

    func pause(displayID: DisplayID) async {
        pauseCalls.append(displayID)
    }

    func resume(displayID: DisplayID) async {}
}

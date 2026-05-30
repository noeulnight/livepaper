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

    func testApplyRuntimeConfigsUpdatesRuntimeBeforePausingPausedDisplays() async throws {
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
            synchronizeMatchingWallpapers: false,
            orderedDisplayIDs: { Array($0) }
        )

        XCTAssertEqual(controller.activeConfigs[displayID], config)
        XCTAssertEqual(controller.pausedDisplayIDs, [displayID])
        XCTAssertEqual(runtime.matchingWallpaperAudioLeaderCalls, [displayID])
        XCTAssertEqual(runtime.synchronizeMatchingWallpapersCalls, [false])
        XCTAssertEqual(runtime.runtimeOptionEvents, ["sync:false", "audio:display-a"])
        XCTAssertEqual(runtime.pauseCalls, [displayID])
        XCTAssertEqual(runtime.updateCalls.map(\.displayID), [displayID])
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
        XCTAssertEqual(runtime.updateCalls.map(\.displayID), [displayID, displayID])
    }

    func testMatchingWallpaperSynchronizationReferencePrefersAudioLeader() {
        let displayA = DisplayID(uuid: "display-a")
        let displayB = DisplayID(uuid: "display-b")

        XCTAssertEqual(
            InAppWallpaperRuntime.synchronizationReferenceDisplayID(
                in: [displayA, displayB],
                audioLeaderDisplayID: displayB
            ),
            displayB
        )
    }

    func testMatchingWallpaperSynchronizationReferenceFallsBackToRuntimeOrder() {
        let displayA = DisplayID(uuid: "display-a")
        let displayB = DisplayID(uuid: "display-b")
        let displayC = DisplayID(uuid: "display-c")

        XCTAssertEqual(
            InAppWallpaperRuntime.synchronizationReferenceDisplayID(
                in: [displayA, displayB],
                audioLeaderDisplayID: displayC
            ),
            displayA
        )
    }
}

@MainActor
final class RecordingWallpaperRuntime: WallpaperRuntime {
    private(set) var updateCalls: [WallpaperConfig] = []
    private(set) var pauseCalls: [DisplayID] = []
    private(set) var stopCalls: [DisplayID] = []
    private(set) var matchingWallpaperAudioLeaderCalls: [DisplayID?] = []
    private(set) var synchronizeMatchingWallpapersCalls: [Bool] = []
    private(set) var runtimeOptionEvents: [String] = []
    private(set) var events: [String] = []

    func setMatchingWallpaperAudioLeader(_ displayID: DisplayID?) async {
        matchingWallpaperAudioLeaderCalls.append(displayID)
        runtimeOptionEvents.append("audio:\(displayID?.uuid ?? "nil")")
    }

    func setSynchronizesMatchingWallpapers(_ isEnabled: Bool) async {
        synchronizeMatchingWallpapersCalls.append(isEnabled)
        runtimeOptionEvents.append("sync:\(isEnabled)")
    }

    func start(config: WallpaperConfig) async throws {
        updateCalls.append(config)
        events.append("update:\(config.content.url.absoluteString)")
    }

    func stop(displayID: DisplayID) async {
        stopCalls.append(displayID)
        events.append("stop:\(displayID.uuid)")
    }

    func stopAll() async {}

    func update(config: WallpaperConfig) async throws {
        updateCalls.append(config)
        events.append("update:\(config.content.url.absoluteString)")
    }

    func pause(displayID: DisplayID) async {
        pauseCalls.append(displayID)
        events.append("pause:\(displayID.uuid)")
    }

    func resume(displayID: DisplayID) async {}
}

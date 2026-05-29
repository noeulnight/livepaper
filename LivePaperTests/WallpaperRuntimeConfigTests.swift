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
}

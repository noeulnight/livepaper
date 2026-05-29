import XCTest
@testable import LivePaper

@MainActor
final class WallpaperCoordinatorPolicyTests: XCTestCase {
    func testRuntimePauseIsIdempotent() async throws {
        let runtime = RecordingWallpaperRuntime()
        let displayID = DisplayID(uuid: "display-a")

        try await runtime.update(
            config: WallpaperConfig(
                displayID: displayID,
                content: .video(URL(fileURLWithPath: "/tmp/wallpaper.mov"))
            )
        )

        await runtime.pause(displayID: displayID)
        try await runtime.update(
            config: WallpaperConfig(
                displayID: displayID,
                content: .video(URL(fileURLWithPath: "/tmp/wallpaper.mov"))
            )
        )
        await runtime.pause(displayID: displayID)

        XCTAssertEqual(runtime.pauseCalls, [displayID, displayID])
        XCTAssertEqual(runtime.updateCalls.map(\.displayID), [displayID, displayID])
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

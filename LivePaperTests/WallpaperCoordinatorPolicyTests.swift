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

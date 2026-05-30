import XCTest
@testable import LivePaper

@MainActor
final class WallpaperApplyCoordinatorTests: XCTestCase {
    func testStatusUpdatePublishesCurrentApplyStatus() {
        let coordinator = WallpaperApplyCoordinator()
        let content = WallpaperContent.video(URL(fileURLWithPath: "/tmp/wallpaper.mov"))
        var observedStatuses: [WallpaperApplyStatus] = []
        coordinator.statusDidChange = { observedStatuses.append($0) }

        coordinator.updateStatus(
            content: content,
            displayCount: 2,
            desktop: .init(state: .applying, detail: "Applying"),
            lockScreen: .init(state: .skipped, detail: "Auto off"),
            screenSaver: .init(state: .applying, detail: "Updating")
        )

        XCTAssertEqual(coordinator.status.contentName, "wallpaper.mov")
        XCTAssertEqual(coordinator.status.displayCount, 2)
        XCTAssertEqual(coordinator.status.desktop.state, .applying)
        XCTAssertEqual(observedStatuses.last, coordinator.status)
    }

    func testMarkStatusFailedOnlyFailsApplyingSurfaces() {
        let coordinator = WallpaperApplyCoordinator()
        let content = WallpaperContent.video(URL(fileURLWithPath: "/tmp/wallpaper.mov"))
        coordinator.updateStatus(
            content: content,
            displayCount: 1,
            desktop: .init(state: .applied, detail: "Applied"),
            lockScreen: .init(state: .applying, detail: "Exporting"),
            screenSaver: .init(state: .skipped, detail: "Video only")
        )

        coordinator.markStatusFailed(detail: "Export failed")

        XCTAssertEqual(coordinator.status.desktop.state, .applied)
        XCTAssertEqual(coordinator.status.lockScreen, .init(state: .failed, detail: "Export failed"))
        XCTAssertEqual(coordinator.status.screenSaver.state, .skipped)
    }

    func testRefreshStatusUsesSavedConfigsWhenRuntimeIsInactive() {
        let coordinator = WallpaperApplyCoordinator()
        let displayID = DisplayID(uuid: "display-a")
        let content = WallpaperContent.video(URL(fileURLWithPath: "/tmp/wallpaper.mov"))
        let savedConfig = SavedWallpaperConfig(
            displayID: displayID,
            content: content,
            scaleMode: .fill,
            volume: 1,
            muted: false,
            pauseOnBattery: true,
            pauseOnFullscreen: true
        )

        coordinator.refreshStatus(
            activeConfigs: [:],
            savedConfigs: [displayID: savedConfig],
            availableDisplayIDs: [displayID],
            applyAutomatically: false,
            orderedDisplayIDs: { Array($0) }
        )

        XCTAssertEqual(coordinator.status.contentName, "wallpaper.mov")
        XCTAssertEqual(coordinator.status.displayCount, 1)
        XCTAssertEqual(coordinator.status.desktop, .init(state: .applied, detail: "Restored"))
        XCTAssertEqual(coordinator.status.lockScreen, .init(state: .skipped, detail: "Auto off"))
        XCTAssertEqual(coordinator.status.screenSaver, .init(state: .applied, detail: "Updated"))
    }
}

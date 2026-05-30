import XCTest
@testable import LivePaper

@MainActor
final class RuntimePolicyControllerTests: XCTestCase {
    func testPeriodicRefreshStartsAndStopsWithActiveState() {
        let controller = RuntimePolicyController()

        XCTAssertFalse(controller.isPeriodicRefreshActive)

        controller.updatePeriodicRefresh(isActive: true) {}
        XCTAssertTrue(controller.isPeriodicRefreshActive)

        controller.updatePeriodicRefresh(isActive: true) {}
        XCTAssertTrue(controller.isPeriodicRefreshActive)

        controller.updatePeriodicRefresh(isActive: false) {}
        XCTAssertFalse(controller.isPeriodicRefreshActive)
    }

    func testFullscreenDetectionRequiresStableConsecutiveResults() {
        let displayA = DisplayID(uuid: "display-a")
        var detections: [Set<DisplayID>] = [[displayA], []]
        let controller = RuntimePolicyController(
            fullscreenDetector: { detections.removeFirst() },
            missionControlDetector: { false },
            requiredStableFullscreenDetections: 2
        )

        controller.refreshDetectedPolicyState()
        XCTAssertEqual(controller.fullscreenDisplayIDs, [])

        controller.refreshDetectedPolicyState()
        XCTAssertEqual(controller.fullscreenDisplayIDs, [])
    }

    func testFullscreenDetectionCommitsAfterStableConsecutiveResults() {
        let displayA = DisplayID(uuid: "display-a")
        var detections: [Set<DisplayID>] = [[displayA], [displayA]]
        let controller = RuntimePolicyController(
            fullscreenDetector: { detections.removeFirst() },
            missionControlDetector: { false },
            requiredStableFullscreenDetections: 2
        )

        controller.refreshDetectedPolicyState()
        XCTAssertEqual(controller.fullscreenDisplayIDs, [])

        controller.refreshDetectedPolicyState()
        XCTAssertEqual(controller.fullscreenDisplayIDs, [displayA])
    }

    func testFullscreenDetectionClearsAfterStableEmptyResults() {
        let displayA = DisplayID(uuid: "display-a")
        var detections: [Set<DisplayID>] = [[displayA], [displayA], [], []]
        let controller = RuntimePolicyController(
            fullscreenDetector: { detections.removeFirst() },
            missionControlDetector: { false },
            requiredStableFullscreenDetections: 2
        )

        controller.refreshDetectedPolicyState()
        controller.refreshDetectedPolicyState()
        XCTAssertEqual(controller.fullscreenDisplayIDs, [displayA])

        controller.refreshDetectedPolicyState()
        XCTAssertEqual(controller.fullscreenDisplayIDs, [displayA])

        controller.refreshDetectedPolicyState()
        XCTAssertEqual(controller.fullscreenDisplayIDs, [])
    }

    func testMissionControlClearsFullscreenImmediately() {
        let displayA = DisplayID(uuid: "display-a")
        var missionControlDetections = [false, true]
        let controller = RuntimePolicyController(
            fullscreenDetector: { [displayA] },
            missionControlDetector: { missionControlDetections.removeFirst() },
            requiredStableFullscreenDetections: 1
        )

        controller.refreshDetectedPolicyState()
        XCTAssertEqual(controller.fullscreenDisplayIDs, [displayA])

        controller.refreshDetectedPolicyState()
        XCTAssertTrue(controller.isMissionControlActive)
        XCTAssertEqual(controller.fullscreenDisplayIDs, [])
    }

    func testFullscreenDetectionRestabilizesAfterMissionControlCloses() {
        let displayA = DisplayID(uuid: "display-a")
        var missionControlDetections = [false, true, false, false]
        let controller = RuntimePolicyController(
            fullscreenDetector: { [displayA] },
            missionControlDetector: { missionControlDetections.removeFirst() },
            requiredStableFullscreenDetections: 2
        )

        controller.refreshDetectedPolicyState()
        controller.refreshDetectedPolicyState()
        XCTAssertEqual(controller.fullscreenDisplayIDs, [])

        controller.refreshDetectedPolicyState()
        XCTAssertEqual(controller.fullscreenDisplayIDs, [])

        controller.refreshDetectedPolicyState()
        XCTAssertEqual(controller.fullscreenDisplayIDs, [displayA])
    }
}

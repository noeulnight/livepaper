import CoreGraphics
import XCTest
@testable import LivePaper

final class FullscreenWindowDetectorTests: XCTestCase {
    private let displayBounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 820)

    func testCoversWhenWindowCoversDisplayBounds() {
        let windowBounds = CGRect(x: 0, y: 0, width: 1440, height: 900)

        XCTAssertTrue(
            FullscreenWindowDetector.covers(
                windowBounds: windowBounds,
                displayBounds: displayBounds,
                visibleFrame: visibleFrame
            )
        )
    }

    func testCoversWhenWindowCoversVisibleFrame() {
        let windowBounds = CGRect(x: 0, y: 25, width: 1440, height: 780)

        XCTAssertTrue(
            FullscreenWindowDetector.covers(
                windowBounds: windowBounds,
                displayBounds: displayBounds,
                visibleFrame: visibleFrame
            )
        )
    }

    func testDoesNotCoverWhenWindowIsSmallerThanVisibleFrameThreshold() {
        let windowBounds = CGRect(x: 0, y: 25, width: 1100, height: 700)

        XCTAssertFalse(
            FullscreenWindowDetector.covers(
                windowBounds: windowBounds,
                displayBounds: displayBounds,
                visibleFrame: visibleFrame
            )
        )
    }

    func testDoesNotCoverEmptyOrNullRects() {
        XCTAssertFalse(
            FullscreenWindowDetector.covers(
                windowBounds: .null,
                displayBounds: displayBounds,
                visibleFrame: visibleFrame
            )
        )
        XCTAssertFalse(
            FullscreenWindowDetector.covers(
                windowBounds: .zero,
                displayBounds: displayBounds,
                visibleFrame: visibleFrame
            )
        )
    }

    func testDockOwnedMissionControlWindowIsNotFullscreenCandidate() {
        XCTAssertFalse(
            FullscreenWindowDetector.isCandidateFullscreenWindow(
                fullscreenWindowInfo(ownerName: "Dock"),
                currentProcessID: 42
            )
        )
    }

    func testAppOwnedLayerZeroWindowIsFullscreenCandidate() {
        XCTAssertTrue(
            FullscreenWindowDetector.isCandidateFullscreenWindow(
                fullscreenWindowInfo(ownerName: "Safari"),
                currentProcessID: 42
            )
        )
    }

    func testDockDisplayOverlayMarksMissionControlActive() {
        XCTAssertTrue(
            FullscreenWindowDetector.isMissionControlActive(
                windowInfos: [
                    windowInfo(ownerName: "Dock", layer: 20, bounds: displayBounds),
                    fullscreenWindowInfo(ownerName: "Safari")
                ],
                displayBounds: [displayBounds]
            )
        )
    }

    func testFullscreenWindowWithoutDockOverlayDoesNotMarkMissionControlActive() {
        XCTAssertFalse(
            FullscreenWindowDetector.isMissionControlActive(
                windowInfos: [fullscreenWindowInfo(ownerName: "Safari")],
                displayBounds: [displayBounds]
            )
        )
    }

    func testSmallDockWindowDoesNotMarkMissionControlActive() {
        XCTAssertFalse(
            FullscreenWindowDetector.isMissionControlActive(
                windowInfos: [
                    windowInfo(
                        ownerName: "Dock",
                        layer: 20,
                        bounds: CGRect(x: 0, y: 820, width: 360, height: 80)
                    ),
                    fullscreenWindowInfo(ownerName: "Safari")
                ],
                displayBounds: [displayBounds]
            )
        )
    }

    private func fullscreenWindowInfo(ownerName: String) -> [String: Any] {
        windowInfo(ownerName: ownerName, layer: 0, bounds: displayBounds)
    }

    private func windowInfo(ownerName: String, layer: Int, bounds: CGRect) -> [String: Any] {
        [
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowOwnerPID as String: NSNumber(value: 99),
            kCGWindowOwnerName as String: ownerName,
            kCGWindowAlpha as String: NSNumber(value: 1.0),
            kCGWindowBounds as String: bounds.dictionaryRepresentation as Any
        ]
    }
}

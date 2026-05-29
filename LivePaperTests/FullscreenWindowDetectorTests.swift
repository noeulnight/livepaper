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
}

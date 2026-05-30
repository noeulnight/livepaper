import XCTest
@testable import LivePaper

final class AerialLockScreenExporterTests: XCTestCase {
    func testSupportsOnlyLocalVideoContent() {
        let exporter = AerialLockScreenExporter()

        XCTAssertTrue(exporter.supportsExport(.video(URL(fileURLWithPath: "/tmp/wallpaper.mov"))))
        XCTAssertFalse(exporter.supportsExport(.web(URL(fileURLWithPath: "/tmp/web/index.html"))))
        XCTAssertFalse(exporter.supportsExport(.webPage(URL(string: "https://example.com")!)))
    }
}

import XCTest
@testable import LivePaper

final class WallpaperEngineImportErrorTests: XCTestCase {
    func testUnsupportedWallpaperTypeExplainsSupportedScope() {
        let message = WallpaperEngineImportError
            .unsupportedWallpaperType("scene")
            .errorDescription ?? ""

        XCTAssertTrue(message.contains("Web and video wallpapers are supported"))
        XCTAssertTrue(message.contains("separate renderer"))
    }

    func testPackageOnlyErrorExplainsRendererRequirement() {
        let message = WallpaperEngineImportError
            .unsupportedPackageOnly
            .errorDescription ?? ""

        XCTAssertTrue(message.contains("package-only items"))
        XCTAssertTrue(message.contains("separate renderer"))
    }
}

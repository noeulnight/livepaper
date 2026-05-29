import XCTest
@testable import LivePaper

final class SteamWorkshopURLTests: XCTestCase {
    func testParsesValidWorkshopURL() throws {
        let workshopURL = try SteamWorkshopURL("https://steamcommunity.com/sharedfiles/filedetails/?id=123456789")

        XCTAssertEqual(workshopURL.itemID, "123456789")
    }

    func testRejectsInvalidHost() {
        XCTAssertThrowsError(try SteamWorkshopURL("https://example.com/sharedfiles/filedetails/?id=123")) { error in
            XCTAssertEqual(error as? SteamWorkshopURLError, .unsupportedURL)
        }
    }

    func testRejectsMissingID() {
        XCTAssertThrowsError(try SteamWorkshopURL("https://steamcommunity.com/sharedfiles/filedetails/")) { error in
            XCTAssertEqual(error as? SteamWorkshopURLError, .missingWorkshopID)
        }
    }

    func testRejectsNonNumericID() {
        XCTAssertThrowsError(try SteamWorkshopURL("https://steamcommunity.com/sharedfiles/filedetails/?id=abc")) { error in
            XCTAssertEqual(error as? SteamWorkshopURLError, .missingWorkshopID)
        }
    }
}

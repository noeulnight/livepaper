import XCTest
@testable import LivePaper

final class WallpaperProfileStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "LivePaperTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testProfilesRoundTrip() {
        let profile = WallpaperProfile(
            name: "Work",
            galleryItemID: "video:file:///work.mp4",
            wallpaperTitle: "Work Loop",
            displayUUIDs: ["uuid-1"],
            restoresPreviousWallpapers: true
        )

        WallpaperProfileStore.saveProfiles([profile], to: defaults)
        let loaded = WallpaperProfileStore.loadProfiles(from: defaults)

        XCTAssertEqual(loaded, [profile])
    }

    func testProfilesLoadSortedByName() {
        let work = WallpaperProfile(name: "Work", galleryItemID: "a", wallpaperTitle: "A")
        let dnd = WallpaperProfile(name: "Calm", galleryItemID: "b", wallpaperTitle: "B")
        let night = WallpaperProfile(name: "night", galleryItemID: "c", wallpaperTitle: "C")

        WallpaperProfileStore.saveProfiles([work, dnd, night], to: defaults)
        let loaded = WallpaperProfileStore.loadProfiles(from: defaults)

        XCTAssertEqual(loaded.map(\.name), ["Calm", "night", "Work"])
    }

    func testActivationRoundTripAssignsIncrementingRevisions() {
        XCTAssertNil(WallpaperProfileStore.loadActivation(from: defaults))

        let first = WallpaperProfileStore.saveActivation(
            WallpaperProfileActivation(profileID: "profile-1"),
            to: defaults
        )
        XCTAssertEqual(first.revision, 1)
        XCTAssertEqual(first.profileID, "profile-1")

        let loaded = WallpaperProfileStore.loadActivation(from: defaults)
        XCTAssertEqual(loaded?.profileID, "profile-1")
        XCTAssertEqual(loaded?.revision, 1)

        let second = WallpaperProfileStore.saveActivation(
            WallpaperProfileActivation(profileID: nil),
            to: defaults
        )
        XCTAssertEqual(second.revision, 2)
        XCTAssertNil(second.profileID)
    }
}

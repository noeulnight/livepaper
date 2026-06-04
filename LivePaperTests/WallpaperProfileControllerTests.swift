import XCTest
@testable import LivePaper

@MainActor
final class WallpaperProfileControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var controller: WallpaperProfileController!

    override func setUp() {
        super.setUp()
        suiteName = "LivePaperTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        controller = WallpaperProfileController(defaults: defaults)
    }

    override func tearDown() {
        controller = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func config(_ uuid: String) -> WallpaperConfig {
        WallpaperConfig(
            displayID: DisplayID(uuid: uuid),
            content: .video(URL(fileURLWithPath: "/tmp/\(uuid).mp4"))
        )
    }

    func testStaleProfilesPrunedWhenGalleryItemDisappears() {
        controller.createProfile(name: "Keep", galleryItemID: "valid", wallpaperTitle: "Keep", restoresPreviousWallpapers: true)
        controller.createProfile(name: "Drop", galleryItemID: "missing", wallpaperTitle: "Drop", restoresPreviousWallpapers: true)

        let remaining = controller.refreshProfiles(validGalleryItemIDs: ["valid"])

        XCTAssertEqual(remaining.map(\.name), ["Keep"])
        XCTAssertEqual(WallpaperProfileStore.loadProfiles(from: defaults).map(\.name), ["Keep"])
    }

    func testActivationRevisionConsumedOnlyOnce() async {
        var handledProfileIDs: [String?] = []
        controller.setActivationHandler { activation in
            handledProfileIDs.append(activation.profileID)
        }

        WallpaperProfileStore.saveActivation(.init(profileID: "a"), to: defaults)
        await controller.consumePendingActivation()
        await controller.consumePendingActivation()

        XCTAssertEqual(handledProfileIDs, ["a"])

        WallpaperProfileStore.saveActivation(.init(profileID: nil), to: defaults)
        await controller.consumePendingActivation()

        XCTAssertEqual(handledProfileIDs, ["a", nil])
    }

    func testSwitchingProfilesKeepsOriginalPreviousConfigsForRestore() {
        let profileA = controller.createProfile(name: "A", galleryItemID: "a", wallpaperTitle: "A", restoresPreviousWallpapers: true)
        let profileB = controller.createProfile(name: "B", galleryItemID: "b", wallpaperTitle: "B", restoresPreviousWallpapers: true)

        let originalConfigs = [DisplayID(uuid: "display-1"): config("display-1")]

        // Apply profile A: snapshot taken.
        let transitionA = controller.prepareApplyTransition(profileID: profileA.id, currentConfigs: originalConfigs)
        controller.markApplied(transitionA)

        // Apply profile B while A is active: snapshot must be preserved.
        let profileBConfigs = [DisplayID(uuid: "display-1"): config("profile-b")]
        let transitionB = controller.prepareApplyTransition(profileID: profileB.id, currentConfigs: profileBConfigs)
        controller.markApplied(transitionB)

        let restore = controller.restorationConfigsForDeactivation()
        XCTAssertEqual(restore, originalConfigs)
    }

    func testRestoreSkippedWhenProfileDisablesRestore() {
        let profile = controller.createProfile(name: "NoRestore", galleryItemID: "a", wallpaperTitle: "A", restoresPreviousWallpapers: false)

        let originalConfigs = [DisplayID(uuid: "display-1"): config("display-1")]
        let transition = controller.prepareApplyTransition(profileID: profile.id, currentConfigs: originalConfigs)
        controller.markApplied(transition)

        XCTAssertNil(controller.restorationConfigsForDeactivation())
    }

    func testTargetDisplaysFallBackFromProfileToActiveToAll() {
        let profile = WallpaperProfile(name: "P", galleryItemID: "a", wallpaperTitle: "A", displayUUIDs: ["d2"])
        let displays = [DisplayID(uuid: "d1"), DisplayID(uuid: "d2"), DisplayID(uuid: "d3")]

        // Profile-specified display wins.
        XCTAssertEqual(
            controller.targetDisplayIDs(for: profile, displays: displays, activeDisplayIDs: [DisplayID(uuid: "d1")]),
            [DisplayID(uuid: "d2")]
        )

        // No profile displays -> active displays.
        let noDisplayProfile = WallpaperProfile(name: "P", galleryItemID: "a", wallpaperTitle: "A")
        XCTAssertEqual(
            controller.targetDisplayIDs(for: noDisplayProfile, displays: displays, activeDisplayIDs: [DisplayID(uuid: "d1")]),
            [DisplayID(uuid: "d1")]
        )

        // No profile displays and none active -> all available.
        XCTAssertEqual(
            controller.targetDisplayIDs(for: noDisplayProfile, displays: displays, activeDisplayIDs: []),
            Set(displays)
        )
    }
}

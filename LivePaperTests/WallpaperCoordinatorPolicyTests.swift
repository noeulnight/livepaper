import XCTest
@testable import LivePaper

@MainActor
final class WallpaperCoordinatorPolicyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "LivePaperPolicyTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

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

    func testApplyingWallpaperWhileManuallyPausedLoadsNewConfigAndRemainsPaused() async throws {
        let runtime = RecordingWallpaperRuntime()
        let coordinator = WallpaperCoordinator(
            runtime: runtime,
            store: WallpaperSettingsStore(defaults: defaults),
            loginItemController: LoginItemController(service: PolicyTestLoginItemService())
        )
        guard let displayID = coordinator.displays.first?.id else {
            throw XCTSkip("No display available in test environment.")
        }

        coordinator.applyLockScreenAutomatically = false
        coordinator.selectedDisplayIDs = [displayID]
        let firstURL = URL(string: "https://example.com/first")!
        coordinator.selectWebPage(url: firstURL)
        await coordinator.applySelectedContent()

        await coordinator.pauseDisplay(displayID)
        let pauseCallCount = runtime.pauseCalls.count
        let eventCount = runtime.events.count

        let secondURL = URL(string: "https://example.com/second")!
        coordinator.selectWebPage(url: secondURL)
        await coordinator.applySelectedContent()
        let applyEvents = Array(runtime.events.dropFirst(eventCount))

        XCTAssertEqual(runtime.updateCalls.last?.content.url, secondURL)
        XCTAssertGreaterThan(runtime.pauseCalls.count, pauseCallCount)
        XCTAssertTrue(applyEvents.contains("update:\(secondURL.absoluteString)"))
        XCTAssertTrue(applyEvents.last?.hasPrefix("pause:") == true)
        XCTAssertTrue(coordinator.isDisplayPaused(displayID))
    }
}

private struct PolicyTestLoginItemService: LoginItemServiceManaging {
    var status: LoginItemStatus.RegistrationStatus { .notRegistered }
    func register() throws {}
    func unregister() throws {}
}

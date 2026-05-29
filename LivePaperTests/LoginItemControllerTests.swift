import XCTest
@testable import LivePaper

final class LoginItemControllerTests: XCTestCase {
    func testStatusReflectsServiceStatus() {
        let service = StubLoginItemService(status: .requiresApproval)
        let controller = LoginItemController(service: service)

        let status = controller.status()

        XCTAssertEqual(status.registrationStatus, .requiresApproval)
        XCTAssertTrue(status.isRegistered)
        XCTAssertTrue(status.requiresApproval)
    }

    func testSetEnabledRegistersService() throws {
        let service = StubLoginItemService(status: .notRegistered)
        let controller = LoginItemController(service: service)

        try controller.setEnabled(true)

        XCTAssertEqual(service.actions, [.register])
    }

    func testSetDisabledUnregistersService() throws {
        let service = StubLoginItemService(status: .enabled)
        let controller = LoginItemController(service: service)

        try controller.setEnabled(false)

        XCTAssertEqual(service.actions, [.unregister])
    }
}

private final class StubLoginItemService: LoginItemServiceManaging {
    enum Action: Equatable {
        case register
        case unregister
    }

    var status: LoginItemStatus.RegistrationStatus
    private(set) var actions: [Action] = []

    init(status: LoginItemStatus.RegistrationStatus) {
        self.status = status
    }

    func register() throws {
        actions.append(.register)
        status = .enabled
    }

    func unregister() throws {
        actions.append(.unregister)
        status = .notRegistered
    }
}

import Foundation
import ServiceManagement

struct LoginItemStatus: Equatable {
    enum RegistrationStatus: Equatable {
        case notRegistered
        case enabled
        case requiresApproval
        case notFound
    }

    let registrationStatus: RegistrationStatus

    var isRegistered: Bool {
        registrationStatus == .enabled || registrationStatus == .requiresApproval
    }

    var requiresApproval: Bool {
        registrationStatus == .requiresApproval
    }
}

protocol LoginItemServiceManaging {
    var status: LoginItemStatus.RegistrationStatus { get }
    func register() throws
    func unregister() throws
}

final class LoginItemController {
    private let service: LoginItemServiceManaging

    init(service: LoginItemServiceManaging = MainAppLoginItemService()) {
        self.service = service
    }

    func status() -> LoginItemStatus {
        LoginItemStatus(registrationStatus: service.status)
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}

private struct MainAppLoginItemService: LoginItemServiceManaging {
    var status: LoginItemStatus.RegistrationStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

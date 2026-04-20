import Foundation
import ServiceManagement

final class LoginItemService {
    enum LoginItemServiceError: LocalizedError {
        case unsupportedStatus

        var errorDescription: String? {
            switch self {
            case .unsupportedStatus:
                return "macOS could not determine the launch-at-login status for this build."
            }
        }
    }

    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Needs approval in Login Items settings"
        case .notFound:
            return "The app needs to be installed in /Applications before macOS can keep it registered."
        case .notRegistered:
            return "Disabled"
        @unknown default:
            return "Unknown"
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

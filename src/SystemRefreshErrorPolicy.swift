import Foundation

enum SystemRefreshErrorPolicy {
    static func shouldTreatAsRefreshedSystemState(_ error: Error) -> Bool {
        guard let pulseError = error as? PulseError else {
            return false
        }

        switch pulseError {
        case .invalidAuthFile:
            return true
        case .invalidSessionToken, .invalidUsageResponse, .workspaceListUnavailable:
            return false
        }
    }
}

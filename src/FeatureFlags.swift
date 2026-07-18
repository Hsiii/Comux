import Foundation

enum FeatureFlags {
    static let supportsFiveHourLimit = fiveHourLimitSupportEnabled()

    static func fiveHourLimitSupportEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard let rawValue = environment["COMUX_SUPPORTS_FIVE_HOUR_LIMIT"] else {
            return false
        }

        return ["1", "true", "yes", "on"].contains(rawValue.lowercased())
    }
}

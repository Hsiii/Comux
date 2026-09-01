import Foundation

enum UsageWindowScope: String, Codable, Sendable {
    case shortHorizon
    case longHorizon
    case unknown
}

struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let scope: UsageWindowScope
    let durationSeconds: Int?
    let available: Bool
    let label: String
    let usedMinutes: Int
    let limitMinutes: Int
    let usedPercentage: Double
    let resetsAt: String

    init(
        id: String? = nil,
        scope: UsageWindowScope = .unknown,
        durationSeconds: Int? = nil,
        available: Bool,
        label: String,
        usedMinutes: Int,
        limitMinutes: Int,
        usedPercentage: Double,
        resetsAt: String
    ) {
        self.id = id ?? Self.legacyID(for: label)
        self.scope = scope
        self.durationSeconds = durationSeconds
        self.available = available
        self.label = label
        self.usedMinutes = usedMinutes
        self.limitMinutes = limitMinutes
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    var remainingMinutes: Int {
        max(limitMinutes - usedMinutes, 0)
    }

    func withMetadata(
        id: String,
        scope: UsageWindowScope,
        durationSeconds: Int?
    ) -> UsageWindow {
        UsageWindow(
            id: id,
            scope: scope,
            durationSeconds: durationSeconds,
            available: self.available,
            label: self.label,
            usedMinutes: self.usedMinutes,
            limitMinutes: self.limitMinutes,
            usedPercentage: self.usedPercentage,
            resetsAt: self.resetsAt
        )
    }

    static func unavailable(scope: UsageWindowScope) -> UsageWindow {
        UsageWindow(
            id: "unavailable-\(scope.rawValue)",
            scope: scope,
            available: false,
            label: "Usage window",
            usedMinutes: 0,
            limitMinutes: 0,
            usedPercentage: 0,
            resetsAt: ""
        )
    }

    private static func legacyID(for label: String) -> String {
        let normalized = label
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalized.isEmpty ? "usage-window" : normalized
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case scope
        case durationSeconds
        case available
        case label
        case usedMinutes
        case limitMinutes
        case usedPercentage
        case resetsAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let label = try container.decode(String.self, forKey: .label)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            scope: try container.decodeIfPresent(UsageWindowScope.self, forKey: .scope) ?? .unknown,
            durationSeconds: try container.decodeIfPresent(Int.self, forKey: .durationSeconds),
            available: try container.decode(Bool.self, forKey: .available),
            label: label,
            usedMinutes: try container.decode(Int.self, forKey: .usedMinutes),
            limitMinutes: try container.decode(Int.self, forKey: .limitMinutes),
            usedPercentage: try container.decode(Double.self, forKey: .usedPercentage),
            resetsAt: try container.decode(String.self, forKey: .resetsAt)
        )
    }
}

struct CodexResetCredits: Codable, Equatable, Sendable {
    let availableCount: Int
    let nextExpiresAt: String?
    let updatedAt: String
}

struct AccountSnapshot: Codable, Identifiable, Sendable {
    let accountId: String
    let label: String
    let email: String
    let workspaceId: String?
    let workspaceLabel: String
    let plan: String
    let source: String
    let systemAuthProfileId: String?
    let isCurrentSystemAccount: Bool?
    let lastSyncedAt: String
    let usageWindows: [UsageWindow]
    let resetCredits: CodexResetCredits?

    var id: String { self.accountId }

    var longHorizonWindow: UsageWindow? {
        let windows = self.usageWindows.filter { $0.scope == .longHorizon }
        return windows
            .filter(\.available)
            .max { ($0.durationSeconds ?? 0) < ($1.durationSeconds ?? 0) }
            ?? windows.max { ($0.durationSeconds ?? 0) < ($1.durationSeconds ?? 0) }
    }

    var shortHorizonWindow: UsageWindow? {
        let windows = self.usageWindows.filter { $0.scope == .shortHorizon }
        return windows
            .filter(\.available)
            .min { ($0.durationSeconds ?? .max) < ($1.durationSeconds ?? .max) }
            ?? windows.min { ($0.durationSeconds ?? .max) < ($1.durationSeconds ?? .max) }
    }

    var fiveHourWindow: UsageWindow? {
        let fiveHours = 5 * 60 * 60
        let windows = self.usageWindows.filter { window in
            window.durationSeconds == fiveHours
                || window.label.localizedCaseInsensitiveContains("5-hour")
                || window.label.localizedCaseInsensitiveContains("5h")
        }
        return windows.first(where: \.available) ?? windows.first
    }

    var primaryUsageWindow: UsageWindow {
        self.longHorizonWindow
            ?? self.usageWindows.first(where: \.available)
            ?? self.usageWindows.first
            ?? UsageWindow.unavailable(scope: .longHorizon)
    }

    var weeklyWindow: UsageWindow {
        self.longHorizonWindow ?? UsageWindow.unavailable(scope: .longHorizon)
    }

    var rollingWindow: UsageWindow {
        self.shortHorizonWindow ?? UsageWindow.unavailable(scope: .shortHorizon)
    }

    init(
        accountId: String,
        label: String,
        email: String,
        workspaceId: String?,
        workspaceLabel: String,
        plan: String,
        source: String,
        systemAuthProfileId: String?,
        isCurrentSystemAccount: Bool?,
        lastSyncedAt: String,
        weeklyWindow: UsageWindow,
        rollingWindow: UsageWindow,
        resetCredits: CodexResetCredits? = nil
    ) {
        self.accountId = accountId
        self.label = label
        self.email = email
        self.workspaceId = workspaceId
        self.workspaceLabel = workspaceLabel
        self.plan = plan
        self.source = source
        self.systemAuthProfileId = systemAuthProfileId
        self.isCurrentSystemAccount = isCurrentSystemAccount
        self.lastSyncedAt = lastSyncedAt
        self.usageWindows = [
            weeklyWindow.withMetadata(
                id: "legacy-weekly",
                scope: .longHorizon,
                durationSeconds: weeklyWindow.durationSeconds ?? 7 * 24 * 60 * 60
            ),
            rollingWindow.withMetadata(
                id: "legacy-rolling",
                scope: .shortHorizon,
                durationSeconds: rollingWindow.durationSeconds ?? 5 * 60 * 60
            ),
        ]
        self.resetCredits = resetCredits
    }

    init(
        accountId: String,
        label: String,
        email: String,
        workspaceId: String?,
        workspaceLabel: String,
        plan: String,
        source: String,
        systemAuthProfileId: String?,
        isCurrentSystemAccount: Bool?,
        lastSyncedAt: String,
        usageWindows: [UsageWindow],
        resetCredits: CodexResetCredits? = nil
    ) {
        self.accountId = accountId
        self.label = label
        self.email = email
        self.workspaceId = workspaceId
        self.workspaceLabel = workspaceLabel
        self.plan = plan
        self.source = source
        self.systemAuthProfileId = systemAuthProfileId
        self.isCurrentSystemAccount = isCurrentSystemAccount
        self.lastSyncedAt = lastSyncedAt
        self.usageWindows = usageWindows
        self.resetCredits = resetCredits
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case label
        case email
        case workspaceId
        case workspaceLabel
        case plan
        case source
        case systemAuthProfileId
        case isCurrentSystemAccount
        case lastSyncedAt
        case usageWindows
        case weeklyWindow
        case rollingWindow
        case resetCredits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let genericWindows = try container.decodeIfPresent([UsageWindow].self, forKey: .usageWindows)
        let legacyWeekly = try container.decodeIfPresent(UsageWindow.self, forKey: .weeklyWindow)
        let legacyRolling = try container.decodeIfPresent(UsageWindow.self, forKey: .rollingWindow)
        let windows: [UsageWindow]

        if let genericWindows, !genericWindows.isEmpty {
            windows = genericWindows
        } else {
            windows = [
                legacyWeekly?.withMetadata(
                    id: "legacy-weekly",
                    scope: .longHorizon,
                    durationSeconds: legacyWeekly?.durationSeconds ?? 7 * 24 * 60 * 60
                ),
                legacyRolling?.withMetadata(
                    id: "legacy-rolling",
                    scope: .shortHorizon,
                    durationSeconds: legacyRolling?.durationSeconds ?? 5 * 60 * 60
                ),
            ].compactMap { $0 }
        }

        self.init(
            accountId: try container.decode(String.self, forKey: .accountId),
            label: try container.decode(String.self, forKey: .label),
            email: try container.decode(String.self, forKey: .email),
            workspaceId: try container.decodeIfPresent(String.self, forKey: .workspaceId),
            workspaceLabel: try container.decode(String.self, forKey: .workspaceLabel),
            plan: try container.decode(String.self, forKey: .plan),
            source: try container.decode(String.self, forKey: .source),
            systemAuthProfileId: try container.decodeIfPresent(String.self, forKey: .systemAuthProfileId),
            isCurrentSystemAccount: try container.decodeIfPresent(Bool.self, forKey: .isCurrentSystemAccount),
            lastSyncedAt: try container.decode(String.self, forKey: .lastSyncedAt),
            usageWindows: windows,
            resetCredits: try container.decodeIfPresent(CodexResetCredits.self, forKey: .resetCredits)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.accountId, forKey: .accountId)
        try container.encode(self.label, forKey: .label)
        try container.encode(self.email, forKey: .email)
        try container.encodeIfPresent(self.workspaceId, forKey: .workspaceId)
        try container.encode(self.workspaceLabel, forKey: .workspaceLabel)
        try container.encode(self.plan, forKey: .plan)
        try container.encode(self.source, forKey: .source)
        try container.encodeIfPresent(self.systemAuthProfileId, forKey: .systemAuthProfileId)
        try container.encodeIfPresent(self.isCurrentSystemAccount, forKey: .isCurrentSystemAccount)
        try container.encode(self.lastSyncedAt, forKey: .lastSyncedAt)
        try container.encode(self.usageWindows, forKey: .usageWindows)
        try container.encode(self.weeklyWindow, forKey: .weeklyWindow)
        try container.encode(self.rollingWindow, forKey: .rollingWindow)
        try container.encodeIfPresent(self.resetCredits, forKey: .resetCredits)
    }
}

struct CacheMeta: Codable {
    let source: String
}

struct CachePayload: Codable {
    let meta: CacheMeta
    let accounts: [AccountSnapshot]
}

struct AccountConfig: Codable, Identifiable, Sendable {
    let id: String
    let label: String
    let email: String
    let workspaceLabel: String
    let plan: String
    let color: String
    let chatGPTCookie: String
    let source: String?
    let sessionEndpoint: String?
    let usageEndpoint: String?
    let accountHeader: String?
}

struct PulseConfig: Codable {
    let pollIntervalSeconds: Double
    let accounts: [AccountConfig]

    static let `default` = PulseConfig(
        pollIntervalSeconds: 300,
        accounts: []
    )
}

struct SystemAuthIdentity: Sendable {
    let accessToken: String
    let accountId: String?
    let email: String?
    let name: String?
    let planType: String?
    let organizationTitles: [String]
    let subject: String?
}

func normalizedSystemAuthProfileID(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
        return nil
    }

    return trimmed.lowercased()
}

struct WorkspaceIdentity: Decodable {
    let items: [WorkspaceItem]
}

struct WorkspaceItem: Decodable, Sendable {
    let id: String
    let name: String?
}

enum PulseError: Error, LocalizedError, Equatable {
    case invalidAuthFile
    case invalidSessionToken
    case invalidUsageResponse
    case workspaceListUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidAuthFile:
            return "Local Codex auth could not be parsed."
        case .invalidSessionToken:
            return "ChatGPT session cookie did not yield an access token."
        case .invalidUsageResponse:
            return "Usage endpoint did not contain enough fields to normalize."
        case .workspaceListUnavailable:
            return "Workspace list could not be loaded."
        }
    }
}

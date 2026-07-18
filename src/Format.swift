import SwiftUI

func parseISO8601Date(_ value: String) -> Date? {
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractionalFormatter.date(from: value) {
        return date
    }

    return ISO8601DateFormatter().date(from: value)
}

func formatCountdown(_ value: String, now: Date = Date()) -> String {
    guard let date = parseISO8601Date(value) else {
        return "n/a"
    }

    let diff = Int(date.timeIntervalSince(now))

    if diff <= 0 {
        return "just reset"
    }

    let minutes = diff / 60
    let days = minutes / (24 * 60)
    let hours = (minutes % (24 * 60)) / 60
    let remainingMinutes = minutes % 60

    if days > 0 {
        return "\(days)d \(hours)h"
    }

    if hours > 0 {
        return "\(hours)h \(remainingMinutes)m"
    }

    return "\(remainingMinutes)m"
}

func formatRelative(_ value: String) -> String {
    guard let date = parseISO8601Date(value) else {
        return value
    }

    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}

func clampPercentage(_ value: Double) -> Double {
    min(100, max(0, value))
}

func remainingPercentage(for window: UsageWindow) -> Int {
    Int(round(clampPercentage(100 - window.usedPercentage)))
}

func hasJustReset(_ window: UsageWindow, now: Date = Date()) -> Bool {
    guard let resetDate = parseISO8601Date(window.resetsAt) else {
        return false
    }

    return resetDate <= now
}

func displayRemainingPercentage(for window: UsageWindow, now: Date = Date()) -> Int {
    hasJustReset(window, now: now) ? 100 : remainingPercentage(for: window)
}

func percentageText(for window: UsageWindow, now: Date = Date()) -> String {
    guard window.available else {
        return "No seat"
    }

    return "\(displayRemainingPercentage(for: window, now: now))%"
}

func currentUsageDelta(for window: UsageWindow, now: Date = Date()) -> Int {
    guard window.available,
          !hasJustReset(window, now: now),
          !isFreshResetWindow(window, now: now)
    else {
        return 0
    }

    return displayRemainingPercentage(for: window, now: now)
        - Int(round(expectedRemainingPercentage(for: window, now: now)))
}

func usageHeadlineText(for window: UsageWindow, now: Date = Date()) -> String {
    guard window.available else {
        return percentageText(for: window, now: now)
    }

    return "\(percentageText(for: window, now: now))\(usageDeltaText(for: window, now: now) ?? "")"
}

func usageDeltaText(for window: UsageWindow, now: Date = Date()) -> String? {
    guard window.available,
          !hasJustReset(window, now: now),
          !isFreshResetWindow(window, now: now),
          displayRemainingPercentage(for: window, now: now) < 100
    else {
        return nil
    }

    let delta = currentUsageDelta(for: window, now: now)
    let signedDelta = delta > 0 ? "+\(delta)%" : "\(delta)%"
    return " (\(signedDelta))"
}

func primaryMenuBarAccount(from accounts: [AccountSnapshot]) -> AccountSnapshot? {
    accounts
        .filter({ account in
            account.isCurrentSystemAccount == true
                && account.primaryUsageWindow.available
        })
        .sorted(by: { left, right in
            let leftDate = ISO8601DateFormatter().date(from: left.lastSyncedAt) ?? .distantPast
            let rightDate = ISO8601DateFormatter().date(from: right.lastSyncedAt) ?? .distantPast
            return leftDate > rightDate
        })
        .first
}

func menuBarUsageText(from accounts: [AccountSnapshot]) -> String? {
    guard let account = primaryMenuBarAccount(from: accounts) else {
        return nil
    }

    return usageHeadlineText(for: account.primaryUsageWindow)
}

func usageWindowResetText(for window: UsageWindow, now: Date = Date()) -> String {
    if hasJustReset(window, now: now) || isFreshResetWindow(window, now: now) {
        return "Fresh"
    }

    return "Resets in \(formatCountdown(window.resetsAt, now: now))"
}

func resetPaceText(for window: UsageWindow) -> String {
    guard window.available else {
        return "No usage access"
    }

    if hasJustReset(window) {
        return "Fresh"
    }

    if displayRemainingPercentage(for: window) == 0 {
        return "Used up • Resets in \(formatCountdown(window.resetsAt))"
    }

    let delta = currentExpectationDelta(for: window)
    let deltaText = delta > 0 ? "+\(delta)%" : "\(delta)%"
    return "\(deltaText) • Resets in \(formatCountdown(window.resetsAt))"
}

func resetCreditsSummaryText(for resetCredits: CodexResetCredits?) -> String? {
    guard let resetCredits else {
        return nil
    }

    guard resetCredits.availableCount > 0 else {
        return "No resets available"
    }

    let availableText = resetCredits.availableCount == 1
        ? "1 reset available"
        : "\(resetCredits.availableCount) resets available"

    guard let nextExpiresAt = resetCredits.nextExpiresAt,
          let expiryDate = parseISO8601Date(nextExpiresAt),
          expiryDate > Date()
    else {
        return availableText
    }

    return "\(availableText) • next expires in \(formatCountdown(nextExpiresAt))"
}

func currentExpectationDelta(for window: UsageWindow) -> Int {
    displayRemainingPercentage(for: window) - Int(round(expectedRemainingPercentage(for: window)))
}

func displayWindowLabel(for window: UsageWindow) -> String {
    if let durationSeconds = window.durationSeconds, durationSeconds > 0 {
        let day = 24 * 60 * 60
        let hour = 60 * 60

        if durationSeconds == 7 * day {
            return "Weekly"
        }

        if durationSeconds.isMultiple(of: day) {
            return "\(durationSeconds / day)d"
        }

        if durationSeconds.isMultiple(of: hour) {
            return "\(durationSeconds / hour)h"
        }
    }

    let label = window.label.lowercased()

    if label.contains("30-day") || label.contains("30d") || label.contains("monthly") {
        return "30d"
    }

    if label.contains("week") {
        return "Weekly"
    }

    if label.contains("5-hour") || label.contains("5h") {
        return "5h"
    }

    return window.label
}

func isPersonalPlan(_ plan: String) -> Bool {
    let normalized = plan.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.contains("free")
        || normalized.contains("plus")
        || normalized.contains("pro")
        || normalized.contains("personal")
}

func isTeamPlan(_ plan: String) -> Bool {
    let normalized = plan.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.contains("team")
}

func normalizedWorkspaceLabel(_ workspaceLabel: String, plan: String) -> String {
    let trimmed = workspaceLabel.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.caseInsensitiveCompare("free") == .orderedSame {
        return "Personal"
    }

    if trimmed.isEmpty && isPersonalPlan(plan) {
        return "Personal"
    }

    return trimmed
}

func normalizedPlanLabel(_ plan: String, workspaceLabel: String) -> String {
    let trimmedPlan = plan.trimmingCharacters(in: .whitespacesAndNewlines)

    if workspaceLabel == "Personal" && isTeamPlan(trimmedPlan) {
        return "Codex Personal"
    }

    return trimmedPlan
}

func tierLabel(for plan: String) -> String {
    let normalized = plan.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    if normalized.contains("team") {
        return "Team"
    }

    if normalized.contains("free") {
        return "Free"
    }

    if normalized.contains("plus") {
        return "Plus"
    }

    if normalized.contains("pro") {
        return "Pro"
    }

    if normalized.contains("personal") {
        return "Personal"
    }

    if normalized.hasPrefix("codex ") {
        return String(plan.dropFirst(6))
    }

    return plan
}

func accountTierText(for account: AccountSnapshot) -> String {
    let tier = tierLabel(for: account.plan)
    let workspace = normalizedWorkspaceLabel(account.workspaceLabel, plan: account.plan)

    if workspace == "Ambient ~/.codex session" {
        return tier
    }

    if workspace == "Personal" {
        return tier
    }

    if tier == "Team" && !workspace.isEmpty {
        return "Team \(workspace)"
    }

    return workspace.isEmpty ? tier : workspace
}

func compactAccountTag(for account: AccountSnapshot) -> String? {
    accountTierText(for: account)
}

func resetCreditsCountText(for resetCredits: CodexResetCredits?) -> String {
    guard let resetCredits else {
        return "No resets"
    }

    switch resetCredits.availableCount {
    case ...0:
        return "No resets"
    case 1:
        return "1 reset available"
    default:
        return "\(resetCredits.availableCount) resets available"
    }
}

func resetCreditsExpiryText(
    for resetCredits: CodexResetCredits?,
    now: Date = Date()
) -> String? {
    guard let resetCredits,
          resetCredits.availableCount > 0,
          let nextExpiresAt = resetCredits.nextExpiresAt,
          let expiryDate = parseISO8601Date(nextExpiresAt),
          expiryDate > now
    else {
        return nil
    }

    return "Next reset expires in \(formatCountdown(nextExpiresAt, now: now))"
}

func windowDuration(for window: UsageWindow) -> TimeInterval? {
    if let durationSeconds = window.durationSeconds, durationSeconds > 0 {
        return TimeInterval(durationSeconds)
    }

    let label = window.label.lowercased()

    if label.contains("30-day") || label.contains("30d") || label.contains("monthly") {
        return 30 * 24 * 60 * 60
    }

    if label.contains("week") {
        return 7 * 24 * 60 * 60
    }

    if label.contains("5-hour") || label.contains("5h") {
        return 5 * 60 * 60
    }

    return nil
}

func expectedRemainingPercentage(for window: UsageWindow, now: Date = Date()) -> Double {
    guard window.available,
          let duration = windowDuration(for: window),
          let resetDate = parseISO8601Date(window.resetsAt)
    else {
        return 0
    }

    let startDate = resetDate.addingTimeInterval(-duration)
    let elapsed = now.timeIntervalSince(startDate)
    return clampPercentage(100 - ((elapsed / duration) * 100))
}

func isFreshResetWindow(_ window: UsageWindow, now: Date = Date()) -> Bool {
    guard window.available,
          window.usedMinutes == 0,
          remainingPercentage(for: window) == 100,
          let resetDate = parseISO8601Date(window.resetsAt)
    else {
        return false
    }

    return resetDate <= now
}

func isUsageWindowLocked(_ window: UsageWindow) -> Bool {
    window.available && remainingPercentage(for: window) == 0 && !hasJustReset(window)
}

func shouldShowShortHorizonLock(
    for account: AccountSnapshot,
    supportsFiveHourLimit: Bool = FeatureFlags.supportsFiveHourLimit
) -> Bool {
    supportsFiveHourLimit
        && isUsageWindowLocked(account.rollingWindow)
        && displayRemainingPercentage(for: account.primaryUsageWindow) > 0
}

func sortedAccountsByHeadroom(
    _ accounts: [AccountSnapshot],
    displayName: (AccountSnapshot) -> String
) -> [AccountSnapshot] {
    return accounts.sorted { left, right in
        let leftWindow = left.primaryUsageWindow
        let rightWindow = right.primaryUsageWindow
        let leftCurrent = displayRemainingPercentage(for: leftWindow)
        let rightCurrent = displayRemainingPercentage(for: rightWindow)
        let leftIsFull = leftCurrent == 100
        let rightIsFull = rightCurrent == 100
        let leftIsEmpty = leftCurrent == 0
        let rightIsEmpty = rightCurrent == 0

        if leftIsFull != rightIsFull {
            return leftIsFull
        }

        if leftIsFull && rightIsFull {
            let leftIsPaid = !isPersonalPlan(left.plan)
            let rightIsPaid = !isPersonalPlan(right.plan)

            if leftIsPaid != rightIsPaid {
                return leftIsPaid
            }
        }

        if leftIsEmpty != rightIsEmpty {
            return !leftIsEmpty
        }

        let leftDelta = currentExpectationDelta(for: leftWindow)
        let rightDelta = currentExpectationDelta(for: rightWindow)

        if leftDelta != rightDelta {
            return leftDelta > rightDelta
        }

        if leftCurrent != rightCurrent {
            return leftCurrent > rightCurrent
        }

        let leftDate = parseISO8601Date(leftWindow.resetsAt)
        let rightDate = parseISO8601Date(rightWindow.resetsAt)

        switch (leftDate, rightDate) {
        case let (leftDate?, rightDate?) where leftDate != rightDate:
            return leftDate < rightDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return displayName(left).localizedCaseInsensitiveCompare(displayName(right)) == .orderedAscending
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let red = Double((int >> 16) & 0xFF) / 255
        let green = Double((int >> 8) & 0xFF) / 255
        let blue = Double(int & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

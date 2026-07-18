import AppKit
import SwiftUI

private let accountCardHeight: CGFloat = 80
private let accountCardCornerRadius: CGFloat = 16

enum WindowHeaderPlacement {
    case above
    case below
    case hidden
}

struct WindowCardView: View {
    let window: UsageWindow
    let compact: Bool
    let isLocked: Bool
    let headerPlacement: WindowHeaderPlacement

    init(
        window: UsageWindow,
        compact: Bool,
        isLocked: Bool,
        headerPlacement: WindowHeaderPlacement = .above
    ) {
        self.window = window
        self.compact = compact
        self.isLocked = isLocked
        self.headerPlacement = headerPlacement
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            if headerPlacement == .above {
                header
            }

            bar

            if headerPlacement == .below {
                header
            }
        }
    }

    private var header: some View {
        HStack {
            Text(displayWindowLabel(for: window))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(resetPaceText(for: window))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var bar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                barShape
                    .fill(Color.white.opacity(0.08))

                if showsExpectedOverlay {
                    barFill
                        .frame(width: geometry.size.width)
                        .mask(alignment: .leading) {
                            segmentRangeMask(
                                totalWidth: geometry.size.width,
                                startFraction: 0,
                                endFraction: currentFraction,
                                roundTrailing: true
                            )
                        }

                    expectedBehindFill
                        .frame(width: geometry.size.width)
                        .mask(alignment: .leading) {
                            segmentRangeMask(
                                totalWidth: geometry.size.width,
                                startFraction: 0,
                                endFraction: expectedFraction,
                                roundTrailing: true
                            )
                        }
                } else {
                    expectedFill
                        .frame(width: geometry.size.width)
                        .mask(alignment: .leading) {
                            segmentRangeMask(
                                totalWidth: geometry.size.width,
                                startFraction: 0,
                                endFraction: expectedFraction,
                                roundTrailing: true
                            )
                        }

                    barFill
                        .frame(width: geometry.size.width)
                        .mask(alignment: .leading) {
                            segmentRangeMask(
                                totalWidth: geometry.size.width,
                                startFraction: 0,
                                endFraction: currentFraction,
                                roundTrailing: true
                            )
                        }
                }
            }
        }
        .frame(height: compact ? 8 : 14)
        .opacity(window.available ? 1 : 0)
    }

    private var barFill: some View {
        Group {
            if isLocked {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.32),
                        Color.white.opacity(0.2),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.46, green: 0.56, blue: 0.98),
                        Color(red: 0.54, green: 0.36, blue: 0.78),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var showsExpectedOverlay: Bool {
        expectedRemainingPercentage(for: window) < Double(displayRemainingPercentage(for: window))
    }

    private var currentFraction: CGFloat {
        CGFloat(Double(displayRemainingPercentage(for: window)) / 100)
    }

    private var expectedFraction: CGFloat {
        CGFloat(expectedRemainingPercentage(for: window) / 100)
    }

    private var expectedBarColor: Color {
        Color.white.opacity(0.24)
    }

    private var barShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 999)
    }

    private func segmentRangeMask(
        totalWidth: CGFloat,
        startFraction: CGFloat,
        endFraction: CGFloat,
        roundTrailing: Bool
    ) -> some View {
        let start = min(1, max(0, startFraction))
        let end = min(1, max(start, endFraction))
        let startWidth = totalWidth * start
        let segmentWidth = totalWidth * (end - start)
        let trailingWidth = max(totalWidth - startWidth - segmentWidth, 0)

        return HStack(spacing: 0) {
            Color.clear
                .frame(width: startWidth)

            UnevenRoundedRectangle(
                topLeadingRadius: start == 0 ? 999 : 0,
                bottomLeadingRadius: start == 0 ? 999 : 0,
                bottomTrailingRadius: roundTrailing ? 999 : 0,
                topTrailingRadius: roundTrailing ? 999 : 0,
                style: .continuous
            )
            .fill(Color.white)
            .frame(width: max(segmentWidth, 0))

            Color.clear
                .frame(width: trailingWidth)
        }
        .frame(width: totalWidth, alignment: .leading)
    }

    private var expectedFill: some View {
        barShape
            .fill(expectedBarColor)
    }

    private var expectedBehindFill: some View {
        barShape
            .fill(Color.white.opacity(isLocked ? 0.12 : 0.14))
    }
}

struct RollingUsageInlineView: View {
    let window: UsageWindow
    let size: CGFloat

    private var currentFraction: CGFloat {
        CGFloat(Double(displayRemainingPercentage(for: window)) / 100)
    }

    private var expectedFraction: CGFloat {
        CGFloat(expectedRemainingPercentage(for: window) / 100)
    }

    private var showsExpectedOverlay: Bool {
        expectedRemainingPercentage(for: window) < Double(displayRemainingPercentage(for: window))
    }

    private var lineWidth: CGFloat {
        max(1.75, size * 0.16)
    }

    private var expectedRing: some View {
        Circle()
            .trim(from: 0, to: expectedFraction)
            .stroke(
                Color.white.opacity(0.28),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
    }

    private var currentRing: some View {
        Circle()
            .trim(from: 0, to: currentFraction)
            .stroke(
                Color.white.opacity(isUsageWindowLocked(window) ? 0.66 : 0.92),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
    }

    private var brightCurrentRing: some View {
        Circle()
            .trim(from: 0, to: currentFraction)
            .stroke(
                Color(red: 0.72, green: 0.72, blue: 0.76),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .overlay {
                currentRing
            }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)

            expectedRing

            if showsExpectedOverlay {
                brightCurrentRing
            } else {
                currentRing
            }
        }
        .frame(width: size, height: size)
        .opacity(window.available ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage window")
        .accessibilityValue(usageWindowResetText(for: window) + ", " + percentageText(for: window) + " remaining")
    }
}

struct HeaderIdentityClusterView: View {
    let displayName: String
    let rollingWindow: UsageWindow
    let nameFont: Font
    let clusterWidth: CGFloat
    let ringSize: CGFloat
    let spacing: CGFloat

    private var lockCountdownSpacing: CGFloat {
        spacing / 2
    }

    private var truncatedDisplayName: String {
        String(displayName.prefix(12))
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            Text(truncatedDisplayName)
                .font(nameFont)
                .lineLimit(1)

            if isUsageWindowLocked(rollingWindow) {
                HStack(alignment: .firstTextBaseline, spacing: lockCountdownSpacing) {
                    Image(systemName: "lock.fill")
                        .font(nameFont.weight(.semibold))

                    Text(formatCountdown(rollingWindow.resetsAt))
                        .font(nameFont)
                        .lineLimit(1)
                }
                .foregroundStyle(Color.white.opacity(0.5))
            }

            Spacer(minLength: 8)
        }
        .frame(width: clusterWidth, alignment: .leading)
    }
}

struct UsageSurfaceView<Content: View>: View {
    let window: UsageWindow
    let isLocked: Bool
    let isActive: Bool
    let isHovered: Bool
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    let contentInsets: EdgeInsets
    @ViewBuilder let content: Content

    init(
        window: UsageWindow,
        isLocked: Bool,
        isActive: Bool,
        isHovered: Bool = false,
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat,
        contentInsets: EdgeInsets,
        @ViewBuilder content: () -> Content
    ) {
        self.window = window
        self.isLocked = isLocked
        self.isActive = isActive
        self.isHovered = isHovered
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.contentInsets = contentInsets
        self.content = content()
    }

    private var currentFraction: CGFloat {
        CGFloat(Double(displayRemainingPercentage(for: window)) / 100)
    }

    private var expectedFraction: CGFloat {
        CGFloat(expectedRemainingPercentage(for: window) / 100)
    }

    private var showsExpectedOverlay: Bool {
        expectedRemainingPercentage(for: window) < Double(displayRemainingPercentage(for: window))
    }

    private var surfaceShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topCornerRadius,
            bottomLeadingRadius: bottomCornerRadius,
            bottomTrailingRadius: bottomCornerRadius,
            topTrailingRadius: topCornerRadius,
            style: .continuous
        )
    }

    private var tintedFill: some View {
        Group {
            if isLocked {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.07),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.46, green: 0.56, blue: 0.98).opacity(0.32),
                        Color(red: 0.54, green: 0.36, blue: 0.78).opacity(0.26),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var expectedTint: some View {
        surfaceShape
            .fill(Color.white.opacity(isHovered ? 0.072 : 0.06))
    }

    private var expectedBehindTint: some View {
        surfaceShape
            .fill(Color.white.opacity(isHovered ? 0.1 : 0.08))
    }

    private var baseFillOpacity: Double {
        isHovered ? 0.056 : 0.04
    }

    var body: some View {
        content
            .padding(contentInsets)
            .background {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        surfaceShape
                            .fill(Color.white.opacity(baseFillOpacity))

                        if window.available {
                            if showsExpectedOverlay {
                                tintedFill
                                    .frame(width: geometry.size.width)
                                    .mask(alignment: .leading) {
                                        surfaceRangeMask(
                                            totalWidth: geometry.size.width,
                                            startFraction: 0,
                                            endFraction: currentFraction,
                                            roundTrailing: true
                                        )
                                    }

                                expectedBehindTint
                                    .frame(width: geometry.size.width)
                                    .mask(alignment: .leading) {
                                        surfaceRangeMask(
                                            totalWidth: geometry.size.width,
                                            startFraction: 0,
                                            endFraction: expectedFraction,
                                            roundTrailing: true
                                        )
                                    }
                            } else {
                                expectedTint
                                    .frame(width: geometry.size.width)
                                    .mask(alignment: .leading) {
                                        surfaceRangeMask(
                                            totalWidth: geometry.size.width,
                                            startFraction: 0,
                                            endFraction: expectedFraction,
                                            roundTrailing: true
                                        )
                                    }

                                tintedFill
                                    .frame(width: geometry.size.width)
                                    .mask(alignment: .leading) {
                                        surfaceRangeMask(
                                            totalWidth: geometry.size.width,
                                            startFraction: 0,
                                            endFraction: currentFraction,
                                            roundTrailing: true
                                        )
                                    }
                            }
                        }
                    }
                }
            }
            .clipShape(surfaceShape)
            .overlay {
                if isActive {
                    surfaceShape
                        .stroke(Color.white.opacity(0.7), lineWidth: 2)
                }
            }
    }

    private func surfaceRangeMask(
        totalWidth: CGFloat,
        startFraction: CGFloat,
        endFraction: CGFloat,
        roundTrailing: Bool
    ) -> some View {
        let start = min(1, max(0, startFraction))
        let end = min(1, max(start, endFraction))
        let startWidth = totalWidth * start
        let segmentWidth = totalWidth * (end - start)
        let trailingWidth = max(totalWidth - startWidth - segmentWidth, 0)

        return HStack(spacing: 0) {
            Color.clear
                .frame(width: startWidth)

            UnevenRoundedRectangle(
                topLeadingRadius: start == 0 ? topCornerRadius : 0,
                bottomLeadingRadius: start == 0 ? bottomCornerRadius : 0,
                bottomTrailingRadius: roundTrailing ? bottomCornerRadius : 0,
                topTrailingRadius: roundTrailing ? topCornerRadius : 0,
                style: .continuous
            )
            .fill(Color.white)
            .frame(width: max(segmentWidth, 0))

            Color.clear
                .frame(width: trailingWidth)
        }
        .frame(width: totalWidth, alignment: .leading)
    }
}

private struct AccountCardMenuTrigger: NSViewRepresentable {
    let canRemove: Bool
    let onEditDisplayName: () -> Void
    let onRemove: () -> Void
    let onHoverChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onEditDisplayName: onEditDisplayName,
            onRemove: onRemove
        )
    }

    func makeNSView(context: Context) -> MenuTriggerView {
        let view = MenuTriggerView()
        view.coordinator = context.coordinator
        view.onHoverChanged = onHoverChanged
        view.canRemove = canRemove
        return view
    }

    func updateNSView(_ nsView: MenuTriggerView, context: Context) {
        context.coordinator.onEditDisplayName = onEditDisplayName
        context.coordinator.onRemove = onRemove
        nsView.coordinator = context.coordinator
        nsView.onHoverChanged = onHoverChanged
        nsView.canRemove = canRemove
    }

    final class Coordinator: NSObject {
        var onEditDisplayName: () -> Void
        var onRemove: () -> Void

        init(
            onEditDisplayName: @escaping () -> Void,
            onRemove: @escaping () -> Void
        ) {
            self.onEditDisplayName = onEditDisplayName
            self.onRemove = onRemove
        }

        @objc func handleEditDisplayName() {
            self.onEditDisplayName()
        }

        @objc func handleRemove() {
            self.onRemove()
        }
    }

    final class MenuTriggerView: NSView {
        weak var coordinator: Coordinator?
        var onHoverChanged: ((Bool) -> Void)?
        var canRemove = false
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingArea {
                self.removeTrackingArea(trackingArea)
            }

            let nextTrackingArea = NSTrackingArea(
                rect: self.bounds,
                options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            )

            self.addTrackingArea(nextTrackingArea)
            self.trackingArea = nextTrackingArea
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            self.onHoverChanged?(true)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            self.onHoverChanged?(false)
        }

        override func mouseDown(with event: NSEvent) {
            guard let coordinator else {
                return
            }

            let menu = NSMenu()

            let editItem = NSMenuItem(
                title: "Edit Display Name…",
                action: #selector(Coordinator.handleEditDisplayName),
                keyEquivalent: ""
            )
            editItem.target = coordinator
            menu.addItem(editItem)

            let removeItem = NSMenuItem(
                title: "Remove",
                action: #selector(Coordinator.handleRemove),
                keyEquivalent: ""
            )
            removeItem.target = coordinator
            removeItem.isEnabled = self.canRemove
            menu.addItem(removeItem)

            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}

struct AccountCardView: View {
    static let fixedHeight: CGFloat = accountCardHeight

    static func height(for account: AccountSnapshot) -> CGFloat {
        Self.fixedHeight
    }

    let account: AccountSnapshot
    let displayName: String
    let canRemove: Bool
    let onEditDisplayName: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false
    private let contentInsets = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)

    private var height: CGFloat {
        Self.height(for: account)
    }

    private var primaryWindow: UsageWindow {
        account.primaryUsageWindow
    }

    var body: some View {
        self.cardContent
            .frame(maxWidth: .infinity, minHeight: self.height, maxHeight: self.height, alignment: .topLeading)
        .overlay {
            self.cardMenuTrigger
        }
    }

    private var cardContent: some View {
        UsageSurfaceView(
            window: primaryWindow,
            isLocked: isUsageWindowLocked(primaryWindow),
            isActive: account.isCurrentSystemAccount == true,
            isHovered: isHovered,
            topCornerRadius: accountCardCornerRadius,
            bottomCornerRadius: accountCardCornerRadius,
            contentInsets: contentInsets
        ) {
            self.compactUsageRows
        }
    }

    private var compactUsageRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 8)

                self.usageHeadlineLabel
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let accountTag = compactAccountTag(for: account), !accountTag.isEmpty {
                    Text(accountTag)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 8)

                Text(usageWindowResetText(for: primaryWindow))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(resetCreditsCountText(for: account.resetCredits))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 8)

                if let expiryText = resetCreditsExpiryText(for: account.resetCredits) {
                    Text(expiryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var usageHeadlineLabel: some View {
        let now = Date()

        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(percentageText(for: primaryWindow, now: now))

            if let deltaText = usageDeltaText(for: primaryWindow, now: now) {
                Text(deltaText)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.headline.weight(.semibold))
    }

    private var cardMenuTrigger: some View {
        AccountCardMenuTrigger(
            canRemove: canRemove,
            onEditDisplayName: onEditDisplayName,
            onRemove: onRemove,
            onHoverChanged: { hovering in
                self.isHovered = hovering
            }
        )
    }

}

import SwiftUI

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
            Text(window.available ? resetPaceText(for: window) : "n/a")
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
                    brightFill
                        .frame(width: geometry.size.width)
                        .mask(alignment: .leading) {
                            segmentMask(width: geometry.size.width * currentFraction)
                        }

                    barFill
                        .frame(width: geometry.size.width)
                        .mask(alignment: .leading) {
                            segmentMask(width: geometry.size.width * expectedFraction)
                        }
                } else {
                    expectedFill
                        .frame(width: geometry.size.width)
                        .mask(alignment: .leading) {
                            segmentMask(width: geometry.size.width * expectedFraction)
                        }

                    barFill
                        .frame(width: geometry.size.width)
                        .mask(alignment: .leading) {
                            segmentMask(width: geometry.size.width * currentFraction)
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
                        Color(red: 0.4, green: 0.49, blue: 0.92),
                        Color(red: 0.46, green: 0.29, blue: 0.64),
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

    @ViewBuilder
    private func segmentMask(width: CGFloat) -> some View {
        barShape
            .frame(width: max(width, 0), alignment: .leading)
    }

    private var expectedFill: some View {
        barShape
            .fill(expectedBarColor)
    }

    private var brightFill: some View {
        ZStack {
            barFill
            barShape
                .fill(Color.white.opacity(0.24))
        }
        .clipShape(barShape)
    }
}

struct RollingUsageInlineView: View {
    let window: UsageWindow

    private var currentFraction: CGFloat {
        CGFloat(Double(displayRemainingPercentage(for: window)) / 100)
    }

    private var expectedFraction: CGFloat {
        CGFloat(expectedRemainingPercentage(for: window) / 100)
    }

    private var showsExpectedOverlay: Bool {
        expectedRemainingPercentage(for: window) < Double(displayRemainingPercentage(for: window))
    }

    private var ringStyle: AnyShapeStyle {
        if isRollingWindowLocked(window) {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.32),
                        Color.white.opacity(0.2),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color(red: 0.4, green: 0.49, blue: 0.92),
                    Color(red: 0.46, green: 0.29, blue: 0.64),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var expectedRing: some View {
        Circle()
            .trim(from: 0, to: expectedFraction)
            .stroke(
                Color.white.opacity(0.24),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
    }

    private var currentRing: some View {
        Circle()
            .trim(from: 0, to: currentFraction)
            .stroke(
                ringStyle,
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
    }

    private var brightCurrentRing: some View {
        Circle()
            .trim(from: 0, to: currentFraction)
            .stroke(
                Color.white.opacity(0.24),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .overlay {
                currentRing
            }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(displayWindowLabel(for: window))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 3)

                expectedRing

                if showsExpectedOverlay {
                    brightCurrentRing
                } else {
                    currentRing
                }
            }
            .frame(width: 12, height: 12)
        }
        .opacity(window.available ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("5 hour session usage")
        .accessibilityValue(sessionResetText(for: window) + ", " + percentageText(for: window) + " remaining")
    }
}

struct WeeklyUsageSurfaceView<Content: View>: View {
    let window: UsageWindow
    let isLocked: Bool
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    let contentPadding: CGFloat
    @ViewBuilder let content: Content

    init(
        window: UsageWindow,
        isLocked: Bool,
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat,
        contentPadding: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.window = window
        self.isLocked = isLocked
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.contentPadding = contentPadding
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
                        Color(red: 0.4, green: 0.49, blue: 0.92).opacity(0.2),
                        Color(red: 0.46, green: 0.29, blue: 0.64).opacity(0.14),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var expectedTint: some View {
        surfaceShape
            .fill(Color.white.opacity(0.06))
    }

    var body: some View {
        content
            .padding(contentPadding)
            .background {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        surfaceShape
                            .fill(Color.white.opacity(0.04))

                        if window.available {
                            if showsExpectedOverlay {
                                tintedFill
                                    .frame(width: geometry.size.width)
                                    .mask(alignment: .leading) {
                                        surfaceShape.frame(width: geometry.size.width * currentFraction)
                                    }

                                expectedTint
                                    .frame(width: geometry.size.width)
                                    .mask(alignment: .leading) {
                                        surfaceShape.frame(width: geometry.size.width * expectedFraction)
                                    }
                            } else {
                                expectedTint
                                    .frame(width: geometry.size.width)
                                    .mask(alignment: .leading) {
                                        surfaceShape.frame(width: geometry.size.width * expectedFraction)
                                    }

                                tintedFill
                                    .frame(width: geometry.size.width)
                                    .mask(alignment: .leading) {
                                        surfaceShape.frame(width: geometry.size.width * currentFraction)
                                    }
                            }
                        }
                    }
                }
            }
            .clipShape(surfaceShape)
    }
}

struct AccountCardView: View {
    let account: AccountSnapshot
    let displayName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WeeklyUsageSurfaceView(
                window: account.weeklyWindow,
                isLocked: isRollingWindowLocked(account.rollingWindow),
                topCornerRadius: 24,
                bottomCornerRadius: 24,
                contentPadding: 20
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(displayName)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            if account.rollingWindow.available {
                                RollingUsageInlineView(window: account.rollingWindow)
                            }

                            Text(percentageText(for: account.weeklyWindow))
                                .font(.title3.weight(.semibold))
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(accountTierText(for: account))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        Text(resetPaceText(for: account.weeklyWindow))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct SlimAccountCardView: View {
    let account: AccountSnapshot
    let displayName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WeeklyUsageSurfaceView(
                window: account.weeklyWindow,
                isLocked: isRollingWindowLocked(account.rollingWindow),
                topCornerRadius: 20,
                bottomCornerRadius: 20,
                contentPadding: 14
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(displayName)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if account.rollingWindow.available {
                                RollingUsageInlineView(window: account.rollingWindow)
                            }

                            Text(percentageText(for: account.weeklyWindow))
                                .font(.headline.weight(.semibold))
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        if let tag = compactAccountTag(for: account) {
                            Text(tag)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 12)

                        Text(resetPaceText(for: account.weeklyWindow))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

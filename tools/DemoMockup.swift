import AppKit
import SwiftUI

private let canvasSize = CGSize(width: 906, height: 1598)
private let menuBarHeight: CGFloat = 48
private let cardWidth: CGFloat = 520
private let cardSpacing: CGFloat = 12
private let horizontalPadding: CGFloat = 72
private let verticalPadding: CGFloat = 96
private let iconPath = "assets/icon.png"

@main
@MainActor
struct DemoMockup {
    static func main() throws {
        let arguments = CommandLine.arguments.dropFirst()
        let outputPath = arguments.first ?? "assets/demo.png"
        let image = renderDemoImage()
        try writePNG(image, to: URL(fileURLWithPath: outputPath))
        print("Wrote \(outputPath)")
    }
}

private struct DemoMockupView: View {
    private let accounts = demoAccounts()

    private var sortedRows: [AccountSnapshot] {
        sortedAccountsByResetTime(accounts) { account in
            account.label
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.91, green: 0.91, blue: 0.92)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: cardSpacing) {
                ForEach(sortedRows) { account in
                    AccountCardView(
                        account: account,
                        displayName: account.label,
                        canRemove: false,
                        onEditDisplayName: {},
                        onRemove: {}
                    )
                }
            }
            .frame(width: cardWidth)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.1))
                    .shadow(color: .black.opacity(0.16), radius: 28, x: 0, y: 18)
            )
        }
        .overlay(alignment: .top) {
            menuBar
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .preferredColorScheme(.dark)
    }

    private var menuBar: some View {
        HStack(spacing: 0) {
            Text("Comux")
                .font(.system(size: 14, weight: .semibold))

            Text("File")
                .font(.system(size: 14))
                .padding(.leading, 22)

            Text("Edit")
                .font(.system(size: 14))
                .padding(.leading, 18)

            Spacer()

            HStack(spacing: 4) {
                menuBarIcon

                if let usageText = menuBarUsageText(from: accounts) {
                    Text(usageText)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.08))
            )

            Text("Tue 9:41 AM")
                .font(.system(size: 13, weight: .medium))
                .padding(.leading, 12)
        }
        .foregroundStyle(Color.black.opacity(0.82))
        .padding(.horizontal, 18)
        .frame(width: canvasSize.width, height: menuBarHeight)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var menuBarIcon: some View {
        Group {
            if let image = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
            } else {
                Image(systemName: "gauge.with.needle")
                    .resizable()
            }
        }
        .foregroundStyle(Color.black.opacity(0.82))
        .frame(width: 16, height: 16)
    }
}

private func renderDemoImage() -> NSImage {
    let view = DemoMockupView()
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(origin: .zero, size: canvasSize)
    hostingView.setFrameSize(canvasSize)
    hostingView.layoutSubtreeIfNeeded()

    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Unable to allocate bitmap for demo mockup.")
    }

    bitmap.size = canvasSize

    NSGraphicsContext.saveGraphicsState()
    if let context = NSGraphicsContext(bitmapImageRep: bitmap) {
        NSGraphicsContext.current = context
        hostingView.displayIgnoringOpacity(hostingView.bounds, in: context)
    }
    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: canvasSize)
    image.addRepresentation(bitmap)
    return image
}

private func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode demo mockup PNG.")
    }

    try pngData.write(to: url, options: .atomic)
}

private func demoAccounts() -> [AccountSnapshot] {
    let now = Date()

    return [
        makeAccount(
            id: "used-out",
            label: "Used Out",
            workspaceLabel: "Ops",
            plan: "Codex Team",
            isCurrent: false,
            weeklyUsedPercentage: 100,
            weeklyResetOffset: 2 * 24 * 60 * 60,
            rollingUsedPercentage: 72,
            rollingResetOffset: 45 * 60,
            now: now
        ),
        makeAccount(
            id: "behind",
            label: "Behind Pace",
            workspaceLabel: "Labs",
            plan: "Codex Team",
            isCurrent: false,
            weeklyUsedPercentage: 62,
            weeklyResetOffset: 5 * 24 * 60 * 60,
            rollingUsedPercentage: 44,
            rollingResetOffset: 3 * 60 * 60,
            now: now
        ),
        makeAccount(
            id: "locked",
            label: "Locked",
            workspaceLabel: "Personal",
            plan: "Codex Pro",
            isCurrent: true,
            weeklyUsedPercentage: 36,
            weeklyResetOffset: 3 * 24 * 60 * 60,
            rollingUsedPercentage: 100,
            rollingResetOffset: 82 * 60,
            now: now
        ),
        makeAccount(
            id: "fresh-paid",
            label: "Fresh Team",
            workspaceLabel: "Design",
            plan: "Codex Team",
            isCurrent: false,
            weeklyUsedPercentage: 0,
            weeklyResetOffset: 7 * 24 * 60 * 60,
            rollingUsedPercentage: 0,
            rollingResetOffset: 5 * 60 * 60,
            now: now
        ),
        makeAccount(
            id: "ahead",
            label: "Ahead Pace",
            workspaceLabel: "Personal",
            plan: "Codex Pro",
            isCurrent: false,
            weeklyUsedPercentage: 46,
            weeklyResetOffset: 2 * 24 * 60 * 60,
            rollingUsedPercentage: 18,
            rollingResetOffset: 70 * 60,
            now: now
        ),
    ]
}

private func makeAccount(
    id: String,
    label: String,
    workspaceLabel: String,
    plan: String,
    isCurrent: Bool,
    weeklyAvailable: Bool = true,
    weeklyUsedPercentage: Double,
    weeklyResetOffset: TimeInterval,
    rollingAvailable: Bool = true,
    rollingUsedPercentage: Double,
    rollingResetOffset: TimeInterval,
    now: Date
) -> AccountSnapshot {
    AccountSnapshot(
        accountId: id,
        label: label,
        email: "\(id)@example.com",
        workspaceId: workspaceLabel == "Personal" ? nil : "workspace-\(id)",
        workspaceLabel: workspaceLabel,
        plan: plan,
        source: "mockup",
        systemAuthProfileId: isCurrent ? "mockup-profile" : nil,
        isCurrentSystemAccount: isCurrent,
        lastSyncedAt: isoString(now),
        weeklyWindow: makeWindow(
            label: "weekly",
            available: weeklyAvailable,
            limitMinutes: 10_080,
            usedPercentage: weeklyUsedPercentage,
            resetOffset: weeklyResetOffset,
            now: now
        ),
        rollingWindow: makeWindow(
            label: "5-hour",
            available: rollingAvailable,
            limitMinutes: 300,
            usedPercentage: rollingUsedPercentage,
            resetOffset: rollingResetOffset,
            now: now
        )
    )
}

private func makeWindow(
    label: String,
    available: Bool,
    limitMinutes: Int,
    usedPercentage: Double,
    resetOffset: TimeInterval,
    now: Date
) -> UsageWindow {
    let clampedUsed = clampPercentage(usedPercentage)
    let usedMinutes = Int(round(Double(limitMinutes) * (clampedUsed / 100)))

    return UsageWindow(
        available: available,
        label: label,
        usedMinutes: usedMinutes,
        limitMinutes: limitMinutes,
        usedPercentage: clampedUsed,
        resetsAt: isoString(now.addingTimeInterval(resetOffset))
    )
}

private func isoString(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

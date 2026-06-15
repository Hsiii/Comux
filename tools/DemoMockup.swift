import AppKit
import SwiftUI

private let renderScale: CGFloat = 3
private let canvasSize = CGSize(width: 529, height: 679)
private let outputPixelSize = CGSize(
    width: canvasSize.width * renderScale,
    height: canvasSize.height * renderScale
)
private let menuBarHeight: CGFloat = 24
private let panelWidth: CGFloat = 360
private let panelHeight: CGFloat = 602
private let panelTopOffset: CGFloat = 36
private let panelCornerRadius: CGFloat = 12
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
    private let coordinator = demoCoordinator()
    private let displayNameStore = DisplayNameStore(displayNames: [:])
    private let launchAtLoginStore = LaunchAtLoginStore(opensAtLogin: true)
    @State private var measuredPanelContentHeight: CGFloat = panelHeight

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.91, green: 0.91, blue: 0.92)
                .ignoresSafeArea()

            menuBar

            panel
                .padding(.top, panelTopOffset)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .preferredColorScheme(.dark)
    }

    private var menuBar: some View {
        HStack(spacing: 0) {
            Text("Comux")
                .font(.system(size: 13, weight: .semibold))

            Text("File")
                .font(.system(size: 13))
                .padding(.leading, 22)

            Text("Edit")
                .font(.system(size: 13))
                .padding(.leading, 18)

            Spacer()

            HStack(spacing: 4) {
                menuBarIcon

                if let usageText = menuBarUsageText(from: accounts) {
                    Text(usageText)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.08))
            )

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 13, weight: .medium))
                .padding(.leading, 10)

            Image(systemName: "wifi")
                .font(.system(size: 13, weight: .semibold))
                .padding(.leading, 10)

            Image(systemName: "battery.100.bolt")
                .font(.system(size: 15, weight: .medium))
                .padding(.leading, 10)

            Text("Tue 9:41 AM")
                .font(.system(size: 12, weight: .medium))
                .padding(.leading, 12)
        }
        .foregroundStyle(Color.black.opacity(0.82))
        .padding(.horizontal, 10)
        .frame(width: canvasSize.width, height: menuBarHeight)
        .background(Color.white.opacity(0.28))
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

    private var panel: some View {
        SlimDashboardPanelView(
            coordinator: coordinator,
            displayNameStore: displayNameStore,
            launchAtLoginStore: launchAtLoginStore,
            measuredContentHeight: $measuredPanelContentHeight,
            panelHeight: panelHeight,
            onEditDisplayNameRequested: { _ in },
            onRemoveRequested: { _ in }
        )
        .frame(width: panelWidth, height: panelHeight)
        .background(
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .fill(Color(red: 0.12, green: 0.16, blue: 0.2).opacity(0.9))
                .background(
                    RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        )
        .overlay {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.34), radius: 16, x: 0, y: 8)
    }
}

@MainActor
private func demoCoordinator() -> PulseCoordinator {
    let coordinator = PulseCoordinator()
    coordinator.cache = CachePayload(
        meta: CacheMeta(source: "demo-mockup"),
        accounts: demoAccounts()
    )
    return coordinator
}

private func renderDemoImage() -> NSImage {
    let view = DemoMockupView()
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(origin: .zero, size: canvasSize)
    hostingView.setFrameSize(canvasSize)
    hostingView.layoutSubtreeIfNeeded()

    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(outputPixelSize.width),
        pixelsHigh: Int(outputPixelSize.height),
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
            id: "hsi-kiwi",
            label: "Hsi",
            workspaceLabel: "Kiwi",
            plan: "Codex Team",
            isCurrent: false,
            weeklyUsedPercentage: 0,
            weeklyResetOffset: 7 * 24 * 60 * 60,
            rollingUsedPercentage: 0,
            rollingResetOffset: 5 * 60 * 60,
            now: now
        ),
        makeAccount(
            id: "sago-ahead",
            label: "Sago",
            workspaceLabel: "せっきたくま",
            plan: "Codex Team",
            isCurrent: false,
            weeklyUsedPercentage: 19,
            weeklyResetOffset: 5 * 24 * 60 * 60 + 11 * 60 * 60,
            rollingUsedPercentage: 26,
            rollingResetOffset: 4 * 60 * 60,
            now: now
        ),
        makeAccount(
            id: "erikson-locked",
            label: "Erikson",
            workspaceLabel: "せっきたくま",
            plan: "Codex Team",
            isCurrent: false,
            weeklyUsedPercentage: 32,
            weeklyResetOffset: 5 * 24 * 60 * 60 + 10 * 60 * 60,
            rollingUsedPercentage: 100,
            rollingResetOffset: 94 * 60,
            now: now
        ),
        makeAccount(
            id: "nthu-locked",
            label: "NTHU",
            workspaceLabel: "せっきたくま",
            plan: "Codex Team",
            isCurrent: false,
            weeklyUsedPercentage: 21,
            weeklyResetOffset: 6 * 24 * 60 * 60 + 10 * 60 * 60,
            rollingUsedPercentage: 100,
            rollingResetOffset: 4 * 60 * 60 + 4 * 60,
            now: now
        ),
        makeAccount(
            id: "hs1-locked",
            label: "Hs1",
            workspaceLabel: "せっきたくま",
            plan: "Codex Team",
            isCurrent: false,
            weeklyUsedPercentage: 67,
            weeklyResetOffset: 4 * 24 * 60 * 60 + 14 * 60 * 60,
            rollingUsedPercentage: 100,
            rollingResetOffset: 2 * 60 * 60 + 56 * 60,
            now: now
        ),
        makeAccount(
            id: "hsi-used",
            label: "Hsi",
            workspaceLabel: "せっきたくま",
            plan: "Codex Team",
            isCurrent: false,
            weeklyUsedPercentage: 100,
            weeklyResetOffset: 3 * 24 * 60 * 60 + 16 * 60 * 60,
            rollingUsedPercentage: 80,
            rollingResetOffset: 3 * 60 * 60,
            now: now
        ),
        makeAccount(
            id: "sago-used",
            label: "Sago",
            workspaceLabel: "Kiwi",
            plan: "Codex Team",
            isCurrent: false,
            weeklyUsedPercentage: 100,
            weeklyResetOffset: 4 * 24 * 60 * 60 + 13 * 60 * 60,
            rollingUsedPercentage: 65,
            rollingResetOffset: 2 * 60 * 60,
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

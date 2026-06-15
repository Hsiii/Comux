import AppKit
import SwiftUI

private let renderScale: CGFloat = 2
private let canvasSize = CGSize(width: 529, height: 679)
private let outputPixelSize = CGSize(
    width: canvasSize.width * renderScale,
    height: canvasSize.height * renderScale
)
private let menuBarHeight: CGFloat = 24
private let panelWidth: CGFloat = 360
private let panelTopOffset: CGFloat = 36
private let panelCornerRadius: CGFloat = 12
private let panelContentInset: CGFloat = 16
private let cardStackSpacing: CGFloat = 16
private let controlHeight: CGFloat = 28
private let controlDividerSpacing: CGFloat = 6
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
        ZStack(alignment: .top) {
            DemoDesktopBackground()
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
            .frame(height: 20)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.14))
            )

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 14, weight: .medium))
                .padding(.leading, 10)

            Image(systemName: "wifi")
                .font(.system(size: 14, weight: .semibold))
                .padding(.leading, 10)

            Image(systemName: "battery.100.bolt")
                .font(.system(size: 16, weight: .medium))
                .padding(.leading, 10)

            Text("Tue 9:41 AM")
                .font(.system(size: 13, weight: .medium))
                .padding(.leading, 12)
        }
        .foregroundStyle(Color.white.opacity(0.94))
        .padding(.horizontal, 10)
        .frame(width: canvasSize.width, height: menuBarHeight)
        .background(Color.black.opacity(0.18))
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
        .foregroundStyle(Color.white.opacity(0.94))
        .frame(width: 12, height: 12)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: cardStackSpacing) {
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
            .padding(.top, panelContentInset)
            .padding(.horizontal, panelContentInset)

            Divider()
                .padding(.top, panelContentInset)
                .padding(.bottom, controlDividerSpacing)
                .padding(.horizontal, panelContentInset)

            controlRow("Open at Login", showsCheckmark: true)

            Divider()
                .padding(.vertical, controlDividerSpacing)
                .padding(.horizontal, panelContentInset)

            controlRow("Quit")
                .padding(.bottom, 6)
        }
        .frame(width: panelWidth)
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

    private func controlRow(_ title: String, showsCheckmark: Bool = false) -> some View {
        HStack(spacing: 0) {
            if showsCheckmark {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 14)
                    .padding(.trailing, 4)
            }

            Text(title)
                .font(.system(size: 13, weight: .semibold))

            Spacer()
        }
        .foregroundStyle(Color.white.opacity(0.94))
        .frame(height: controlHeight)
        .padding(.horizontal, 26)
    }
}

private struct DemoDesktopBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.49, blue: 0.55),
                    Color(red: 0.19, green: 0.24, blue: 0.29),
                    Color(red: 0.58, green: 0.61, blue: 0.63),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(Color(red: 0.77, green: 0.82, blue: 0.86).opacity(0.5))
                .frame(width: 700, height: 46)
                .rotationEffect(.degrees(-10))
                .offset(x: -110, y: -100)

            Rectangle()
                .fill(Color(red: 0.08, green: 0.11, blue: 0.16).opacity(0.42))
                .frame(width: 720, height: 50)
                .rotationEffect(.degrees(-7))
                .offset(x: -120, y: -8)

            Rectangle()
                .fill(Color(red: 0.12, green: 0.16, blue: 0.2).opacity(0.5))
                .frame(width: 760, height: 54)
                .rotationEffect(.degrees(-9))
                .offset(x: -120, y: 84)

            Circle()
                .fill(Color(red: 0.62, green: 0.06, blue: 0.22).opacity(0.5))
                .frame(width: 160, height: 220)
                .offset(x: -246, y: 240)
                .blur(radius: 14)

            Color.black.opacity(0.12)
        }
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

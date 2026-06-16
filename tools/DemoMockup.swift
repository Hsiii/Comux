import AppKit
import SwiftUI

private let windowRenderScale: CGFloat = 2
private let canvasSize = CGSize(width: 529, height: 679)
private let windowSize = CGSize(
    width: canvasSize.width * windowRenderScale,
    height: canvasSize.height * windowRenderScale
)
private let menuBarHeight: CGFloat = 35
private let panelWidth: CGFloat = 360
private let panelHeight: CGFloat = 602
private let panelLeading = (canvasSize.width - panelWidth) / 2
private let panelTopOffset = menuBarHeight
private let panelCornerRadius: CGFloat = 12
private let iconPath = "assets/icon.png"

@main
@MainActor
struct DemoMockup {
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        let outputPath = arguments.first ?? "assets/demo.png"
        let app = NSApplication.shared

        app.setActivationPolicy(.accessory)
        demoCaptureController = DemoCaptureController(outputPath: outputPath)
        app.delegate = demoCaptureController
        app.run()
    }
}

@MainActor private var demoCaptureController: DemoCaptureController?

private struct DemoMockupView: View {
    let menuBarItemImage: NSImage

    private let coordinator = demoCoordinator()
    private let displayNameStore = DisplayNameStore(displayNames: [:])
    private let launchAtLoginStore = LaunchAtLoginStore(opensAtLogin: true)
    @State private var measuredPanelContentHeight: CGFloat = panelHeight

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(white: 0.3)
                .ignoresSafeArea()

            Image(nsImage: menuBarItemImage)
                .resizable()
                .frame(width: menuBarItemImage.size.width, height: menuBarItemImage.size.height)
                .position(
                    x: panelLeading + panelWidth - (menuBarItemImage.size.width / 2),
                    y: menuBarHeight / 2
                )

            panel
                .padding(.leading, panelLeading)
                .padding(.top, panelTopOffset)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .preferredColorScheme(.dark)
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

private enum DemoRenderError: Error {
    case missingScreen
    case missingWindowID
    case missingWindowCaptureSymbol
    case captureFailed
    case missingStatusButton
    case missingStatusSnapshot
    case missingUsageText
}

private typealias CGWindowListCreateImageFunction = @convention(c) (
    CGRect,
    UInt32,
    CGWindowID,
    UInt32
) -> Unmanaged<CGImage>?

@MainActor
private final class DemoCaptureController: NSObject, NSApplicationDelegate {
    private let outputPath: String
    private var statusItem: NSStatusItem?
    private var panelWindow: NSWindow?

    init(outputPath: String) {
        self.outputPath = outputPath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate()

        do {
            try installStatusItem()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.captureAndExit()
            }
        } catch {
            fail(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }

    private func installStatusItem() throws {
        guard let usageText = menuBarUsageText(from: demoAccounts()) else {
            throw DemoRenderError.missingUsageText
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItem(statusItem, usageText: usageText)
        self.statusItem = statusItem
    }

    private func captureAndExit() {
        do {
            let image = try renderDemoImage()
            try writePNG(image, to: URL(fileURLWithPath: outputPath))
            print("Wrote \(outputPath)")
            cleanup()
            NSApplication.shared.terminate(nil)
        } catch {
            fail(error)
        }
    }

    private func renderDemoImage() throws -> NSImage {
        guard let screen = NSScreen.main else {
            throw DemoRenderError.missingScreen
        }

        let menuBarItemImage = try nativeStatusItemImage()
        panelWindow = makeMockupWindow(menuBarItemImage: menuBarItemImage, screen: screen)
        panelWindow?.orderFrontRegardless()

        for _ in 0..<8 {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
            panelWindow?.displayIfNeeded()
        }

        guard let captureWindow = dynamicWindowCaptureFunction() else {
            throw DemoRenderError.missingWindowCaptureSymbol
        }

        let imageOptions: CGWindowImageOption = [.bestResolution, .boundsIgnoreFraming]
        guard let windowNumber = panelWindow.flatMap({ CGWindowID(exactly: $0.windowNumber) }) else {
            throw DemoRenderError.missingWindowID
        }

        guard let capturedImage = captureWindow(
            .null,
            CGWindowListOption.optionIncludingWindow.rawValue,
            windowNumber,
            imageOptions.rawValue
        )?.takeRetainedValue() else {
            throw DemoRenderError.captureFailed
        }

        return NSImage(
            cgImage: capturedImage,
            size: NSSize(width: capturedImage.width, height: capturedImage.height)
        )
    }

    private func nativeStatusItemImage() throws -> NSImage {
        guard let button = statusItem?.button else {
            throw DemoRenderError.missingStatusButton
        }

        let intrinsicSize = button.intrinsicContentSize
        let buttonSize = NSSize(
            width: max(ceil(intrinsicSize.width), 76),
            height: menuBarHeight
        )
        button.frame = CGRect(origin: .zero, size: buttonSize)
        button.layoutSubtreeIfNeeded()
        button.highlight(true)
        defer { button.highlight(false) }

        guard let representation = button.bitmapImageRepForCachingDisplay(in: button.bounds) else {
            throw DemoRenderError.missingStatusSnapshot
        }

        representation.size = button.bounds.size
        button.cacheDisplay(in: button.bounds, to: representation)

        let image = NSImage(size: button.bounds.size)
        image.addRepresentation(representation)
        return image
    }

    private func cleanup() {
        panelWindow?.orderOut(nil)

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }

        statusItem = nil
        panelWindow = nil
    }

    private func fail(_ error: Error) -> Never {
        cleanup()
        fputs("Demo mockup failed: \(error)\n", stderr)
        exit(1)
    }
}

private func configureStatusItem(_ statusItem: NSStatusItem, usageText: String) {
    guard let button = statusItem.button else {
        return
    }

    statusItem.length = NSStatusItem.variableLength
    button.appearance = NSAppearance(named: .darkAqua)
    button.image = statusIcon()
    button.imagePosition = .imageLeft
    button.imageScaling = .scaleProportionallyDown
    button.imageHugsTitle = true
    button.title = usageText
    button.font = .menuBarFont(ofSize: 0)
}

private func statusIcon() -> NSImage? {
    let image = NSImage(contentsOfFile: iconPath)
        ?? NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "Comux")
    image?.size = NSSize(width: 16, height: 16)
    image?.isTemplate = true
    return image
}

private func makeMockupWindow(menuBarItemImage: NSImage, screen: NSScreen) -> NSWindow {
    let rootView = DemoMockupView(menuBarItemImage: menuBarItemImage)
        .scaleEffect(windowRenderScale, anchor: .topLeading)
        .frame(width: windowSize.width, height: windowSize.height, alignment: .topLeading)
    let hostingView = NSHostingView(rootView: rootView)
    hostingView.frame = CGRect(origin: .zero, size: windowSize)
    hostingView.setFrameSize(windowSize)

    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: windowSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false,
        screen: screen
    )
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = false
    window.level = .floating
    window.contentView = hostingView
    window.setFrameOrigin(
        CGPoint(
            x: screen.visibleFrame.midX - (windowSize.width / 2),
            y: screen.visibleFrame.midY - (windowSize.height / 2)
        )
    )
    hostingView.layoutSubtreeIfNeeded()
    return window
}

private func dynamicWindowCaptureFunction() -> CGWindowListCreateImageFunction? {
    guard let handle = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        RTLD_NOW
    ) else {
        return nil
    }

    guard let symbol = dlsym(handle, "CGWindowListCreateImage") else {
        return nil
    }

    return unsafeBitCast(symbol, to: CGWindowListCreateImageFunction.self)
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
            id: "demo-alpha",
            label: "Alex",
            workspaceLabel: "Atlas",
            plan: "Codex Team",
            isCurrent: false,
            weeklyUsedPercentage: 0,
            weeklyResetOffset: 7 * 24 * 60 * 60,
            rollingUsedPercentage: 0,
            rollingResetOffset: 5 * 60 * 60,
            now: now
        ),
        makeAccount(
            id: "demo-bravo",
            label: "Blake",
            workspaceLabel: "Beacon",
            plan: "Codex Team",
            isCurrent: true,
            weeklyUsedPercentage: 19,
            weeklyResetOffset: 5 * 24 * 60 * 60 + 11 * 60 * 60,
            rollingUsedPercentage: 17,
            rollingResetOffset: 4 * 60 * 60,
            now: now
        ),
        makeAccount(
            id: "demo-charlie",
            label: "Casey",
            workspaceLabel: "Canvas",
            plan: "Codex Team",
            isCurrent: false,
            weeklyUsedPercentage: 32,
            weeklyResetOffset: 5 * 24 * 60 * 60 + 10 * 60 * 60,
            rollingUsedPercentage: 100,
            rollingResetOffset: 94 * 60,
            now: now
        ),
        makeAccount(
            id: "demo-delta",
            label: "Drew",
            workspaceLabel: "Delta",
            plan: "Codex Team",
            isCurrent: false,
            weeklyUsedPercentage: 21,
            weeklyResetOffset: 6 * 24 * 60 * 60 + 10 * 60 * 60,
            rollingUsedPercentage: 100,
            rollingResetOffset: 4 * 60 * 60 + 4 * 60,
            now: now
        ),
        makeAccount(
            id: "demo-echo",
            label: "Emery",
            workspaceLabel: "Echo",
            plan: "Codex Team",
            isCurrent: false,
            weeklyUsedPercentage: 67,
            weeklyResetOffset: 4 * 24 * 60 * 60 + 14 * 60 * 60,
            rollingUsedPercentage: 100,
            rollingResetOffset: 2 * 60 * 60 + 56 * 60,
            now: now
        ),
        makeAccount(
            id: "demo-foxtrot",
            label: "Finley",
            workspaceLabel: "Forge",
            plan: "Codex Team",
            isCurrent: false,
            weeklyUsedPercentage: 100,
            weeklyResetOffset: 3 * 24 * 60 * 60 + 16 * 60 * 60,
            rollingUsedPercentage: 80,
            rollingResetOffset: 3 * 60 * 60,
            now: now
        ),
        makeAccount(
            id: "demo-golf",
            label: "Gray",
            workspaceLabel: "Garden",
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

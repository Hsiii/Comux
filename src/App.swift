import AppKit
import SwiftUI

@MainActor
final class ComuxLifecycleDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Comux menu bar app")
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProcessInfo.processInfo.enableAutomaticTermination("Comux menu bar app")
    }
}

@main
struct ComuxApp: App {
    @NSApplicationDelegateAdaptor(ComuxLifecycleDelegate.self) private var lifecycleDelegate
    @StateObject private var coordinator: PulseCoordinator
    @StateObject private var autoUpdateStore: AutoUpdateStore

    init() {
        let coordinator = PulseCoordinator()
        let autoUpdateStore = AutoUpdateStore()
        _coordinator = StateObject(wrappedValue: coordinator)
        _autoUpdateStore = StateObject(wrappedValue: autoUpdateStore)
        coordinator.start()
        autoUpdateStore.checkAutomatically()
    }

    var body: some Scene {
        MenuBarExtra {
            PulseMenuView(
                coordinator: self.coordinator,
                autoUpdateStore: self.autoUpdateStore
            )
                .task {
                    await self.coordinator.syncNow()
                }
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: Self.codexMenuBarIcon)

                if let usageText = menuBarUsageText(from: self.coordinator.cache.accounts) {
                    Text(usageText)
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private static var codexMenuBarIcon: NSImage {
        let image = AppResources.image(named: "icon", withExtension: "png", subdirectory: "assets")
            ?? AppResources.image(named: "comux", withExtension: "icns")
            ?? NSApplication.shared.applicationIconImage

        guard let image else {
            return NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "Comux") ?? NSImage()
        }

        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        image.accessibilityDescription = "Comux"
        return image
    }
}

import SwiftUI

@main
struct CodexMuxApp: App {
    @StateObject private var coordinator = PulseCoordinator()

    var body: some Scene {
        MenuBarExtra("CodexMux", systemImage: "gauge.with.needle") {
            PulseMenuView(coordinator: coordinator)
                .task {
                    coordinator.start()
                }
        }
        .menuBarExtraStyle(.window)
    }
}

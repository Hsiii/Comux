// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "comux",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "comux", targets: ["Comux"])
    ],
    targets: [
        .executableTarget(
            name: "Comux",
            path: "src",
            sources: [
                "App.swift",
                "FeatureFlags.swift",
                "Model.swift",
                "AccountIdentity.swift",
                "AccountSnapshotMerger.swift",
                "UsagePayloadParser.swift",
                "CodexAuthenticatedSession.swift",
                "WorkspaceLabelResolver.swift",
                "SystemRefreshErrorPolicy.swift",
                "Path.swift",
                "Persistence.swift",
                "Store.swift",
                "Pulse.swift",
                "Format.swift",
                "Card.swift",
                "CodexLogin.swift",
                "Menu.swift",
                "LaunchAtLogin.swift",
                "Resources.swift",
                "AutoUpdate.swift",
            ],
            resources: [
                .process("../assets")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "ComuxTests",
            dependencies: ["Comux"],
            path: "test"
        )
    ]
)

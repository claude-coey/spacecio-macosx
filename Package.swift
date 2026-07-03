// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpaceSIORelay",
    // macOS 15+: keeps the Swift concurrency runtime on its modern
    // executor-checking path (the legacy pre-15 path crashed in SwiftUI
    // button dispatch on macOS 26).
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "SpaceSIORelay",
            path: "Sources/SpaceSIORelay",
            resources: [.process("Resources")],
            linkerSettings: [
                // Embed Info.plist (location-permission strings, bundle id)
                // directly in the executable so `swift run` works without an
                // .app bundle.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Support/Info.plist",
                ])
            ]
        )
    ]
)

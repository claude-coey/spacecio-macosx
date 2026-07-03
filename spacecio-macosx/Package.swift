// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpaceSIORelay",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SpaceSIORelay",
            path: "Sources/SpaceSIORelay",
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

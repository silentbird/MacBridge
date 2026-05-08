// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacBridgePOC",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacBridgePOC",
            path: "Sources/MacBridgePOC"
        )
    ]
)

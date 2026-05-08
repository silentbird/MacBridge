// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacBridge",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacBridge",
            path: "Sources/MacBridge"
        ),
        .testTarget(
            name: "MacBridgeTests",
            dependencies: ["MacBridge"],
            path: "Tests/MacBridgeTests"
        )
    ]
)

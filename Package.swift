// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexAlert",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "AttentionKit",
            targets: ["AttentionKit"]
        ),
        .executable(
            name: "codex-alert",
            targets: ["codex-alert"]
        ),
    ],
    targets: [
        .target(
            name: "AttentionKit"
        ),
        .executableTarget(
            name: "codex-alert",
            dependencies: ["AttentionKit"]
        ),
        .testTarget(
            name: "AttentionKitTests",
            dependencies: ["AttentionKit"]
        ),
    ]
)

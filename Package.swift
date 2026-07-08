// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.
// 6.0 is the floor for `swiftLanguageModes` + the Swift 6 language mode; newer toolchains
// (including CI's 6.1) build it fine.

import PackageDescription

let package = Package(
    name: "XeneonEdgeWidgets",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "XeneonEdgeWidgets",
            targets: ["XeneonEdgeWidgets"]
        )
    ],
    targets: [
        .executableTarget(
            name: "XeneonEdgeWidgets",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "XeneonEdgeWidgetsTests",
            dependencies: ["XeneonEdgeWidgets"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

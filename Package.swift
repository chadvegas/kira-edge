// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

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

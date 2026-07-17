// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WinLift",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "WinLiftCore", targets: ["WinLiftCore"]),
        .executable(name: "WinLift", targets: ["WinLift"])
    ],
    targets: [
        .target(
            name: "WinLiftCore"
        ),
        .executableTarget(
            name: "WinLift",
            dependencies: ["WinLiftCore"]
        ),
        .testTarget(
            name: "WinLiftCoreTests",
            dependencies: ["WinLiftCore"]
        )
    ]
)

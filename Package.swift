// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "augur",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "augur", targets: ["augur"]),
        .library(name: "AugurKit", targets: ["AugurKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "AugurKit",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "augur",
            dependencies: [
                "AugurKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AugurKitTests",
            dependencies: ["AugurKit"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
    ]
)

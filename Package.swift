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
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        // TOML parsing for `.augur.toml`. CLI-only: AugurKit stays dependency-free.
        .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.3.0"),
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
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AugurKitTests",
            dependencies: ["AugurKit"],
            exclude: ["__snapshots__"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AugurCLITests",
            dependencies: ["augur"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
    ]
)

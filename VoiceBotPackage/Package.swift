// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VoiceBotFeature",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "VoiceBotFeature",
            targets: ["VoiceBotFeature"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Liquid4All/leap-ios.git", from: "0.5.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.0.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.25.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", branch: "main")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "VoiceBotFeature",
            dependencies: [
                .product(name: "LeapSDK", package: "leap-ios"),
                .product(name: "LeapModelDownloader", package: "leap-ios"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
                .product(name: "MLXLLM", package: "mlx-swift-examples")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech")
            ]
        ),
        .testTarget(
            name: "VoiceBotFeatureTests",
            dependencies: [
                "VoiceBotFeature"
            ]
        ),
    ]
)

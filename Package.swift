// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BetterFasterWhisper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "BetterFasterWhisper",
            targets: ["BetterFasterWhisper"]
        ),
    ],
    dependencies: [
        // Add dependencies here if needed
    ],
    targets: [
        .executableTarget(
            name: "BetterFasterWhisper",
            dependencies: [
                "WhisperBridge"
            ],
            path: "App/BetterFasterWhisper/Sources",
            linkerSettings: [
                .linkedLibrary("whisper_core", .when(platforms: [.macOS])),
                .unsafeFlags(["-L", "../whisper-core/target/release"], .when(configuration: .release)),
                .unsafeFlags(["-L", "../whisper-core/target/debug"], .when(configuration: .debug))
            ]
        ),
        .target(
            name: "WhisperBridge",
            dependencies: [],
            path: "App/WhisperBridge",
            publicHeadersPath: "include"
        ),
    ]
)

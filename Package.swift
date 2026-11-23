// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CAMR",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CAMRCore", targets: ["CAMRCore"]),
        .library(name: "CAMRTrial", targets: ["CAMRTrial"]),
        .library(name: "CAMRTools", targets: ["CAMRTools"]),
        .executable(name: "camr", targets: ["camr"]),
        .executable(name: "camr-trial", targets: ["camr-trial"]),
    ],
    targets: [
        .target(name: "CAMRCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "CAMRTrial", dependencies: ["CAMRCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "CAMRTools", dependencies: ["CAMRCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "CAMRMCP", dependencies: ["CAMRCore", "CAMRTools"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "CAMRChat", dependencies: ["CAMRCore", "CAMRTools"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "CAMRTUI", dependencies: ["CAMRCore", "CAMRTools"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "camr", dependencies: ["CAMRCore", "CAMRTools", "CAMRMCP", "CAMRChat", "CAMRTUI"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "camr-trial", dependencies: ["CAMRCore", "CAMRTrial"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CAMRCoreTests", dependencies: ["CAMRCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CAMRTrialTests", dependencies: ["CAMRCore", "CAMRTrial"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CAMRTerminalTests", dependencies: ["CAMRCore", "CAMRTools", "CAMRMCP", "CAMRChat", "CAMRTUI"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

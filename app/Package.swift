// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CAMRApp",
    platforms: [.macOS(.v26)],
    dependencies: [.package(name: "CAMR", path: "..")],
    targets: [
        .executableTarget(
            name: "CAMR",
            dependencies: [.product(name: "CAMRCore", package: "CAMR"), .product(name: "CAMRTrial", package: "CAMR"), .product(name: "CAMRTools", package: "CAMR")],
            path: "Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

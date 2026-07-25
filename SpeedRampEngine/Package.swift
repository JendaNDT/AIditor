// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpeedRampEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpeedRampEngine", targets: ["SpeedRampEngine"]),
    ],
    targets: [
        .target(name: "SpeedRampEngine"),
        .testTarget(name: "SpeedRampEngineTests", dependencies: ["SpeedRampEngine"]),
    ]
)

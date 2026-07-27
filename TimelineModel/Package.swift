// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TimelineModel",
    // Stejné minimum jako zbytek projektu. Modul nesahá na žádné Apple API
    // kromě Foundation — jediná závislost je SpeedRampEngine, který je také
    // čistý Swift, takže se obojí přeloží a otestuje i na Linuxu.
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TimelineModel", targets: ["TimelineModel"]),
    ],
    dependencies: [
        .package(path: "../SpeedRampEngine"),
    ],
    targets: [
        .target(name: "TimelineModel", dependencies: ["SpeedRampEngine"]),
        .testTarget(name: "TimelineModelTests", dependencies: ["TimelineModel"]),
    ]
)

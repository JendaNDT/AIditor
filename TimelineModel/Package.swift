// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TimelineModel",
    // Stejné minimum jako zbytek projektu. Modul nesahá na žádné Apple API
    // kromě Foundation — závislosti SpeedRampEngine a AudioEngine (fáze 14:
    // `BeatGrid` na assetu hudby) jsou také čistý Swift, takže se všechno
    // přeloží a otestuje i na Linuxu.
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TimelineModel", targets: ["TimelineModel"]),
    ],
    dependencies: [
        .package(path: "../SpeedRampEngine"),
        .package(path: "../AudioEngine"),
    ],
    targets: [
        .target(name: "TimelineModel", dependencies: ["SpeedRampEngine", "AudioEngine"]),
        .testTarget(name: "TimelineModelTests", dependencies: ["TimelineModel"]),
    ]
)

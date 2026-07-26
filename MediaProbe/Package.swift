// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MediaProbe",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ProbeKit", targets: ["ProbeKit"]),
        .executable(name: "MediaProbe", targets: ["MediaProbe"]),
        .executable(name: "Flatten", targets: ["Flatten"]),
        .executable(name: "Ramp", targets: ["Ramp"]),
    ],
    dependencies: [
        // Matematika rychlostní křivky. Hotová a ověřená 31 testy.
        .package(path: "../SpeedRampEngine"),
    ],
    targets: [
        // Měřicí a renderovací jádro. Sdílené všemi nástroji.
        .target(name: "ProbeKit"),
        // Sonda: přečti soubor a řekni, co v něm je.
        .executableTarget(name: "MediaProbe", dependencies: ["ProbeKit"]),
        // Zplošťovač: přepiš VFR na pevnou mřížku.
        .executableTarget(name: "Flatten", dependencies: ["ProbeKit"]),
        // Ramp: rychlostní křivka segmentací na mikro-úseky.
        .executableTarget(name: "Ramp", dependencies: [
            "ProbeKit",
            .product(name: "SpeedRampEngine", package: "SpeedRampEngine"),
        ]),
    ]
)

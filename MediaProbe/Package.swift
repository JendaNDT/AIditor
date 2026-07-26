// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MediaProbe",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ProbeKit", targets: ["ProbeKit"]),
        .executable(name: "MediaProbe", targets: ["MediaProbe"]),
        .executable(name: "Flatten", targets: ["Flatten"]),
    ],
    targets: [
        // Měřicí jádro. Sdílené, ať sonda a zplošťovač počítají modus stejně.
        .target(name: "ProbeKit"),
        // Sonda: přečti soubor a řekni, co v něm je.
        .executableTarget(name: "MediaProbe", dependencies: ["ProbeKit"]),
        // Zplošťovač: přepiš VFR na pevnou mřížku.
        .executableTarget(name: "Flatten", dependencies: ["ProbeKit"]),
    ]
)

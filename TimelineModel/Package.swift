// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TimelineModel",
    // Stejné minimum jako zbytek projektu. Modul sám ale nesahá na žádné
    // Apple API kromě Foundation, takže se přeloží a otestuje i na Linuxu.
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TimelineModel", targets: ["TimelineModel"]),
    ],
    targets: [
        .target(name: "TimelineModel"),
        .testTarget(name: "TimelineModelTests", dependencies: ["TimelineModel"]),
    ]
)

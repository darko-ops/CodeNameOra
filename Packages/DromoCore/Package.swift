// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DromoCore",
    platforms: [
        .iOS(.v16),
        .watchOS(.v9),
        .macOS(.v13)   // for local CLI testing of the platform-agnostic core
    ],
    products: [
        .library(name: "DromoCore", targets: ["DromoCore"])
    ],
    targets: [
        .target(
            name: "DromoCore",
            path: "Sources/DromoCore"
        ),
        .testTarget(
            name: "DromoCoreTests",
            dependencies: ["DromoCore"],
            path: "Tests/DromoCoreTests"
        )
    ]
)

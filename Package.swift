// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BerryShot",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BerryShot", targets: ["BerryShot"])
    ],
    targets: [
        .executableTarget(
            name: "BerryShot",
            dependencies: [],
            path: "Sources",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "BerryShotTests",
            dependencies: ["BerryShot"],
            path: "Tests/BerryShotTests"
        )
    ]
)

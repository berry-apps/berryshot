// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BerryShot",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BerryShot", targets: ["BerryShot"]),
        .executable(name: "BerryShotMCP", targets: ["BerryShotMCP"])
    ],
    dependencies: [
        // Pinned exact version per the WP6 compile spike
        // (`05-mcp-server-contract.md` section 2). Do not float this to a
        // range/`from:` requirement without a new reviewed spike — see
        // `10-decisions-risks-open-questions.md` and the WP6 anti-pattern
        // guard "No floating unreviewed pre-1.0 SDK update."
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")
    ],
    targets: [
        .target(
            name: "BerryShotIPC",
            dependencies: [],
            path: "Shared/IPC",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "BerryShot",
            dependencies: ["BerryShotIPC"],
            path: "Sources",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "BerryShotMCP",
            dependencies: [
                "BerryShotIPC",
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "MCPServer",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "BerryShotTests",
            dependencies: ["BerryShot"],
            path: "Tests/BerryShotTests"
        ),
        .testTarget(
            name: "BerryShotIPCTests",
            dependencies: ["BerryShotIPC"],
            path: "Tests/BerryShotIPCTests"
        ),
        .testTarget(
            name: "BerryShotMCPTests",
            dependencies: [
                "BerryShotMCP",
                "BerryShotIPC",
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Tests/BerryShotMCPTests"
        )
    ]
)

// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AgentBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgentBar", targets: ["AgentBar"]),
        .library(name: "AgentBarCore", targets: ["AgentBarCore"])
    ],
    targets: [
        .target(
            name: "AgentBarCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "AgentBar",
            dependencies: ["AgentBarCore"],
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "AgentBarCoreTests",
            dependencies: ["AgentBarCore"]
        )
    ]
)

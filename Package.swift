// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LinkLion",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "LinkLion", targets: ["LinkLion"]),
        .executable(name: "linklion", targets: ["LinkLionCLI"]),
        .executable(name: "linklion-mcp", targets: ["LinkLionMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "LinkLion",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .executableTarget(
            name: "LinkLionCLI",
            dependencies: [
                "LinkLion",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "LinkLionMCP",
            dependencies: [
                "LinkLion",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        swiftLanguageModes: [.v6]
    ]
)

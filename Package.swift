// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LinkedInKit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "LinkedInKit", targets: ["LinkLion"]),
        .executable(name: "linkedin", targets: ["LinkedInCLI"]),
        .executable(name: "linkedin-mcp", targets: ["LinkedInMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.7.0"),
        .package(url: "https://github.com/steipete/SweetCookieKit", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "LinkLion",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "LinkedInCLI",
            dependencies: [
                "LinkLion",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SweetCookieKit", package: "SweetCookieKit"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "LinkedInMCP",
            dependencies: [
                "LinkLion",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "LinkedInKitTests",
            dependencies: [
                "LinkLion",
                "LinkedInCLI",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)

// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MacTidy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacTidy", targets: ["MacTidy"])
    ],
    targets: [
        .executableTarget(
            name: "MacTidy",
            path: "Sources/MacTidy"
        ),
        .testTarget(
            name: "MacTidyTests",
            dependencies: ["MacTidy"],
            path: "Tests/MacTidyTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)

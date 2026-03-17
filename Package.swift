// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Teleport",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Teleport", targets: ["Teleport"])
    ],
    targets: [
        .executableTarget(
            name: "Teleport",
            path: "Sources/Teleport"
        )
    ]
)

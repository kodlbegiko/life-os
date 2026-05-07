// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LifeOSNative",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "LifeOSCore", targets: ["LifeOSCore"]),
        .executable(name: "LifeOS", targets: ["LifeOS"]),
    ],
    targets: [
        .target(
            name: "LifeOSCore",
            path: "Sources/LifeOSCore"
        ),
        .executableTarget(
            name: "LifeOS",
            dependencies: ["LifeOSCore"],
            path: "Sources/LifeOS"
        ),
        .testTarget(
            name: "LifeOSCoreTests",
            dependencies: ["LifeOSCore"],
            path: "Tests/LifeOSCoreTests"
        ),
    ]
)

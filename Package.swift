// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Peeker",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Peeker", targets: ["PeekerApp"]),
        .library(name: "PeekerCore", targets: ["PeekerCore"]),
        .library(name: "FunctionCardKit", targets: ["FunctionCardKit"]),
        .library(name: "TimerFeature", targets: ["TimerFeature"]),
        .library(name: "PusherFeature", targets: ["PusherFeature"]),
        .library(name: "PersistenceCore", targets: ["PersistenceCore"]),
        .library(name: "MacPlatform", targets: ["MacPlatform"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "PeekerCore"),
        .target(name: "FunctionCardKit", dependencies: ["PeekerCore"]),
        .target(name: "TimerFeature", dependencies: ["PeekerCore", "FunctionCardKit"]),
        .target(name: "PusherFeature", dependencies: ["PeekerCore", "FunctionCardKit"]),
        .target(
            name: "PersistenceCore",
            dependencies: ["PeekerCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(
            name: "TimerGRDBAdapter",
            dependencies: ["PeekerCore", "TimerFeature", "PersistenceCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(
            name: "PusherGRDBAdapter",
            dependencies: ["PeekerCore", "PusherFeature", "PersistenceCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "MacPlatform", dependencies: ["PeekerCore", "FunctionCardKit"]),
        .executableTarget(
            name: "PeekerApp",
            dependencies: [
                "PeekerCore", "FunctionCardKit", "TimerFeature", "PusherFeature",
                "PersistenceCore", "TimerGRDBAdapter", "PusherGRDBAdapter", "MacPlatform",
            ]
        ),
        .testTarget(name: "PeekerCoreTests", dependencies: ["PeekerCore"]),
        .testTarget(name: "FunctionCardKitTests", dependencies: ["FunctionCardKit", "PeekerCore"]),
        .testTarget(name: "TimerFeatureTests", dependencies: ["TimerFeature", "PeekerCore"]),
        .testTarget(name: "PusherFeatureTests", dependencies: ["PusherFeature", "PeekerCore"]),
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "PersistenceCore", "TimerGRDBAdapter", "PusherGRDBAdapter",
                "TimerFeature", "PusherFeature", "PeekerCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "MacPlatformTests", dependencies: ["MacPlatform", "PeekerCore"]),
    ],
    swiftLanguageModes: [.v6]
)

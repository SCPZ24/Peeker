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
        .library(name: "FeatureRuntimeKit", targets: ["FeatureRuntimeKit"]),
        .library(name: "TimerModule", targets: ["TimerModule"]),
        .library(name: "PusherModule", targets: ["PusherModule"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "PeekerCore"),
        .target(name: "FunctionCardKit", dependencies: ["PeekerCore"]),
        .target(
            name: "TimerFeature",
            dependencies: ["PeekerCore", "FunctionCardKit"],
            path: "Sources/Features/Timer/TimerFeature"
        ),
        .target(
            name: "PusherFeature",
            dependencies: ["PeekerCore", "FunctionCardKit"],
            path: "Sources/Features/Pusher/PusherFeature"
        ),
        .target(
            name: "PersistenceCore",
            dependencies: ["PeekerCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(
            name: "TimerGRDBAdapter",
            dependencies: ["PeekerCore", "TimerFeature", "PersistenceCore", .product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/Features/Timer/TimerGRDBAdapter"
        ),
        .target(
            name: "PusherGRDBAdapter",
            dependencies: ["PeekerCore", "PusherFeature", "PersistenceCore", .product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/Features/Pusher/PusherGRDBAdapter"
        ),
        .target(name: "MacPlatform", dependencies: ["PeekerCore", "FunctionCardKit"]),
        .target(
            name: "FeatureRuntimeKit",
            dependencies: ["PeekerCore", "FunctionCardKit", "PersistenceCore", "MacPlatform"]
        ),
        .target(
            name: "TimerModule",
            dependencies: [
                "FeatureRuntimeKit", "FunctionCardKit", "MacPlatform", "PeekerCore",
                "PersistenceCore", "TimerFeature", "TimerGRDBAdapter",
            ],
            path: "Sources/Features/Timer/TimerModule"
        ),
        .target(
            name: "PusherModule",
            dependencies: [
                "FeatureRuntimeKit", "FunctionCardKit", "MacPlatform", "PeekerCore",
                "PersistenceCore", "PusherFeature", "PusherGRDBAdapter",
            ],
            path: "Sources/Features/Pusher/PusherModule"
        ),
        .executableTarget(
            name: "PeekerApp",
            dependencies: [
                "PeekerCore", "FunctionCardKit", "PersistenceCore", "MacPlatform",
                "FeatureRuntimeKit", "TimerModule", "PusherModule",
            ]
        ),
        .testTarget(name: "PeekerCoreTests", dependencies: ["PeekerCore"]),
        .testTarget(name: "FunctionCardKitTests", dependencies: ["FunctionCardKit", "PeekerCore"]),
        .testTarget(
            name: "TimerFeatureTests",
            dependencies: ["TimerFeature", "PeekerCore"],
            path: "Tests/Features/Timer/TimerFeatureTests"
        ),
        .testTarget(
            name: "PusherFeatureTests",
            dependencies: ["PusherFeature", "PeekerCore"],
            path: "Tests/Features/Pusher/PusherFeatureTests"
        ),
        .testTarget(
            name: "PersistenceCoreTests",
            dependencies: [
                "PersistenceCore", "PeekerCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "TimerGRDBAdapterTests",
            dependencies: [
                "PersistenceCore", "TimerGRDBAdapter", "TimerFeature", "PeekerCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/Features/Timer/TimerGRDBAdapterTests"
        ),
        .testTarget(
            name: "PusherGRDBAdapterTests",
            dependencies: [
                "PersistenceCore", "PusherGRDBAdapter", "PusherFeature", "PeekerCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/Features/Pusher/PusherGRDBAdapterTests"
        ),
        .testTarget(name: "MacPlatformTests", dependencies: ["MacPlatform", "PeekerCore"]),
        .testTarget(
            name: "FeatureRuntimeKitTests",
            dependencies: ["FeatureRuntimeKit", "FunctionCardKit", "PersistenceCore", "MacPlatform", "PeekerCore"]
        ),
        .testTarget(
            name: "TimerModuleTests",
            dependencies: ["TimerModule", "FeatureRuntimeKit", "MacPlatform", "PeekerCore"],
            path: "Tests/Features/Timer/TimerModuleTests"
        ),
        .testTarget(
            name: "PusherModuleTests",
            dependencies: ["PusherModule", "FeatureRuntimeKit", "MacPlatform", "PeekerCore"],
            path: "Tests/Features/Pusher/PusherModuleTests"
        ),
        .testTarget(
            name: "PeekerAppTests",
            dependencies: ["PeekerApp", "FunctionCardKit", "PeekerCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

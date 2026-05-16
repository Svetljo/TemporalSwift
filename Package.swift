// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TemporalSwift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TemporalSwiftCore", targets: ["TemporalSwiftCore"]),
        .library(name: "TemporalSwiftStorage", targets: ["TemporalSwiftStorage"]),
        .library(name: "TemporalSwiftQuery", targets: ["TemporalSwiftQuery"]),
    ],
    targets: [
        .target(
            name: "TemporalSwiftCore",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "TemporalSwiftStorage",
            dependencies: ["TemporalSwiftCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "TemporalSwiftQuery",
            dependencies: ["TemporalSwiftCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "TemporalSwiftCoreTests",
            dependencies: ["TemporalSwiftCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "TemporalSwiftStorageTests",
            dependencies: ["TemporalSwiftCore", "TemporalSwiftStorage"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "TemporalSwiftQueryTests",
            dependencies: ["TemporalSwiftCore", "TemporalSwiftStorage", "TemporalSwiftQuery"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TemporalSwift",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "TemporalSwiftCore", targets: ["TemporalSwiftCore"]),
        .library(name: "TemporalSwiftStorage", targets: ["TemporalSwiftStorage"]),
        .library(name: "TemporalSwiftQuery", targets: ["TemporalSwiftQuery"]),
        .library(name: "TemporalSwiftPersistence", targets: ["TemporalSwiftPersistence"]),
        .library(name: "TemporalSwiftSQLite", targets: ["TemporalSwiftSQLite"]),
    ],
    targets: [
        // MARK: - System library wrapper for SQLite3
        .systemLibrary(
            name: "CSQLite",
            pkgConfig: "sqlite3",
            providers: [
                .apt(["libsqlite3-dev"]),
                .brew(["sqlite"]),
            ]
        ),

        // MARK: - Core library targets
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
        .target(
            name: "TemporalSwiftPersistence",
            dependencies: ["TemporalSwiftCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "TemporalSwiftSQLite",
            dependencies: ["TemporalSwiftCore", "CSQLite"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),

        // MARK: - Test targets
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
        .testTarget(
            name: "TemporalSwiftPersistenceTests",
            dependencies: ["TemporalSwiftCore", "TemporalSwiftStorage", "TemporalSwiftPersistence"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "TemporalSwiftSQLiteTests",
            dependencies: ["TemporalSwiftCore", "TemporalSwiftStorage", "TemporalSwiftSQLite"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)

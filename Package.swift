// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PureZip",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ArchiveCore",
            targets: ["ArchiveCore"]
        ),
        .library(
            name: "ArchiveEngines",
            targets: ["ArchiveEngines"]
        ),
        .library(
            name: "PureZipFinderSupport",
            targets: ["PureZipFinderSupport"]
        ),
        .executable(
            name: "PureZipApp",
            targets: ["PureZipApp"]
        ),
        .executable(
            name: "PureZipArchiveService",
            targets: ["PureZipArchiveService"]
        ),
        .executable(
            name: "PureZipFinderSync",
            targets: ["PureZipFinderSync"]
        ),
        .executable(
            name: "PureZipQuickLook",
            targets: ["PureZipQuickLook"]
        ),
        .executable(
            name: "purezip-cli",
            targets: ["PureZipCLI"]
        )
    ],
    targets: [
        .target(
            name: "ArchiveCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "ArchiveEngines",
            dependencies: ["ArchiveCore"],
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .target(
            name: "PureZipFinderSupport",
            dependencies: ["ArchiveCore"]
        ),
        .executableTarget(
            name: "PureZipApp",
            dependencies: [
                "ArchiveCore",
                "ArchiveEngines",
                "PureZipFinderSupport"
            ]
        ),
        .executableTarget(
            name: "PureZipArchiveService",
            dependencies: [
                "ArchiveCore",
                "ArchiveEngines"
            ]
        ),
        .executableTarget(
            name: "PureZipFinderSync",
            dependencies: [
                "ArchiveCore",
                "PureZipFinderSupport"
            ],
            linkerSettings: [
                .linkedFramework("FinderSync"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "PureZipQuickLook",
            dependencies: [
                "ArchiveCore",
                "ArchiveEngines"
            ],
            linkerSettings: [
                .linkedFramework("Quartz"),
                .linkedFramework("QuickLookUI"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "PureZipCLI",
            dependencies: [
                "ArchiveCore",
                "ArchiveEngines",
                "PureZipFinderSupport"
            ]
        ),
        .testTarget(
            name: "PureZipTests",
            dependencies: [
                "ArchiveCore",
                "ArchiveEngines",
                "PureZipFinderSupport"
            ]
        )
    ]
)

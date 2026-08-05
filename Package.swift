// swift-tools-version: 5.9
// Aurora Lighting Control System — monorepo package (PR1 scaffold)
import PackageDescription

let package = Package(
    name: "Aurora",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AuroraModel", targets: ["AuroraModel"]),
        .library(name: "AuroraCore", targets: ["AuroraCore"]),
        .library(name: "AuroraEngine", targets: ["AuroraEngine"]),
        .library(name: "AuroraMIDI", targets: ["AuroraMIDI"]),
        .library(name: "AuroraOutput", targets: ["AuroraOutput"]),
        .library(name: "AuroraFixtureLib", targets: ["AuroraFixtureLib"]),
        .library(name: "AuroraDiagnostics", targets: ["AuroraDiagnostics"]),
        .library(name: "AuroraUI", targets: ["AuroraUI"]),
        .executable(name: "Aurora", targets: ["Aurora"]),
    ],
    targets: [
        // MARK: - Libraries (dependency edges match system design §3.2 / PR1 doc §6)
        .target(
            name: "AuroraModel"
        ),
        .target(
            name: "AuroraFixtureLib",
            dependencies: ["AuroraModel"],
            resources: [
                .process("Resources"),
            ]
        ),
        .target(
            name: "AuroraOutput",
            linkerSettings: [
                .linkedFramework("Network"),
            ]
        ),
        .target(
            name: "AuroraEngine",
            dependencies: ["AuroraModel", "AuroraOutput"]
        ),
        .target(
            name: "AuroraCore",
            dependencies: ["AuroraModel", "AuroraEngine"]
        ),
        .target(
            name: "AuroraMIDI",
            dependencies: ["AuroraModel"],
            linkerSettings: [
                .linkedFramework("CoreMIDI"),
            ]
        ),
        .target(
            name: "AuroraDiagnostics"
        ),
        .target(
            name: "AuroraUI",
            dependencies: ["AuroraCore", "AuroraModel", "AuroraEngine"]
        ),

        // MARK: - App (design name: AuroraApp)
        .executableTarget(
            name: "Aurora",
            dependencies: [
                "AuroraUI",
                "AuroraCore",
                "AuroraModel",
                "AuroraFixtureLib",
                "AuroraEngine",
                "AuroraOutput",
                "AuroraMIDI",
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "AuroraModelTests",
            dependencies: ["AuroraModel"]
        ),
        .testTarget(
            name: "AuroraCoreTests",
            dependencies: ["AuroraCore", "AuroraModel"]
        ),
        .testTarget(
            name: "AuroraFixtureLibTests",
            dependencies: ["AuroraFixtureLib", "AuroraModel"]
        ),
        .testTarget(
            name: "AuroraUITests",
            dependencies: ["AuroraUI", "AuroraCore", "AuroraModel"]
        ),
        .testTarget(
            name: "AuroraOutputTests",
            dependencies: ["AuroraOutput"]
        ),
        .testTarget(
            name: "AuroraEngineTests",
            dependencies: ["AuroraEngine", "AuroraModel", "AuroraOutput"]
        ),
        .testTarget(
            name: "AuroraMIDITests",
            dependencies: ["AuroraMIDI"]
        ),
        .testTarget(
            name: "AuroraPackageSmokeTests",
            dependencies: [
                "AuroraModel",
                "AuroraCore",
                "AuroraEngine",
                "AuroraMIDI",
                "AuroraOutput",
                "AuroraFixtureLib",
                "AuroraDiagnostics",
                "AuroraUI",
            ]
        ),
    ]
)

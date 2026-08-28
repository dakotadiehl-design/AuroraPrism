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
        .library(name: "AuroraMusical", targets: ["AuroraMusical"]),
        .library(name: "AuroraOutput", targets: ["AuroraOutput"]),
        .library(name: "AuroraFixtureLib", targets: ["AuroraFixtureLib"]),
        .library(name: "AuroraDiagnostics", targets: ["AuroraDiagnostics"]),
        .library(name: "AuroraUI", targets: ["AuroraUI"]),
        .executable(name: "Aurora", targets: ["Aurora"]),
    ],
    dependencies: [
        .package(name: "AuroraDesignSystem", path: "../AuroraDesignSystem"),
        .package(
            url: "https://github.com/dakotadiehl-design/rACP.git",
            revision: "b023590b926c2c4c3a111275d847c997fd511514"
        ),
    ],
    targets: [
        // MARK: - Libraries (dependency edges match system design §3.2 / PR1 doc §6)
        .target(
            name: "AuroraModel",
            dependencies: ["AuroraDiagnostics"]
        ),
        // Musical Engine foundation: no CoreMIDI. Timing/provider runtime only.
        .target(
            name: "AuroraMusical",
            dependencies: ["AuroraDiagnostics"]
        ),
        .target(
            name: "AuroraFixtureLib",
            dependencies: ["AuroraModel", "AuroraDiagnostics"],
            resources: [
                .process("Resources"),
            ]
        ),
        .target(
            name: "AuroraOutput",
            dependencies: ["AuroraModel", "AuroraDiagnostics"],
            linkerSettings: [
                .linkedFramework("Network"),
            ]
        ),
        .target(
            name: "AuroraEngine",
            dependencies: ["AuroraModel", "AuroraOutput", "AuroraMusical", "AuroraDiagnostics"]
        ),
        .target(
            name: "AuroraCore",
            dependencies: ["AuroraModel", "AuroraEngine", "AuroraDiagnostics"]
        ),
        .target(
            name: "AuroraMIDI",
            dependencies: ["AuroraModel", "AuroraMusical", "AuroraDiagnostics"],
            linkerSettings: [
                .linkedFramework("CoreMIDI"),
                .linkedFramework("Network"),
            ]
        ),
        .target(
            name: "AuroraDiagnostics"
        ),
        .target(
            // AuroraMIDI: MIDIMappingsPanel uses ShowAction (declared dependency; avoids illicit import).
            // Still no AuroraOutput dependency (DMX stays out of UI).
            name: "AuroraUI",
            dependencies: [
                "AuroraCore",
                "AuroraModel",
                "AuroraEngine",
                "AuroraMIDI",
                "AuroraMusical",
                "AuroraFixtureLib",
                "AuroraDiagnostics",
                .product(name: "AuroraDesignSystem", package: "AuroraDesignSystem"),
            ],
            resources: [
                .copy("Resources/StageAssets"),
            ]
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
                "AuroraMusical",
                "AuroraDiagnostics",
                .product(name: "ReasonableACP", package: "rACP"),
                .product(name: "AuroraDesignSystem", package: "AuroraDesignSystem"),
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "AuroraRACPTests",
            dependencies: [
                "Aurora",
                "AuroraModel",
                "AuroraOutput",
                .product(name: "ReasonableACP", package: "rACP"),
            ]
        ),
        .testTarget(
            name: "AuroraDiagnosticsTests",
            dependencies: ["AuroraDiagnostics", "AuroraEngine", "AuroraModel", "AuroraOutput"]
        ),
        .testTarget(
            name: "AuroraModelTests",
            dependencies: ["AuroraModel", "AuroraDiagnostics"]
        ),
        .testTarget(
            name: "AuroraMusicalTests",
            dependencies: ["AuroraMusical", "AuroraDiagnostics"]
        ),
        .testTarget(
            name: "AuroraCoreTests",
            dependencies: ["AuroraCore", "AuroraModel", "AuroraDiagnostics"]
        ),
        .testTarget(
            name: "AuroraFixtureLibTests",
            dependencies: ["AuroraFixtureLib", "AuroraModel", "AuroraDiagnostics"]
        ),
        .testTarget(
            name: "AuroraUITests",
            dependencies: [
                "AuroraUI",
                "AuroraCore",
                "AuroraModel",
                "AuroraDiagnostics",
                .product(name: "AuroraDesignSystem", package: "AuroraDesignSystem"),
            ]
        ),
        .testTarget(
            name: "AuroraOutputTests",
            dependencies: ["AuroraOutput", "AuroraEngine", "AuroraModel", "AuroraDiagnostics"]
        ),
        .testTarget(
            name: "AuroraEngineTests",
            dependencies: ["AuroraEngine", "AuroraModel", "AuroraOutput", "AuroraDiagnostics", "AuroraMusical"]
        ),
        .testTarget(
            name: "AuroraMIDITests",
            dependencies: ["AuroraMIDI", "AuroraMusical", "AuroraDiagnostics"]
        ),
        .testTarget(
            name: "AuroraPackageSmokeTests",
            dependencies: [
                "AuroraModel",
                "AuroraCore",
                "AuroraEngine",
                "AuroraMIDI",
                "AuroraMusical",
                "AuroraOutput",
                "AuroraFixtureLib",
                "AuroraDiagnostics",
                "AuroraUI",
            ]
        ),
    ]
)

// swift-tools-version: 6.2
import PackageDescription

// Every target compiles in Swift 6 mode (the default for this tools version)
// with strict concurrency, and a warning fails the build.
let strict: [SwiftSetting] = [
    .treatAllWarnings(as: .error)
]

let package = Package(
    name: "Beam",
    platforms: [.macOS(.v14)],
    targets: [
        // Built from vendor/ghostty by scripts/build-ghostty.sh.
        .binaryTarget(
            name: "GhosttyKit",
            path: "vendor/ghostty/macos/GhosttyKit.xcframework"
        ),
        // libghostty-vt, which GhosttyKit does not export. Also built by
        // scripts/build-ghostty.sh.
        .binaryTarget(
            name: "GhosttyVt",
            path: "vendor/ghostty/macos/GhosttyVt.xcframework"
        ),
        // Pure Swift: models, state machines, persistence. No AppKit, no GhosttyKit.
        .target(
            name: "BeamCore",
            swiftSettings: strict
        ),
        .executableTarget(
            name: "Beam",
            dependencies: ["BeamCore", "GhosttyKit"],
            // An AppKit app lives on the main thread; code that runs elsewhere
            // opts out with `nonisolated`.
            swiftSettings: strict + [.defaultIsolation(MainActor.self)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedLibrary("c++"),
            ]
        ),
        // The `beam` helper agent hooks run, bundled as
        // Beam.app/Contents/Helpers/beam. Named apart from `Beam` because the
        // two binaries share a build folder, and APFS ignores case.
        .executableTarget(
            name: "BeamCLI",
            dependencies: ["BeamCore"],
            swiftSettings: strict
        ),
        // beamd, bundled as Beam.app/Contents/Helpers/beamd: owns every pane's
        // pty, so shells and agents outlive Beam (docs/sessions.md). It runs
        // everything on the main queue, like the app.
        .executableTarget(
            name: "BeamDaemon",
            dependencies: ["BeamCore", "GhosttyVt", "SessionSpawn"],
            swiftSettings: strict + [.defaultIsolation(MainActor.self)],
            linkerSettings: [.linkedLibrary("c++")]
        ),
        // beam-attach, bundled as Beam.app/Contents/Helpers/beam-attach: the
        // command each pane's terminal runs. C, so it starts at once and the
        // one process per pane stays small.
        .executableTarget(
            name: "BeamAttach",
            cSettings: [.treatAllWarnings(as: .error), .enableWarning("all"), .enableWarning("extra")]
        ),
        // How beamd starts a session's shell: C, because it forks, which
        // Swift does not allow (see SessionSpawn.c).
        .target(
            name: "SessionSpawn",
            cSettings: [.treatAllWarnings(as: .error), .enableWarning("all"), .enableWarning("extra")]
        ),
        .testTarget(
            name: "BeamCoreTests",
            dependencies: ["BeamCore"],
            swiftSettings: strict
        ),
        .testTarget(
            name: "SessionSpawnTests",
            dependencies: ["SessionSpawn"],
            swiftSettings: strict
        ),
        // The beamd code that calls libghostty-vt, so these run it for real.
        .testTarget(
            name: "BeamDaemonTests",
            dependencies: ["BeamDaemon"],
            swiftSettings: strict
        ),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PacManArcade",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PacManArcade", targets: ["PacManArcade"])
    ],
    targets: [
        .target(
            name: "PacManCore"
        ),
        .executableTarget(
            name: "PacManArcade",
            dependencies: ["PacManCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AVFoundation")
            ]
        ),
        .executableTarget(
            name: "PacManChecks",
            dependencies: ["PacManCore"],
            path: "Checks"
        )
    ]
)

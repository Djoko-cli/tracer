// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tracer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tracer", targets: ["Tracer"]),
        .executable(name: "tracer-cli", targets: ["tracer-cli"]),
        .library(name: "TracerCore", targets: ["TracerCore"]),
    ],
    targets: [
        .target(
            name: "TracerCore",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        ),
        .executableTarget(name: "Tracer", dependencies: ["TracerCore"]),
        .executableTarget(name: "tracer-cli", dependencies: ["TracerCore"]),
        .testTarget(name: "TracerCoreTests", dependencies: ["TracerCore"]),
    ]
)

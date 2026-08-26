// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mouseless",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MouselessRuntime", targets: ["MouselessRuntime"]),
        .executable(name: "Mouseless", targets: ["MouselessApp"])
    ],
    targets: [
        .target(name: "MouselessRuntime"),
        .executableTarget(name: "MouselessApp", dependencies: ["MouselessRuntime"]),
        .testTarget(name: "MouselessRuntimeTests", dependencies: ["MouselessRuntime"])
    ]
)

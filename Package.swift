// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Keyveer",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KeyveerRuntime", targets: ["KeyveerRuntime"]),
        .executable(name: "Keyveer", targets: ["KeyveerApp"])
    ],
    targets: [
        .target(name: "KeyveerRuntime"),
        .executableTarget(name: "KeyveerApp", dependencies: ["KeyveerRuntime"]),
        .testTarget(name: "KeyveerRuntimeTests", dependencies: ["KeyveerRuntime"])
    ]
)

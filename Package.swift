// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MouseMover",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "MouseMover", targets: ["MouseMover"])
    ],
    targets: [
        .executableTarget(name: "MouseMover")
    ]
)

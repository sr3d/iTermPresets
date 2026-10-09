// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "iTermPresets",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "iTermPresets", path: "Sources/iTermPresets")
    ]
)

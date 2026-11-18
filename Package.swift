// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Polux",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Polux",
            path: "Sources/Polux"
        ),
        .testTarget(
            name: "PoluxTests",
            dependencies: ["Polux"],
            path: "Tests/PoluxTests"
        )
    ]
)

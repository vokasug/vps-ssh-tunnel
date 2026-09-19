// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VpsSshTunnel",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VpsSshTunnel",
            path: "Sources/VpsSshTunnel"
        )
    ]
)

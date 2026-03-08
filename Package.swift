// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenAuthenticator",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "OpenAuthenticator")
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopMask",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SlackHarder", targets: ["DesktopMask"])
    ],
    targets: [
        .executableTarget(name: "DesktopMask"),
        .testTarget(name: "DesktopMaskTests", dependencies: ["DesktopMask"])
    ]
)

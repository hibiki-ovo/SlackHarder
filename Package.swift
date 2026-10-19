// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopMask",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SlackHarder", targets: ["DesktopMask"])
    ],
    targets: [
        .executableTarget(name: "DesktopMask", resources: [.process("Resources")]),
        .testTarget(name: "DesktopMaskTests", dependencies: ["DesktopMask"])
    ]
)

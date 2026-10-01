// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MouseTeleportation",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MouseTeleportation", targets: ["MouseTeleportation"])],
    targets: [
        .target(name: "TeleportCore"),
        .executableTarget(name: "MouseTeleportation", dependencies: ["TeleportCore"]),
        .testTarget(name: "TeleportCoreTests", dependencies: ["TeleportCore"]),
    ]
)

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ZoneCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "ZoneCore", targets: ["ZoneCore"])],
    targets: [
        .target(name: "ZoneCore"),
        .testTarget(name: "ZoneCoreTests", dependencies: ["ZoneCore"])
    ]
)

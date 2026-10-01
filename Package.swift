// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HaloChat",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "HaloChat", targets: ["HaloChat"]),
    ],
    targets: [
        .target(name: "HaloChat"),
        .testTarget(name: "HaloChatTests", dependencies: ["HaloChat"]),
    ]
)

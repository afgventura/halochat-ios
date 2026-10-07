// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HaloChat",
    defaultLocalization: "en",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        // Core SDK only: networking, auth, realtime, push, attachments. Your app owns the UI.
        .library(name: "HaloChat", targets: ["HaloChat"]),
        // Drop-in chat screen (UIKit, iOS 15+) on top of the core.
        .library(name: "HaloChatUI", targets: ["HaloChatUI"]),
    ],
    targets: [
        .target(name: "HaloChat"),
        .target(
            name: "HaloChatUI",
            dependencies: ["HaloChat"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "HaloChatTests", dependencies: ["HaloChat"]),
    ]
)

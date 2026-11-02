// swift-tools-version:5.9
// LQCore: platform-independent game logic for Language Quest.
// No UIKit, SwiftUI, SpriteKit, networking or third-party dependencies, so the
// whole package builds and tests on macOS, iOS and Linux.
import PackageDescription

let package = Package(
    name: "LQCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "LQCore", targets: ["LQCore"])
    ],
    targets: [
        .target(
            name: "LQCore",
            resources: [.copy("Resources/Content")]
        ),
        .testTarget(
            name: "LQCoreTests",
            dependencies: ["LQCore"]
        )
    ]
)

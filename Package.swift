// swift-tools-version: 5.9
import PackageDescription

// The app itself is built from Hike.xcodeproj. This package exists so the pure-Swift
// core (geometry, GPX, tile maths, service response decoding) can be unit tested with
// `swift test`, without a simulator.
let package = Package(
    name: "HikeCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    targets: [
        .target(name: "HikeCore", path: "Hike/Core"),
        .testTarget(name: "HikeCoreTests", dependencies: ["HikeCore"], path: "Tests/HikeCoreTests"),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AscendKit",
    // macOS is listed so the logic layer can be unit-tested from the command
    // line without Xcode. The app targets are iOS 16 / watchOS 9.
    platforms: [.iOS(.v16), .watchOS(.v9), .macOS(.v13)],
    products: [
        .library(name: "AscendKit", targets: ["AscendKit"])
    ],
    targets: [
        .target(name: "AscendKit"),
        .testTarget(name: "AscendKitTests", dependencies: ["AscendKit"])
    ]
)

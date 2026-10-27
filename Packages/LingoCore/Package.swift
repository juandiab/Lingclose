// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LingoCore",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "LingoCore", targets: ["LingoCore"]),
    ],
    targets: [
        .target(name: "LingoCore"),
        .testTarget(name: "LingoCoreTests", dependencies: ["LingoCore"]),
    ],
    swiftLanguageModes: [.v6]
)

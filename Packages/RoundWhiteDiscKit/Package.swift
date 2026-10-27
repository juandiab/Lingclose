// swift-tools-version: 5.10
// Fork de RoundWhiteDiscKit (MIT). Base: commit 7dd6396f04371330d35799c88b9cba105a200180 (2026-10-24 08:04:30 -0500). Cambios Lingo: ver docs/FORK_RWDK.md
import PackageDescription

let package = Package(
    name: "RoundWhiteDiscKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "RoundWhiteDiscKit", targets: ["RoundWhiteDiscKit"]),
    ],
    targets: [
        .target(
            name: "RoundWhiteDiscKit",
            path: "Sources/RoundWhiteDiscKit",
            resources: [
                .process("Resources/Localizations"),
            ]
        ),
        .testTarget(
            name: "RoundWhiteDiscKitTests",
            dependencies: ["RoundWhiteDiscKit"],
            path: "Tests/RoundWhiteDiscKitTests"
        ),
    ]
)

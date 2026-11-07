// swift-tools-version:5.9
import PackageDescription

// Builds with the Command Line Tools alone (no Xcode.app needed): `swift build`.
// scripts/bundle.sh wraps the result into "Murmr Stream.app".
let package = Package(
    name: "MurmrStream",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MurmrStream", path: "Sources/MurmrStream"),
    ]
)

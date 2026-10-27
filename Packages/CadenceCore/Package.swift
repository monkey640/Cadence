// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CadenceCore",
    // No `platforms:` clause: CadenceCore is pure Swift with no Apple-framework
    // dependency, so it builds on macOS for command-line testing AND is consumed
    // by the iOS 18 / watchOS 11 targets, whose deployment targets are set in the
    // Xcode project. Keeping it platform-agnostic is what makes `swift test` work.
    products: [
        .library(name: "CadenceCore", targets: ["CadenceCore"])
    ],
    targets: [
        .target(name: "CadenceCore"),
        .testTarget(name: "CadenceCoreTests", dependencies: ["CadenceCore"])
    ]
)

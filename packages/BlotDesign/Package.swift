// swift-tools-version: 6.2
import PackageDescription

/// Shared look of the Mac and iPhone apps: tokens, theme choice, control styles, data states
/// and the Blot character. Platform navigation stays in the apps.
let package = Package(
    name: "BlotDesign",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [.library(name: "BlotDesign", targets: ["BlotDesign"])],
    dependencies: [],
    targets: [
        .target(name: "BlotDesign", resources: [.process("Resources")],
                swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "BlotDesignTests", dependencies: ["BlotDesign"],
                    swiftSettings: [.defaultIsolation(MainActor.self)]),
    ]
)

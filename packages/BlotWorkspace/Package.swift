// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BlotWorkspace",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [.library(name: "BlotWorkspace", targets: ["BlotWorkspace"])],
    dependencies: [.package(path: "../BlotDomain")],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "BlotWorkspace", dependencies: ["BlotDomain", "CSQLite"]),
        .testTarget(name: "BlotWorkspaceTests", dependencies: ["BlotWorkspace"]),
    ]
)

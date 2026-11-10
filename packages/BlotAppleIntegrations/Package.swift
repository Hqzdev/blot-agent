// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BlotAppleIntegrations",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [.library(name: "BlotAppleIntegrations", targets: ["BlotAppleIntegrations"])],
    dependencies: [.package(path: "../BlotWorkspace"), .package(path: "../BlotDomain")],
    targets: [
        .target(name: "BlotAppleIntegrations", dependencies: ["BlotWorkspace", "BlotDomain"]),
        .testTarget(name: "BlotAppleIntegrationsTests", dependencies: ["BlotAppleIntegrations"]),
    ]
)

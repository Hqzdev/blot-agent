// swift-tools-version: 6.2
import PackageDescription

let package = Package(name: "CloudWireVerification", platforms: [.macOS(.v26)],
    dependencies: [.package(path: "..")], targets: [
        .executableTarget(name: "DirectModelVerification", dependencies: [.product(name: "BlotWorkspace", package: "BlotWorkspace")]),
        .executableTarget(name: "CloudWireVerification", dependencies: [.product(name: "BlotWorkspace", package: "BlotWorkspace")]),
    ])

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BlotWidgetSupport",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [.library(name: "BlotWidgetSupport", targets: ["BlotWidgetSupport"])],
    dependencies: [.package(path: "../BlotDomain")],
    targets: [
        .target(name: "BlotWidgetSupport", dependencies: ["BlotDomain"]),
        .testTarget(name: "BlotWidgetSupportTests", dependencies: ["BlotWidgetSupport"]),
    ]
)

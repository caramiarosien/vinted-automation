// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WerkstattCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "WerkstattCore", targets: ["WerkstattCore"])],
    targets: [
        .target(name: "WerkstattCore"),
        .testTarget(name: "WerkstattCoreTests", dependencies: ["WerkstattCore"])
    ],
    swiftLanguageVersions: [.v5]
)

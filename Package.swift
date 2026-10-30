// swift-tools-version: 6.0
import PackageDescription

// NekularityKit holds everything except the SwiftUI screens, so it can be
// tested with `swift test` on macOS. The app target (project.yml) depends on
// it. VeneraCatCore.xcframework is built from VeneraCat Core by
// scripts/fetch-core.sh into Vendor/.
let package = Package(
    name: "Nekularity",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "NekularityKit", targets: ["NekularityKit"])],
    targets: [
        .binaryTarget(name: "VeneraCatCore", path: "Vendor/VeneraCatCore.xcframework"),
        .target(name: "NekularityKit", dependencies: ["VeneraCatCore"]),
        .testTarget(name: "NekularityKitTests", dependencies: ["NekularityKit"]),
    ],
    swiftLanguageModes: [.v6]
)

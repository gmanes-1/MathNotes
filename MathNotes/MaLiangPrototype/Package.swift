// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MaLiang",
    platforms: [.iOS(.v13)],
    products: [.library(name: "MaLiang", targets: ["MaLiang"])],
    targets: [
        .target(
            name: "MaLiang",
            path: "Sources/MaLiang",
            resources: [.process("Resources")]
        )
    ],
    swiftLanguageVersions: [.v5]
)

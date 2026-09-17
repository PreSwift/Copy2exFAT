// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Copy2exFAT",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Copy2exFAT", targets: ["Copy2exFAT"])
    ],
    targets: [
        .executableTarget(
            name: "Copy2exFAT",
            path: "Sources"
        )
    ]
)

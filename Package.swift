// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clairiere",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Clairiere", targets: ["Clairiere"])
    ],
    targets: [
        .executableTarget(name: "Clairiere")
    ]
)

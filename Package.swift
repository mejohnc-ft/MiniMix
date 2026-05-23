// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiniMix",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MiniMix", targets: ["MiniMix"])
    ],
    targets: [
        .executableTarget(
            name: "MiniMix",
            exclude: ["Resources/MiniMix-Info.plist"]
        )
    ]
)

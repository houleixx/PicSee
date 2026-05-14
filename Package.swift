// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PicSee",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PicSee", targets: ["PicSee"])
    ],
    targets: [
        .executableTarget(
            name: "PicSee",
            path: "Sources/PicSee"
        ),
        .testTarget(
            name: "PicSeeTests",
            dependencies: ["PicSee"],
            path: "Tests/PicSeeTests"
        )
    ]
)

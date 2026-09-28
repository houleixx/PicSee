// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PicSee",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PicSee", targets: ["PicSee"])
    ],
    targets: [
        .executableTarget(
            name: "PicSee",
            path: "Sources/PicSee",
            resources: [
                .process("Resources/Phosphor.xcassets"),
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj")
            ]
        ),
        .testTarget(
            name: "PicSeeTests",
            dependencies: ["PicSee"],
            path: "Tests/PicSeeTests"
        )
    ]
)

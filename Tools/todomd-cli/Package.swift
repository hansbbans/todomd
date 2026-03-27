// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "todomd-cli",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "TodoMDCLI",
            dependencies: [
                .product(name: "TodoMDCore", package: "TodoMD"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .executableTarget(
            name: "todomd",
            dependencies: ["TodoMDCLI"],
            path: "Sources/todomd"
        ),
        .testTarget(
            name: "TodoMDCLITests",
            dependencies: [
                "TodoMDCLI",
                .product(name: "TodoMDCore", package: "TodoMD")
            ]
        )
    ]
)

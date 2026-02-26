// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TodoMD",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TodoMDCore", targets: ["TodoMDCore"]),
        .executable(name: "TodoMDBenchmarks", targets: ["TodoMDBenchmarks"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.1")
    ],
    targets: [
        .target(
            name: "TodoMDCore",
            dependencies: ["Yams"],
            path: "Sources/TodoMDCore"
        ),
        .testTarget(
            name: "TodoMDCoreTests",
            dependencies: ["TodoMDCore"],
            path: "Tests/TodoMDCoreTests"
        ),
        .executableTarget(
            name: "TodoMDBenchmarks",
            dependencies: ["TodoMDCore"],
            path: "Tools/TodoMDBenchmarks"
        )
    ]
)

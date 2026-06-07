// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YourUsual",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/realm/SwiftLint.git", from: "0.57.0"),
    ],
    targets: [
        .executableTarget(
            name: "YourUsual",
            path: "Sources",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint"),
            ]
        ),
        .testTarget(
            name: "YourUsualTests",
            dependencies: ["YourUsual"],
            path: "Tests"
        ),
    ]
)

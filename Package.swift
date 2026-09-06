// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Takat",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Takat", targets: ["Takat"])
    ],
    targets: [
        .executableTarget(
            name: "Takat",
            path: "Sources/Takat"
        ),
        .testTarget(
            name: "TakatTests",
            dependencies: ["Takat"],
            path: "Tests/TakatTests"
        )
    ]
)

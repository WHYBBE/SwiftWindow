// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwiftWindow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SwiftWindow", targets: ["SwiftWindow"])
    ],
    targets: [
        .executableTarget(
            name: "SwiftWindow",
            path: "Sources/SwiftWindow"
        )
    ]
)

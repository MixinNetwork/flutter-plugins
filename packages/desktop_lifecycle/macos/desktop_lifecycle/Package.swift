// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "desktop_lifecycle",
    platforms: [
        .macOS("10.11")
    ],
    products: [
        .library(name: "desktop-lifecycle", targets: ["desktop_lifecycle"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "desktop_lifecycle",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)

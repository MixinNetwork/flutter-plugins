// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "fts5_simple",
    platforms: [
        .macOS("10.11")
    ],
    products: [
        .library(name: "fts5-simple", targets: ["fts5_simple"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .binaryTarget(
            name: "libsimple",
            path: "Libs/libsimple.xcframework"
        ),
        .target(
            name: "fts5_simple",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "libsimple"
            ]
        )
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ogg_opus_player",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15")
    ],
    products: [
        .library(name: "ogg-opus-player", targets: ["ogg_opus_player"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .binaryTarget(name: "libogg", path: "Frameworks/libogg.xcframework"),
        .binaryTarget(name: "libopus", path: "Frameworks/libopus.xcframework"),
        .binaryTarget(name: "libopusenc", path: "Frameworks/libopusenc.xcframework"),
        .binaryTarget(name: "libopusfile", path: "Frameworks/libopusfile.xcframework"),
        .target(
            name: "ogg_opus_player_c",
            dependencies: ["libogg", "libopus", "libopusenc", "libopusfile"],
            publicHeadersPath: "include/ogg_opus_player_c"
        ),
        .target(
            name: "ogg_opus_player",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "ogg_opus_player_c"
            ]
        )
    ]
)

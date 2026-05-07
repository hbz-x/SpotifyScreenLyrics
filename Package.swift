// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScreenLyrics",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ScreenLyrics", targets: ["ScreenLyricsApp"]),
        .library(name: "ScreenLyricsCore", targets: ["ScreenLyricsCore"])
    ],
    targets: [
        .target(
            name: "ScreenLyricsCore"
        ),
        .executableTarget(
            name: "ScreenLyricsApp",
            dependencies: ["ScreenLyricsCore"]
        ),
        .testTarget(
            name: "ScreenLyricsCoreTests",
            dependencies: ["ScreenLyricsCore"]
        )
    ]
)

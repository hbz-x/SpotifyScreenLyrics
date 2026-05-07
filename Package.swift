// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SpotifyScreenLyrics",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SpotifyScreenLyrics", targets: ["SpotifyScreenLyricsApp"]),
        .library(name: "SpotifyScreenLyricsCore", targets: ["SpotifyScreenLyricsCore"])
    ],
    targets: [
        .target(
            name: "SpotifyScreenLyricsCore"
        ),
        .executableTarget(
            name: "SpotifyScreenLyricsApp",
            dependencies: ["SpotifyScreenLyricsCore"]
        ),
        .testTarget(
            name: "SpotifyScreenLyricsCoreTests",
            dependencies: ["SpotifyScreenLyricsCore"]
        )
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LucidBanner",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "LucidBanner",
            targets: ["LucidBanner"]
        ),
    ],
    targets: [
        .target(
            name: "LucidBanner",
            dependencies: [],
            path: "Sources/LucidBanner"
        ),
    ]
)

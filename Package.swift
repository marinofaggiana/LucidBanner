// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LucidBanner",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "LucidBanner",
            targets: ["LucidBanner"]
        )
    ],
    targets: [
        .target(
            name: "LucidBanner",
            path: "Sources/LucidBanner"
        )
    ]
)

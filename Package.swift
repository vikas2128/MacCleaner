// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "MacCleaner",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "MacCleaner",
            path: "Sources"
        )
    ]
)

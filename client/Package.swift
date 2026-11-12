// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Dingdong",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Dingdong",
            path: "Sources/Dingdong"
        )
    ]
)

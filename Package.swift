// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YTDLPro",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "YTDLPro", targets: ["YTDLPro"])
    ],
    targets: [
        .executableTarget(name: "YTDLPro")
    ],
    swiftLanguageModes: [.v5]
)
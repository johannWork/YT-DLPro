// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YTDLPro",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "YT-DLPro", targets: ["YTDLPro"])
    ],
    targets: [
        .executableTarget(name: "YTDLPro"),
        .testTarget(name: "YTDLProTests", dependencies: ["YTDLPro"])
    ],
    swiftLanguageModes: [.v5]
)
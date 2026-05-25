// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScopeKit",
    platforms: [.iOS(.v14), .macOS(.v11)],
    products: [
        .library(name: "ScopeKit", targets: ["ScopeKit"]),
    ],
    targets: [
        .target(
            name: "ScopeKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)


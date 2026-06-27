// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkillManager",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
        .package(url: "https://github.com/raspu/Highlightr", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SkillManager",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Highlightr", package: "Highlightr"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InventoryCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "InventoryCore", targets: ["InventoryCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "InventoryCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: ".",
            exclude: [
                "App",
                "Features",
                "Shared",
                "Tests",
                "InventoryAI.xcodeproj",
                "Package.swift",
                "project.yml",
                "scripts",
                ".DS_Store"
            ],
            sources: [
                "Models",
                "Persistence",
                "Repositories",
                "Services",
                "UseCases"
            ]
        ),
        .testTarget(
            name: "InventoryCoreTests",
            dependencies: ["InventoryCore"],
            path: "Tests/InventoryCoreTests"
        )
    ]
)

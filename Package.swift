// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ShoevSpell",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ShoevSpell", targets: ["ShoevSpell"])],
    targets: [
        .executableTarget(
            name: "ShoevSpell",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(name: "ShoevSpellTests", dependencies: ["ShoevSpell"])
    ]
)

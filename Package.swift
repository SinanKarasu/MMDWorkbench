// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MMDWorkbench",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "MMDWorkbench", targets: ["MMDWorkbench"]),
    ],
    targets: [
        .target(
            name: "MMDWorkbench",
            resources: [.process("Resources")]
        ),
    ]
)

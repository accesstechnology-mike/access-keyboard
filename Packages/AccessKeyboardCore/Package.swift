// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AccessKeyboardCore",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(name: "AccessKeyboardCore", type: .static, targets: ["AccessKeyboardCore"])
    ],
    targets: [
        .target(
            name: "AccessKeyboardCore",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "AccessKeyboardCoreTests",
            dependencies: ["AccessKeyboardCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)

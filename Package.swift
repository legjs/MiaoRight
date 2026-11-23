// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiaoRight",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "MiaoRightShared",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "MiaoRightKit",
            dependencies: ["MiaoRightShared"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "MiaoRightApp",
            dependencies: ["MiaoRightKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "MiaoRightFinder",
            dependencies: ["MiaoRightShared"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(name: "CArchive", linkerSettings: [.linkedLibrary("archive")]),
        .target(name: "MiaoRightArchivePreviewKit", dependencies: ["CArchive"]),
        .executableTarget(
            name: "MiaoRightArchivePreview",
            dependencies: ["MiaoRightShared", "MiaoRightArchivePreviewKit"]
        ),
        .testTarget(
            name: "MiaoRightTests",
            dependencies: ["MiaoRightKit", "MiaoRightShared", "MiaoRightArchivePreviewKit"],
            exclude: ["Fixtures"]
        )
    ]
)

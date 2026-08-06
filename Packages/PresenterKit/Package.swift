// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PresenterKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SlideKit", targets: ["SlideKit"]),
        .library(name: "MirrorKit", targets: ["MirrorKit"]),
        .library(name: "PresenterCore", targets: ["PresenterCore"]),
    ],
    targets: [
        .target(name: "SlideKit"),
        .target(name: "MirrorKit"),
        .target(name: "PresenterCore", dependencies: ["SlideKit", "MirrorKit"]),
        .testTarget(
            name: "SlideKitTests",
            dependencies: ["SlideKit"],
            // Hand-built .pptx fixtures, reached via Bundle.module. `.copy`
            // rather than `.process` because these are exact byte layouts —
            // processing could re-encode them and the compression method of an
            // entry is part of what the tests assert.
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "MirrorKitTests", dependencies: ["MirrorKit"]),
        .testTarget(name: "PresenterCoreTests", dependencies: ["PresenterCore"]),
    ]
)

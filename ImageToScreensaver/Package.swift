// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ImageToScreensaver",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ImageToScreensaver",
            resources: [
                .copy("Resources/ScreensaverStub.exe")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)

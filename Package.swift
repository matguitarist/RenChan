// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RenChan",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        // The Log page's viewer, shared by my Mac apps.
        .package(url: "https://github.com/matguitarist/LogKit", from: "0.6.0"),
        // Covers as small HEIC, thumbnails and their cache, shared by my apps.
        .package(url: "https://github.com/matguitarist/PictureKit", from: "0.2.0"),
        // Runs ditto, tar, zip and the like without blocking or hanging, shared by my Mac apps.
        .package(url: "https://github.com/matguitarist/ProcessKit", from: "0.1.1"),
        // Zips with Zip Slip checks, unpacked beside the target and moved in whole, shared by my Mac apps.
        .package(url: "https://github.com/matguitarist/ArchiveKit", from: "0.1.1"),
        // Downloads with progress, retries, resume and a SHA-256 check, shared by my apps.
        .package(url: "https://github.com/matguitarist/DownloadKit", from: "0.1.0"),
    ],
    targets: [
        // Ren'Py detection, runtimes, launching and mods, with no SwiftUI, so tests run without the app.
        .target(name: "RenChanKit", dependencies: [.product(name: "LogKit", package: "LogKit"),
                                                  .product(name: "PictureKit", package: "PictureKit"),
                                                  .product(name: "ProcessKit", package: "ProcessKit"),
                                                  .product(name: "ArchiveKit", package: "ArchiveKit"),
                                                  .product(name: "DownloadKit", package: "DownloadKit")]),
        .executableTarget(
            name: "RenChan",
            dependencies: ["RenChanKit", .product(name: "Sparkle", package: "Sparkle"),
                           .product(name: "LogKitUI", package: "LogKit"),
                           .product(name: "PictureKitUI", package: "PictureKit"),
                           .product(name: "ProcessKit", package: "ProcessKit")],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // Sparkle.framework sits in Contents/Frameworks (build.sh copies it).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "RenChanKitTests", dependencies: ["RenChanKit", .product(name: "LogKit", package: "LogKit"),
                                                           .product(name: "PictureKit", package: "PictureKit"),
                                                           .product(name: "ProcessKit", package: "ProcessKit"),
                                                           .product(name: "DownloadKit", package: "DownloadKit")]),
    ]
)

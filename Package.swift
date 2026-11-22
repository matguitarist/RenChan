// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RenChan",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        // The Log page's viewer, shared by my Mac apps.
        .package(url: "https://github.com/matguitarist/LogKit", from: "0.6.0"),
    ],
    targets: [
        // Ren'Py detection, runtimes, launching and mods, with no SwiftUI, so tests run without the app.
        .target(name: "RenChanKit", dependencies: [.product(name: "LogKit", package: "LogKit")]),
        .executableTarget(
            name: "RenChan",
            dependencies: ["RenChanKit", .product(name: "Sparkle", package: "Sparkle"),
                           .product(name: "LogKitUI", package: "LogKit")],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // Sparkle.framework sits in Contents/Frameworks (build.sh copies it).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "RenChanKitTests", dependencies: ["RenChanKit", .product(name: "LogKit", package: "LogKit")]),
    ]
)

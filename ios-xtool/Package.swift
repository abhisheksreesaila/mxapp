// swift-tools-version: 6.0
// HelloMojo: a SwiftUI skin whose logic lives in Mojo (M5, iOS from Linux via xtool).
// Status: written but NOT yet built; the first xtool build is the experiment.
import PackageDescription
import Foundation

// Absolute path of this package, so the linker can find the prebuilt Mojo library.
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

// xtool builds for a real iPhone. On a Mac with the simulator, switch to "ios-simulator".
let mojoLibDir = "\(packageDir)/Mojo/ios-device"

let package = Package(
    name: "HelloMojo",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "HelloMojo", targets: ["HelloMojo"])
    ],
    targets: [
        // C glue: the bridge Mojo calls into, plus the unofficial Mojo runtime stand-in.
        // Links the prebuilt Mojo static library (libmojoapp.a).
        .target(
            name: "MojoBridge",
            linkerSettings: [
                .unsafeFlags(["-L\(mojoLibDir)"]),
                .linkedLibrary("mojoapp")
            ]
        ),
        // The SwiftUI skin.
        .target(
            name: "HelloMojo",
            dependencies: ["MojoBridge"]
        )
    ]
)

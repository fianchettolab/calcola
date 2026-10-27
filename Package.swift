// swift-tools-version: 6.2

import Foundation
import PackageDescription

// The release whose XCFramework this package downloads; written by release.sh.
let release = (version: "", checksum: "")

// A local build (build-xcframework.sh) wins over the release, so a checkout used as a
// local package override runs what was just built.
let localFramework = "build/SFEngine.xcframework"
let hasLocalBuild = FileManager.default.fileExists(atPath: "\(Context.packageDirectory)/\(localFramework)")

let engine: Target = hasLocalBuild || release.version.isEmpty
    ? .binaryTarget(name: "SFEngine", path: localFramework)
    : .binaryTarget(
        name: "SFEngine",
        url: "https://github.com/fianchettolab/calcola/releases/download/\(release.version)/SFEngine.xcframework.zip",
        checksum: release.checksum
    )

let package = Package(
    name: "Calcola",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SFEngine", targets: ["SFEngine"]),
    ],
    targets: [
        engine,
        .testTarget(name: "CalcolaTests", dependencies: ["SFEngine"]),
    ]
)

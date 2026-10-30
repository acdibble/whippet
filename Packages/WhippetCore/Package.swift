// swift-tools-version: 6.0
import PackageDescription

// What Whippet's apps share: clipboard and calculator history with its database and end-to-end encrypted iCloud
// sync, quicklinks, and the calculator with unit, currency and time conversion. It uses no AppKit or UIKit, so it
// builds for iOS as well as macOS.
let package = Package(
    name: "WhippetCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "WhippetCore", targets: ["WhippetCore"]),
    ],
    dependencies: [
        // Pinned to exact commits, as in project.yml, so a release build can't pick up a new upstream version while
        // the signing keychain is unlocked. Bump these on purpose, in both places.
        .package(url: "https://github.com/groue/GRDB.swift", revision: "b83108d10f42680d78f23fe4d4d80fc88dab3212"), // 7.11.1
        // Its package also lists swift-argument-parser, which only its command-line tool uses.
        .package(url: "https://github.com/NeedleInAJayStack/Units", revision: "28b3150f23ee84763f894c714eff87808e82e94d"), // 1.2.1
    ],
    targets: [
        .target(
            name: "WhippetCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Units", package: "Units"),
            ]
        ),
    ]
)

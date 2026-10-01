// swift-tools-version:5.9
import PackageDescription

// The core of SentinelWallet: crypto, derivation, chain clients, vault.
// Foundation only — no UIKit, no third-party code — so it builds and is tested on
// macOS (Xcode) and Linux (CI) with the same sources the iOS app compiles.
let package = Package(
    name: "SentinelCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "SentinelCore", targets: ["SentinelCore"]),
        // A terminal front end for the same core: useful on its own, and it keeps the live
        // provider path exercised outside the app.
        .executable(name: "sentinel", targets: ["sentinel-cli"]),
    ],
    dependencies: [
        // Only pulled in on Linux, where there is no system CryptoKit. On Apple platforms
        // the app links Apple's own CryptoKit and swift-crypto is never built.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "SentinelCore",
            dependencies: [
                // On Linux the library needs swift-crypto for AES-GCM and Ed25519; on Apple
                // platforms it uses the system CryptoKit and this dependency is not built.
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ],
            path: "Core"
        ),
        .executableTarget(
            name: "sentinel-cli",
            dependencies: ["SentinelCore"],
            path: "Tools/sentinel-cli"
        ),
        .testTarget(
            name: "SentinelWalletCoreTests",
            dependencies: [
                "SentinelCore",
                .product(name: "Crypto", package: "swift-crypto",
                         condition: .when(platforms: [.linux])),
            ],
            path: "Tests/SentinelWalletCoreTests",
            // Real responses captured from the live providers by tools/capture_fixtures.sh,
            // so the decoding tests decode genuine payload shapes.
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)

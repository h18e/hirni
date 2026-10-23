// swift-tools-version: 6.2

// HirniKit enthält die gesamte Logik von hirni, die nichts mit der Oberfläche
// zu tun hat: Dateiformat, Datenbank-Engine, Such-Index, Konflikte.
// Kein SwiftUI hier drin – dadurch lässt sich alles mit `swift test` prüfen.

import PackageDescription

let package = Package(
    name: "HirniKit",
    defaultLocalization: "de",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "HirniKit", targets: ["HirniKit"]),
    ],
    targets: [
        .target(name: "HirniKit"),
        .testTarget(name: "HirniKitTests", dependencies: ["HirniKit"]),
    ]
)

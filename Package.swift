// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NotchFlow",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "NotchFlow",
            targets: ["NotchFlow"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "NotchFlow",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WeatherKit"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .systemLibrary(
            name: "CSMCParamStruct",
            path: "Sources/SMCHelper/include"
        ),
        .executableTarget(
            name: "notchflow-smc-helper",
            dependencies: ["CSMCParamStruct"],
            path: "Sources/SMCHelper",
            exclude: ["include", "SMCParamStruct.h"],
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(
            name: "NotchFlowTests",
            dependencies: ["NotchFlow"]
        ),
    ]
)

// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "IceCream",
    platforms: [
        .macOS(.v10_13), .iOS(.v11), .tvOS(.v11), .watchOS(.v4)
    ],
    products: [
        .library(
            name: "IceCream",
            type: .dynamic,
            targets: ["IceCream"]
        ),
    ],
    dependencies: [
        .package(
            url: "git@github.com:realm/realm-swift.git", 
            from: "10.13.0"
        )
    ],
    targets: [
        .target(
            name: "IceCream",
            dependencies: [
//              "RealmSwift", "Realm"
//              .byName(name: "RealmSwift")
              "RealmSwift"
            ],
            path: "IceCream",
            sources: ["Classes"]
//            linkerSettings: [
//              .linkedLibrary("RealmSwift"),
//              .linkedLibrary("Realm")
//            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)

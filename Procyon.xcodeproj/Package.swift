// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Procyon",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ProcyonCore",
            targets: ["ProcyonCore"]
        ),
        .executable(
            name: "Procyon",
            targets: ["ProcyonAppExec"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.8.0")
    ],
    targets: [
        .target(
            name: "ProcyonCore",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire")
            ]
        ),
        .executableTarget(
            name: "ProcyonAppExec",
            dependencies: ["ProcyonCore"]
        ),
    ]
)

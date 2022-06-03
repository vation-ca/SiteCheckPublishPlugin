// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SiteCheckPublishPlugin",
    platforms: [.macOS(.v12)], // Temporary until Xcode 13.2 has been released

    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "SiteCheckPublishPlugin",
            targets: ["SiteCheckPublishPlugin"]),
    ],
    dependencies: [
.package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.3.8"),
.package(name: "Publish",url:"https://github.com/johnsundell/publish.git",  from: "0.9.0"),
.package(url: "https://github.com/swift-server/async-http-client.git", from: "1.10.0")

    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "SiteCheckPublishPlugin",
            dependencies: ["Publish","SwiftSoup",
            .product(name: "AsyncHTTPClient", package: "async-http-client")

            ]),
        .testTarget(
            name: "SiteCheckPublishPluginTests",
            dependencies: ["SiteCheckPublishPlugin"]),
    ]
)

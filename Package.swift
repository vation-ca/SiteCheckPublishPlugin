// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SiteCheckPublishPlugin",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "SiteCheckPublishPlugin",
            targets: ["SiteCheckPublishPlugin"]),
    ],
    dependencies: [
.package(name: "SwiftSoup",url: "https://github.com/scinfu/SwiftSoup.git", from: "1.7.5"),
.package(name: "Publish",url:"https://github.com/johnsundell/publish.git", from: "0.8.0"),
.package(name: "AsyncHTTPClient", url: "https://github.com/swift-server/async-http-client.git", from: "1.0.0")

    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "SiteCheckPublishPlugin",
            dependencies: ["Publish","SwiftSoup","AsyncHTTPClient"]),
        .testTarget(
            name: "SiteCheckPublishPluginTests",
            dependencies: ["SiteCheckPublishPlugin"]),
    ]
)

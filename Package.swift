// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FeatureBoard",
    platforms: [.iOS(.v16)],
    products: [.library(name: "FeatureBoard", targets: ["FeatureBoard"])],
    targets: [.target(name: "FeatureBoard")]
)

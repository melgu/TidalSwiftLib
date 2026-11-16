// swift-tools-version: 6.2

import PackageDescription

let swiftSettings: [SwiftSetting] = [
	.defaultIsolation(MainActor.self),
	.enableUpcomingFeature("DisableOutwardActorInference"),
	.enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
	.enableUpcomingFeature("InferIsolatedConformances"),
	.enableUpcomingFeature("InferSendableFromCaptures"),
	.enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let package = Package(
	name: "TidalSwiftLib",
	platforms: [
		.macOS(.v14),
		.iOS(.v17)
	],
	products: [
		.library(name: "TidalSwiftLib", targets: ["TidalSwiftLib"])
	],
	targets: [
		.target(
			name: "TidalSwiftLib",
			swiftSettings: swiftSettings
		),
		.testTarget(
			name: "TidalSwiftLibTests",
			dependencies: ["TidalSwiftLib"],
			swiftSettings: swiftSettings
		)
	]
)

// swift-tools-version: 6.2

import PackageDescription

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
			swiftSettings: [
				.defaultIsolation(MainActor.self),
				.enableUpcomingFeature("DisableOutwardActorInference"),
				.enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
				.enableUpcomingFeature("InferIsolatedConformances"),
				.enableUpcomingFeature("InferSendableFromCaptures"),
				.enableUpcomingFeature("NonisolatedNonsendingByDefault")
			]
		)
	]
)

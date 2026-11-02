# TidalSwiftLib

Swift library for the unofficial Tidal API: login, search, playlists, favorites, artists, albums, mixes, lyrics, and downloads with metadata. It's the library behind the [TidalSwift](https://github.com/melgu/TidalSwift) app and the [`tidal` command line tool](https://github.com/melgu/TidalSwiftCLI).

Requires macOS 14 or iOS 17 and Swift 6.2.



## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
	.package(url: "https://github.com/melgu/TidalSwiftLib", from: "1.0.0")
],
targets: [
	.target(name: "MyApp", dependencies: ["TidalSwiftLib"])
]
```

In Xcode, choose File › Add Package Dependencies… and enter the URL.



## Usage

`Session` is the entry point. It stores the login in the login Keychain under the service you pass, so give each app its own.

```swift
import TidalSwiftLib

let session = Session(config: nil, keychainService: "com.example.MyApp")

if !session.loadSession() {
	for await state in session.startAuthorization() {
		switch state {
		case .waiting:
			break
		case .pending(let loginUrl, let expiration):
			print("Open \(loginUrl) before \(expiration) and approve the login")
		case .success:
			session.saveConfig()
		case .failure(let error):
			print("Login failed: \(error)")
		}
	}
}

if let results = await session.search(for: "Jacob Collier") {
	for album in results.albums {
		print(album.title)
	}
}
```

The library logs with OSLog under the subsystem `de.melgu.TidalSwiftLib` and never writes to stdout, so command line tools can use stdout for their output.

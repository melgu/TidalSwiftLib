# TidalSwiftLib

Swift library for the unofficial Tidal API: login, search, playlists, favorites, artists, albums, mixes, lyrics, and downloads with metadata. It's the library behind the [TidalSwift](https://github.com/melgu/TidalSwift) app and the [`tidal` command line tool](https://github.com/melgu/TidalSwiftCLI).

Requires macOS 14 or iOS 17 and Swift 6.2.



## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
	.package(url: "https://github.com/melgu/TidalSwiftLib", .upToNextMinor(from: "0.2.0"))
],
targets: [
	.target(name: "MyApp", dependencies: ["TidalSwiftLib"])
]
```

In Xcode, choose File › Add Package Dependencies… and enter the URL, with the dependency rule "Up to Next Minor Version".

Until 1.0.0, the API is still settling: a new minor version (0.3.0) can contain breaking changes, a new patch version (0.2.1) doesn't.



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

### Logins

There are two ways to log in, which get different streams. A session can hold one of each for the same account, and then picks the right one for every stream.

| | Device login | PKCE login |
|---|---|---|
| Flow | `startAuthorization()`: approve a code in the browser | `startPKCEAuthorization()`: log in in the browser, then pass the address of the error page Tidal shows to `finishPKCEAuthorization(_:redirectUrl:)` |
| Qualities | High (FLAC 16 bit / 44.1 kHz) | Low, High and Max (FLAC up to 24 bit / 192 kHz) |
| Dolby Atmos | Yes | No, tracks play in stereo |

Whichever login comes first is the main one. Logging in with the other kind adds it as the second login, `loginKinds` tells which ones the session holds.

### Playing and Storing Tracks

`Track.audioStream(session:audioQuality:preferDolbyAtmos:)` returns the stream. Some streams are split into segments, so play them through `makeAsset(options:)` and store them with `download(to:)` instead of using their `url` directly.

```swift
if let stream = await track.audioStream(session: session, audioQuality: .max, preferDolbyAtmos: false) {
	let player = AVPlayer(playerItem: AVPlayerItem(asset: stream.makeAsset()))
	player.play()
}
```

### Logging

The library logs with OSLog under the subsystem `de.melgu.TidalSwiftLib` and never writes to stdout, so command line tools can use stdout for their output.



## License

TidalSwiftLib is licensed under the [GNU General Public License v3.0](LICENSE). Apps that use it have to be released under the GPL as well.

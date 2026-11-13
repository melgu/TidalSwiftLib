//
//  ContentUrls.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 01.08.20.
//  Copyright © 2020 Melvin Gundlach. All rights reserved.
//

import Foundation
import OSLog

private let logger = Logger(category: "ContentUrls")

extension Session {
	/// Only the device login gets `streamUrl`
	func audioUrl(trackId: Int, audioQuality: AudioQuality) async -> URL? {
		guard let login = login(.device) else { return nil }
		var parameters = sessionParameters
		parameters["soundQuality"] = "\(audioQuality.rawValue)"
		let url = URL(string: "\(AuthInformation.APILocation)/tracks/\(trackId)/streamUrl")!
		do {
			let response: AudioUrl = try await get(url: url, parameters: parameters, login: login)
			
//			print("""
//			Track ID: \(response.trackId),
//			Quality: \(response.soundQuality.rawValue),
//			Codec: \(response.codec)
//			""")
			
			return response.url.upgradedToHTTPS
		} catch {
			return nil
		}
	}
	
	/// Only unencrypted E-AC-3 streams, which AVFoundation plays directly. Tidal refuses Atmos in offline playback mode.
	/// Only the device login gets them, the PKCE login gets stereo.
	func dolbyAtmosUrl(trackId: Int) async -> URL? {
		guard let login = login(.device) else { return nil }
		let url = URL(string: "\(AuthInformation.APILocation)/tracks/\(trackId)/playbackinfopostpaywall")!
		var parameters = sessionParameters
		parameters["audioquality"] = AudioQuality.high.rawValue
		parameters["playbackmode"] = "STREAM"
		parameters["assetpresentation"] = "FULL"
		parameters["immersiveaudio"] = "true"
		do {
			let response: TrackPlaybackInfo = try await get(url: url, parameters: parameters, login: login)
			guard response.audioMode == .dolbyAtmos,
				  response.manifestMimeType == "application/vnd.tidal.bts",
				  let decodedManifestData = Data(base64Encoded: response.manifest) else { return nil }
			let manifest = try JSONDecoder().decode(TrackManifest.self, from: decodedManifestData)
			guard manifest.codecs == "eac3", manifest.encryptionType == "NONE" else { return nil }
			return manifest.urls.first?.upgradedToHTTPS
		} catch {
			return nil
		}
	}
	
	func videoUrl(videoId: Int) async -> URL? {
		let url = URL(string: "\(AuthInformation.APILocation)/videos/\(videoId)/playbackinfo")!
		var parameters = sessionParameters
		parameters["videoquality"] = "HIGH"
		parameters["playbackmode"] = "STREAM"
		parameters["assetpresentation"] = "FULL"
		do {
			// Videos are only verified with the device login
			let response: VideoPlaybackInfo = try await get(url: url, parameters: parameters, login: login(.device))
			guard let decodedManifestData = Data(base64Encoded: response.manifest) else { return nil }
			let manifest = try JSONDecoder().decode(VideoManifest.self, from: decodedManifestData)
			guard let streamUrlString = manifest.urls.first else { return nil }
			guard let streamUrl = URL(string: streamUrlString) else { return nil }
			return streamUrl
		} catch {
			return nil
		}
	}
	
	/// The PKCE login gets unencrypted DASH streams in every quality, but `streamUrl` refuses it
	func dashStream(trackId: Int, audioQuality: AudioQuality) async -> AudioStream? {
		guard let login = login(.pkce) else { return nil }
		let url = URL(string: "\(AuthInformation.APILocation)/tracks/\(trackId)/playbackinfopostpaywall")!
		var parameters = sessionParameters
		parameters["audioquality"] = audioQuality.rawValue
		parameters["playbackmode"] = "STREAM"
		parameters["assetpresentation"] = "FULL"
		do {
			let response: TrackPlaybackInfo = try await get(url: url, parameters: parameters, login: login)
			guard let manifestData = Data(base64Encoded: response.manifest) else { return nil }
			var stream: AudioStream
			switch response.manifestMimeType {
			case "application/dash+xml":
				let manifest = try DASHManifest(manifestData)
				stream = AudioStream(trackId: trackId, manifest: manifest, isDolbyAtmos: response.audioMode == .dolbyAtmos)
			case "application/vnd.tidal.bts":
				let manifest = try JSONDecoder().decode(TrackManifest.self, from: manifestData)
				guard manifest.encryptionType == "NONE", let url = manifest.urls.first?.upgradedToHTTPS else { return nil }
				let pathExtension = manifest.codecs == "flac" ? "flac" : "m4a"
				stream = AudioStream(url: url, pathExtension: pathExtension, isDolbyAtmos: response.audioMode == .dolbyAtmos)
			default:
				logger.error("Unsupported manifest type \(response.manifestMimeType, privacy: .public)")
				return nil
			}
			stream.audioQuality = response.audioQuality
			return stream
		} catch {
			logger.error("No DASH stream for track \(trackId): \(String(describing: error), privacy: .public)")
			return nil
		}
	}
	
	func pathExtension(for audioQuality: AudioQuality) -> String {
		switch audioQuality {
		case .low, .medium:
			return "m4a"
		case .high, .max:
			return "flac"
		}
	}
}

private extension URL {
	fileprivate var upgradedToHTTPS: URL {
		guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
		guard components.scheme?.lowercased() == "http" else { return self }
		components.scheme = "https"
		return components.url ?? self
	}
}

//
//  StreamTests.swift
//  TidalSwiftLibLiveTests
//

import Foundation
import Testing
@testable import TidalSwiftLib

/// The audio modes a test track has
nonisolated enum TrackAudioModes: CaseIterable, Sendable {
	case stereo
	case stereoAndDolbyAtmos
	case dolbyAtmos
	
	@MainActor var trackId: Int {
		switch self {
		case .stereo: TestItems.trackId
		case .stereoAndDolbyAtmos: TestItems.stereoAndDolbyAtmosTrackId
		case .dolbyAtmos: TestItems.dolbyAtmosTrackId
		}
	}
}

/// Only resolves stream URLs and manifests, nothing is downloaded
extension LiveTests {
	@Suite struct Streams {
		/// The legacy endpoint the library no longer uses, as it has no way to ask for stereo.
		/// If this fails, Tidal changed what it refuses, and `audioUrl` might go back to it.
		@Test(arguments: TrackAudioModes.allCases)
		func streamUrlRefusesDolbyAtmos(_ modes: TrackAudioModes) async throws {
			struct StreamUrl: Decodable {
				let url: URL
			}
			let session = try await LiveSession.session()
			let login = try #require(session.login(.device), "The test login has no device login")
			let url = URL(string: "\(AuthInformation.APILocation)/tracks/\(modes.trackId)/streamUrl")!
			var parameters = session.sessionParameters
			parameters["soundQuality"] = AudioQuality.high.rawValue
			
			if modes == .stereo {
				let response: StreamUrl = try await session.get(url: url, parameters: parameters, login: login)
				#expect(response.url.pathExtension == "flac")
			} else {
				let error = await #expect(throws: RequestError.self) {
					let _: StreamUrl = try await session.get(url: url, parameters: parameters, login: login)
				}
				#expect(error?.statusCode == 401)
				#expect(error?.subStatus == 4005)
			}
		}
		
		/// Stereo FLAC for every track, also with Dolby Atmos, which `streamUrl` refuses
		@Test(arguments: TrackAudioModes.allCases)
		func deviceStreamUrl(_ modes: TrackAudioModes) async throws {
			let session = try await LiveSession.session()
			guard session.login(.device) != nil else {
				try Test.cancel("The test login has no device login")
			}
			let stream = try #require(await session.audioUrl(trackId: modes.trackId, audioQuality: .high))
			
			#expect(stream.url.scheme == "https")
			#expect(stream.url.pathExtension == "flac")
			#expect(stream.quality == .high)
		}
		
		/// Dolby Atmos when preferred or when a track has nothing else, stereo FLAC otherwise
		@Test(arguments: TrackAudioModes.allCases, [false, true])
		func audioStream(_ modes: TrackAudioModes, preferDolbyAtmos: Bool) async throws {
			let session = try await LiveSession.session()
			guard session.login(.device) != nil else {
				try Test.cancel("The test login has no device login")
			}
			let track = try #require(await session.track(trackId: modes.trackId))
			#expect(track.hasDolbyAtmos == (modes != .stereo))
			#expect(track.hasStereo == (modes != .dolbyAtmos))
			
			let stream = try #require(await track.audioStream(session: session, audioQuality: .high, preferDolbyAtmos: preferDolbyAtmos))
			
			let expectsDolbyAtmos = modes == .dolbyAtmos || (modes == .stereoAndDolbyAtmos && preferDolbyAtmos)
			#expect(stream.isDolbyAtmos == expectsDolbyAtmos)
			#expect(stream.pathExtension == (expectsDolbyAtmos ? "m4a" : "flac"))
		}
		
		@Test(arguments: [AudioQuality.max, .high, .medium])
		func dashStream(_ quality: AudioQuality) async throws {
			let session = try await LiveSession.session()
			guard session.login(.pkce) != nil else {
				try Test.cancel("The test login has no PKCE login")
			}
			let stream = try #require(await session.dashStream(trackId: TestItems.trackId, audioQuality: quality))
			
			#expect(!stream.isDolbyAtmos)
			#expect(stream.audioQuality != nil)
		}
		
		@Test func video() async throws {
			let session = try await LiveSession.session()
			let url = try #require(await session.videoUrl(videoId: TestItems.videoId))
			
			let (data, _) = try await URLSession.shared.data(from: url)
			let master = try HLSPlaylist.Master(String(decoding: data, as: UTF8.self), baseURL: url)
			#expect(master.best.height >= 1080)
		}
	}
}

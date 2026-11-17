//
//  StreamTests.swift
//  TidalSwiftLibLiveTests
//

import Foundation
import Testing
@testable import TidalSwiftLib

/// Only resolves stream URLs and manifests, nothing is downloaded
extension LiveTests {
	@Suite struct Streams {
		@Test func deviceStreamUrl() async throws {
			let session = try await LiveSession.session()
			guard session.login(.device) != nil else {
				try Test.cancel("The test login has no device login")
			}
			let stream = try #require(await session.audioUrl(trackId: TestItems.trackId, audioQuality: .high))
			
			#expect(stream.url.scheme == "https")
			#expect(stream.quality == .high)
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

//
//  TidalLinkTests.swift
//  TidalSwiftLibTests
//

import Testing
import TidalSwiftLib

struct TidalLinkTests {
	@Test(arguments: [
		("https://tidal.com/browse/album/123", TidalLink.album(id: 123)),
		("https://listen.tidal.com/track/456/u", .track(id: 456)),
		("http://www.tidal.com/artist/789", .artist(id: 789)),
		("tidal.com/browse/video/42", .video(id: 42)),
		("  https://tidal.com/browse/track/1\n", .track(id: 1)),
		("HTTPS://TIDAL.COM/BROWSE/ALBUM/5", .album(id: 5)),
		("tidal://artist/123", .artist(id: 123)),
		("tidal://track/9", .track(id: 9)),
		("https://tidal.com/browse/album/123/track/456", .track(id: 456)),
		("https://tidal.com/browse/track/456?play=true", .track(id: 456)),
		(
			"https://tidal.com/browse/playlist/0A1B2C3D-4E5F-6789-ABCD-EF0123456789",
			.playlist(uuid: "0a1b2c3d-4e5f-6789-abcd-ef0123456789")
		),
	])
	func parsesLink(_ string: String, expected: TidalLink) {
		#expect(TidalLink(string: string) == expected)
	}
	
	@Test(arguments: [
		"",
		"not a link",
		"https://example.com/album/123",
		"https://nottidal.com/album/123",
		"https://tidal.com.example.com/album/123",
		"ftp://tidal.com/album/123",
		"https://tidal.com/browse",
		"https://tidal.com/browse/album/abc",
		"https://tidal.com/browse/mix/123",
		"https://tidal.com/browse/playlist/123",
	])
	func rejectsLink(_ string: String) {
		#expect(TidalLink(string: string) == nil)
	}
}

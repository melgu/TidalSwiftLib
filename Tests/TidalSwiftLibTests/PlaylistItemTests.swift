//
//  PlaylistItemTests.swift
//  TidalSwiftLibTests
//

import Foundation
import Testing
@testable import TidalSwiftLib

struct PlaylistItemTests {
	/// A page of `/playlists/{uuid}/items`, cut down to the fields the models need
	static let page = """
		{
			"limit": 100,
			"offset": 0,
			"totalNumberOfItems": 3,
			"items": [
				{
					"type": "track",
					"cut": null,
					"item": {
						"id": 1, "title": "First", "duration": 200, "replayGain": -6.5, "allowStreaming": true, "streamReady": true,
						"trackNumber": 1, "volumeNumber": 1, "popularity": 10, "url": "http://www.tidal.com/track/1",
						"editable": false, "explicit": false, "artists": [{ "id": 7, "name": "Artist" }],
						"album": { "id": 3, "title": "Album" },
						"dateAdded": "2026-11-25T08:52:51.814+0000", "index": 100000, "itemUuid": "7beab10c-9a9e-4b21-942e-6ca89d8481d9"
					}
				},
				{
					"type": "video",
					"cut": null,
					"item": {
						"id": 2, "title": "Clip", "volumeNumber": 1, "trackNumber": 1, "duration": 250, "quality": "MP4_1080P",
						"streamReady": true, "allowStreaming": true, "explicit": false, "popularity": 5, "type": "Music Video",
						"adsPrePaywallOnly": true, "artists": [{ "id": 7, "name": "Artist" }],
						"dateAdded": "2026-11-25T08:52:52.087+0000", "index": 200000, "itemUuid": "11de01e0-ee2c-43d2-9e72-ac19ab623fc7"
					}
				},
				{
					"type": "track",
					"cut": null,
					"item": {
						"id": 1, "title": "First", "duration": 200, "replayGain": -6.5, "allowStreaming": true, "streamReady": true,
						"trackNumber": 1, "volumeNumber": 1, "popularity": 10, "url": "http://www.tidal.com/track/1",
						"editable": false, "explicit": false, "artists": [{ "id": 7, "name": "Artist" }],
						"album": { "id": 3, "title": "Album" },
						"dateAdded": "2026-11-25T08:52:52.358+0000", "index": 300000, "itemUuid": "ca424b6f-1528-4179-9124-caa83c92cfa4"
					}
				}
			]
		}
		"""
	
	@Test func decodesTracksAndVideos() throws {
		let page = try JSONDecoder.custom.decode(PlaylistItems.self, from: Data(Self.page.utf8))
		let items = page.items
		
		#expect(items.map(\.track?.id) == [1, nil, 1])
		#expect(items.map(\.video?.id) == [nil, 2, nil])
		#expect(items.map(\.mediaId) == [1, 2, 1])
		#expect(items.map(\.title) == ["First", "Clip", "First"])
		#expect(items.map(\.duration) == [200, 250, 200])
		#expect(items.allSatisfy { $0.artists.map(\.name) == ["Artist"] })
		#expect(items[1].dateAdded == Date(timeIntervalSince1970: 1_795_596_772.087))
	}
	
	@Test func idsAreUniqueForDuplicates() throws {
		let items = try JSONDecoder.custom.decode(PlaylistItems.self, from: Data(Self.page.utf8)).items
		
		#expect(items[0].id == "7BEAB10C-9A9E-4B21-942E-6CA89D8481D9")
		#expect(Set(items.map(\.id)).count == 3)
	}
	
	@Test func roundTrips() throws {
		let items = try JSONDecoder.custom.decode(PlaylistItems.self, from: Data(Self.page.utf8)).items
		let decoded = try JSONDecoder().decode([PlaylistItem].self, from: JSONEncoder().encode(items))
		
		#expect(decoded == items)
		#expect(decoded.map(\.id) == items.map(\.id))
		#expect(decoded.map(\.dateAdded) == items.map(\.dateAdded))
	}
	
	/// Skipping it would shift the positions of the items after it
	@Test func failsForUnknownType() {
		let json = #"{ "type": "episode", "item": {} }"#
		
		#expect(throws: DecodingError.self) {
			try JSONDecoder.custom.decode(PlaylistItem.self, from: Data(json.utf8))
		}
	}
}

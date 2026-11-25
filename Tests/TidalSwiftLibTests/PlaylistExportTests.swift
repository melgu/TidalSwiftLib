//
//  PlaylistExportTests.swift
//  TidalSwiftLibTests
//

import Foundation
import Testing
@testable import TidalSwiftLib

struct PlaylistExportTests {
	static let playlist = """
		{
			"uuid": "0b1f2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d", "title": "Roadtrip", "numberOfTracks": 2, "numberOfVideos": 1,
			"creator": { "id": 42, "name": "Someone" }, "description": "For the car", "duration": 650,
			"lastUpdated": "2026-11-25T08:52:52.358+0000", "created": "2026-11-20T10:00:00.000+0000",
			"type": "USER", "publicPlaylist": true, "url": "http://www.tidal.com/playlist/0b1f2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d",
			"popularity": 0
		}
		"""
	
	static func export() throws -> PlaylistExport {
		let playlist = try JSONDecoder.custom.decode(Playlist.self, from: Data(Self.playlist.utf8))
		let items = try JSONDecoder.custom.decode(PlaylistItems.self, from: Data(PlaylistItemTests.page.utf8)).items
		return PlaylistExport(playlist: playlist, items: items, exportedAt: Date(timeIntervalSince1970: 1_795_600_000))
	}
	
	@Test func keepsPlaylistAndItems() throws {
		let export = try Self.export()
		#expect(export.formatVersion == PlaylistExport.currentFormatVersion)
		#expect(export.title == "Roadtrip")
		#expect(export.description == "For the car")
		#expect(export.isPublic)
		#expect(export.creator == "Someone")
		#expect(export.items.map(\.type) == [.track, .video, .track])
		#expect(export.items.map(\.id) == [1, 2, 1])
		
		let track = export.items[0]
		#expect(track.title == "First")
		#expect(track.artists == ["Artist"])
		#expect(track.album == "Album")
		#expect(track.duration == 200)
		#expect(track.dateAdded == Date(timeIntervalSince1970: 1_795_596_771.814))
		#expect(export.items[1].album == nil)
	}
	
	@Test func roundTrips() throws {
		let data = try Self.export().data()
		let decoded = try PlaylistExport(data: data)
		// The file keeps whole seconds
		#expect(try decoded.data() == data)
		#expect(decoded.items.count == 3)
		
		let json = try #require(String(data: data, encoding: .utf8))
		#expect(json.contains("\"public\" : true"))
		#expect(json.contains("\"type\" : \"video\""))
	}
	
	@Test func rejectsNewerFormat() throws {
		let data = Data(#"{ "formatVersion": 99 }"#.utf8)
		#expect(throws: PlaylistExportError.unsupportedFormatVersion(99)) {
			try PlaylistExport(data: data)
		}
	}
}

struct PlaylistImporterTests {
	static func track(id: Int, title: String = "Song", version: String? = nil, duration: Int = 200, streamReady: Bool = true) throws -> Track {
		let json = """
			{
				"id": \(id), "title": "\(title)", "version": \(version.map { "\"\($0)\"" } ?? "null"), "duration": \(duration),
				"replayGain": -6.5, "allowStreaming": true, "streamReady": \(streamReady), "trackNumber": 1, "volumeNumber": 1,
				"popularity": 10, "url": "http://www.tidal.com/track/\(id)", "editable": false, "explicit": false,
				"artists": [{ "id": 7, "name": "Artist" }], "album": { "id": 3, "title": "Album" }
			}
			"""
		return try JSONDecoder.custom.decode(Track.self, from: Data(json.utf8))
	}
	
	static func item(_ id: Int, isrc: String? = nil, title: String = "Song") -> PlaylistExport.Item {
		PlaylistExport.Item(type: .track, id: id, title: title, artists: ["Artist"], isrc: isrc, duration: 200)
	}
	
	/// Records the IDs Tidal would have added, in order
	final class FakePlaylist {
		let known: Set<Int>
		var added: [Int] = []
		var requests = 0
		
		init(known: Set<Int>) {
			self.known = known
		}
		
		func add(_ ids: [Int]) -> AddOutcome {
			requests += 1
			guard ids.allSatisfy(known.contains) else {
				return .notFound
			}
			added += ids
			return .added
		}
	}
	
	@Test func findsUnknownItemsAndKeepsOrder() async throws {
		let playlist = FakePlaylist(known: [1, 3, 5, 40])
		let alternatives = [try Self.track(id: 40)]
		var importer = PlaylistImporter(
			add: { playlist.add($0) },
			alternatives: { $0 == "ISRC4" ? alternatives : [] }
		)
		try await importer.add([Self.item(1), Self.item(2), Self.item(3), Self.item(4, isrc: "ISRC4"), Self.item(5)])
		
		#expect(playlist.added == [1, 3, 40, 5])
		#expect(importer.added.map(\.id) == [1, 3, 5])
		#expect(importer.replaced.map(\.original.id) == [4])
		#expect(importer.replaced.map(\.track.id) == [40])
		#expect(importer.missing.map(\.id) == [2])
	}
	
	@Test func addsInBatches() async throws {
		let playlist = FakePlaylist(known: Set(0..<250))
		var importer = PlaylistImporter(add: { playlist.add($0) }, alternatives: { _ in nil })
		try await importer.add((0..<250).map { Self.item($0) })
		
		#expect(playlist.requests == 3)
		#expect(playlist.added == Array(0..<250))
	}
	
	@Test func stopsWhenTidalFails() async throws {
		var importer = PlaylistImporter(add: { _ in .failed }, alternatives: { _ in nil })
		await #expect(throws: PlaylistImportError.couldNotAddItems) {
			try await importer.add([Self.item(1)])
		}
	}
	
	@Test func prefersSameTitleThenClosestDuration() throws {
		let item = Self.item(1, title: "Song")
		let candidates = [
			try Self.track(id: 1),
			try Self.track(id: 2, title: "Song (Live)", duration: 200),
			try Self.track(id: 3, duration: 260),
			try Self.track(id: 4, duration: 205),
			try Self.track(id: 5, duration: 200, streamReady: false),
		]
		#expect(PlaylistImporter.bestAlternative(for: item, among: candidates)?.id == 4)
		#expect(PlaylistImporter.bestAlternative(for: item, among: []) == nil)
	}
}

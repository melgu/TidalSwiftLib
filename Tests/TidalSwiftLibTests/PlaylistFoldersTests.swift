//
//  PlaylistFoldersTests.swift
//  TidalSwiftLibTests
//

import Foundation
import Testing
@testable import TidalSwiftLib

/// The folders of the playlists against a fake Tidal
@MainActor
struct PlaylistFoldersTests {
	let fake = FakeTransport()
	let session: Session
	
	init() {
		session = Session(config: Config(accessToken: "token", refreshToken: "", clientID: "client"), keychainService: "de.melgu.TidalSwiftLib.unit-tests")
		session.countryCode = "DE"
		session.userId = 1
		session.transport = fake.transport
	}
	
	/// A folder as `my-collection` lists it
	nonisolated static func folder(_ id: String, in parent: String? = nil) -> String {
		#"""
		{"trn":"trn:folder:\#(id)","itemType":"FOLDER","addedAt":"2026-11-25T21:40:02.315+0000","lastModifiedAt":"2026-11-25T21:40:02.315+0000","name":"Folder \#(id)",
		"parent":\#(parent.map { #"{"id":"\#($0)","name":"Folder \#($0)","atRoot":false}"# } ?? "null"),
		"data":{"trn":"trn:folder:\#(id)","name":"Folder \#(id)","createdAt":"2026-11-25T21:40:02.315+0000","lastModifiedAt":"2026-11-25T21:40:02.315+0000","totalNumberOfItems":2,"id":"\#(id)","itemType":"FOLDER"}}
		"""#
	}
	
	/// A playlist as `my-collection` lists it
	nonisolated static func playlist(_ uuid: String, in parent: String? = nil, sharingLevel: String = "PRIVATE") -> String {
		#"""
		{"trn":"trn:playlist:\#(uuid)","itemType":"PLAYLIST","addedAt":"2026-11-25T21:40:28.410+0000","lastModifiedAt":"2026-11-23T12:15:47.137+0000","name":"Playlist \#(uuid)",
		"parent":\#(parent.map { #"{"id":"\#($0)","name":"Folder \#($0)","atRoot":false}"# } ?? "null"),
		"data":{"uuid":"\#(uuid)","type":"USER","creator":{"id":1,"name":null,"picture":null,"type":"USER"},"curators":[],"contentBehavior":"UNRESTRICTED",
		"sharingLevel":"\#(sharingLevel)","status":"READY","source":"DEFAULT","title":"Playlist \#(uuid)","description":"","image":"img","squareImage":"square","customImageUrl":null,
		"url":"http://www.tidal.com/playlist/\#(uuid)","created":"2026-02-26T18:28:14.163+0000","lastUpdated":"2026-10-09T10:30:01.978+0000","lastItemAddedAt":null,
		"duration":7582,"numberOfTracks":35,"numberOfVideos":0,"promotedArtists":[],"trn":"trn:playlist:\#(uuid)","itemType":"PLAYLIST"}}
		"""#
	}
	
	/// Answers listings with these items, in one page
	func answerListing(_ items: [String]) {
		let page = #"{"items":[\#(items.joined(separator: ","))],"cursor":null}"#
		fake.answer { request in
			if request.httpMethod == "GET" {
				return .init(statusCode: 200, body: page)
			}
			if request.url?.path().hasSuffix("/create-folder") == true {
				return .init(statusCode: 200, body: Self.folder("created"))
			}
			return nil
		}
	}
	
	/// The changes sent, as "endpoint trns → folderId"
	var changes: [String] {
		fake.requests.compactMap { request -> String? in
			guard let url = request.url, request.httpMethod == "PUT" else {
				return nil
			}
			let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
			let what = query["trns"] ?? query["trn"] ?? query["name"] ?? ""
			return "\(url.lastPathComponent) \(what)" + (query["folderId"].map { " → \($0)" } ?? "")
		}
	}
	
	@Test func listsContentsOfAFolder() async throws {
		answerListing([Self.folder("sub", in: "f"), Self.playlist("p", in: "f", sharingLevel: "PUBLIC")])
		let items = try #require(await session.playlistFolders.contents(of: "f"))
		let request = try #require(fake.requests.first?.url)
		#expect(request.path() == "/v2/my-collection/playlists/folders")
		#expect(request.query()?.contains("folderId=f") == true)
		guard case let .folder(folder) = items.first, case let .playlist(playlist, folderId, addedAt) = items.last else {
			Issue.record("Expected a folder and a playlist, got \(items)")
			return
		}
		#expect(folder.id == "sub")
		#expect(folder.parentId == "f")
		#expect(folder.numberOfItems == 2)
		#expect(playlist.uuid == "p")
		#expect(playlist.publicPlaylist)
		#expect(playlist.numberOfTracks == 35)
		#expect(folderId == "f")
		#expect(addedAt != nil)
	}
	
	/// Tidal leaves the contents of deleted folders and cycles behind, which are listed at the root
	@Test func listsLeftoversAtTheRoot() async throws {
		answerListing([Self.folder("orphan", in: "gone"), Self.playlist("p", in: "gone"), Self.folder("x", in: "y"), Self.folder("y", in: "x")])
		let items = try #require(await session.playlistFolders.all())
		let parents = Dictionary(uniqueKeysWithValues: items.map { item -> (String, String?) in
			switch item {
			case let .folder(folder): (folder.id, folder.parentId)
			case let .playlist(playlist, folderId, _): (playlist.uuid, folderId)
			}
		})
		#expect(parents["orphan"] == .some(nil))
		#expect(parents["p"] == .some(nil))
		#expect([parents["x"] ?? nil, parents["y"] ?? nil].filter { $0 == nil }.count == 1)
	}
	
	@Test func createsInAFolder() async throws {
		answerListing([])
		let folder = try #require(await session.playlistFolders.create(name: "New", in: "parent"))
		#expect(folder.id == "created")
		#expect(changes == ["create-folder New → root", "move trn:folder:created → parent"])
	}
	
	@Test func refusesToMoveAFolderIntoItself() async {
		answerListing([Self.folder("a"), Self.folder("b", in: "a")])
		#expect(await session.playlistFolders.move(folderId: "a", to: "b") == false)
		#expect(await session.playlistFolders.move(folderId: "a", to: "a") == false)
		#expect(changes.isEmpty)
		#expect(await session.playlistFolders.move(folderId: "b", to: nil))
		#expect(changes == ["move trn:folder:b → root"])
	}
	
	@Test func deletingMovesTheContentsToTheRoot() async {
		answerListing([Self.folder("f"), Self.folder("sub", in: "f"), Self.playlist("p", in: "f"), Self.playlist("deep", in: "sub")])
		#expect(await session.playlistFolders.delete(folderId: "f"))
		#expect(changes == ["move trn:folder:sub,trn:playlist:p → root", "remove trn:folder:f"])
	}
	
	@Test func failedChangeReturnsFalse() async {
		answerListing([])
		fake.answer("PUT", 500)
		#expect(await session.playlistFolders.move(playlists: ["p"], to: "f") == false)
		#expect(await session.playlistFolders.rename(folderId: "f", to: "Name") == false)
	}
}

/// Moving and removing playlist items by the ID of their entry, against a fake Tidal
@MainActor
struct PlaylistEntryTests {
	let fake = FakeTransport()
	let session: Session
	
	init() {
		session = Session(config: Config(accessToken: "token", refreshToken: "", clientID: "client"), keychainService: "de.melgu.TidalSwiftLib.unit-tests")
		session.countryCode = "DE"
		session.userId = 1
		session.transport = fake.transport
		fake.answer { _ in .init(statusCode: 200, body: #"{"links":{},"meta":{}}"#) }
	}
	
	/// A track of a playlist, with the ID of its entry
	static func item(_ id: Int, entry: Int? = nil) throws -> PlaylistItem {
		let uuid = entry.map { #""00000000-0000-4000-8000-\#(String(format: "%012d", $0))""# } ?? "null"
		let json = """
			{
				"id": \(id), "title": "Song", "duration": 200, "replayGain": -6.5, "allowStreaming": true, "streamReady": true,
				"trackNumber": 1, "volumeNumber": 1, "popularity": 10, "url": "http://www.tidal.com/track/\(id)", "editable": false,
				"explicit": false, "artists": [{ "id": 7, "name": "Artist" }], "album": { "id": 3, "title": "Album" }, "itemUuid": \(uuid)
			}
			"""
		return .track(try JSONDecoder.custom.decode(Track.self, from: Data(json.utf8)))
	}
	
	/// The JSON:API documents sent
	var documents: [[String: Any]] {
		fake.requests.compactMap { $0.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
	}
	
	@Test func movesInFrontOfAnItemInBatches() async throws {
		let items = try (1...25).map { try Self.item($0, entry: $0) }
		let before = try Self.item(99, entry: 99)
		#expect(await session.playlistEditing.move(items, before: before, in: "p"))
		#expect(fake.requests.map(\.httpMethod) == ["PATCH", "PATCH"])
		#expect(fake.requests.first?.url?.path() == "/v2/playlists/p/relationships/items")
		#expect(fake.requests.first?.value(forHTTPHeaderField: "Content-Type") == "application/vnd.api+json")
		let first = try #require(documents.first)
		let data = try #require(first["data"] as? [[String: Any]])
		#expect(data.count == 20)
		#expect(data.first?["type"] as? String == "tracks")
		#expect((data.first?["meta"] as? [String: Any])?["itemId"] as? String == "00000000-0000-4000-8000-000000000001")
		#expect((first["meta"] as? [String: Any])?["positionBefore"] as? String == "00000000-0000-4000-8000-000000000099")
		#expect((documents.last?["data"] as? [[String: Any]])?.count == 5)
	}
	
	@Test func movesToTheEndWithoutPosition() async throws {
		#expect(await session.playlistEditing.move([try Self.item(1, entry: 1)], before: nil, in: "p"))
		#expect(documents.first?["meta"] == nil)
	}
	
	@Test func removesByEntry() async throws {
		#expect(await session.playlistEditing.remove([try Self.item(1, entry: 1), try Self.item(1, entry: 2)], from: "p"))
		#expect(fake.requests.map(\.httpMethod) == ["DELETE"])
		let data = try #require(documents.first?["data"] as? [[String: Any]])
		#expect(data.compactMap { ($0["meta"] as? [String: Any])?["itemId"] as? String }.count == 2)
	}
	
	/// Items only have an entry ID in a playlist
	@Test func refusesItemsWithoutEntry() async throws {
		#expect(await session.playlistEditing.remove([try Self.item(1)], from: "p") == false)
		#expect(fake.requests.isEmpty)
	}
	
	@Test func failedRequestReturnsFalse() async throws {
		fake.answer { _ in .init(statusCode: 500, body: "") }
		#expect(await session.playlistEditing.remove([try Self.item(1, entry: 1)], from: "p") == false)
	}
}

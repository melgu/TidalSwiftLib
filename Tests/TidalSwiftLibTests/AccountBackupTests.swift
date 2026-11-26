//
//  AccountBackupTests.swift
//  TidalSwiftLibTests
//

import Foundation
import Testing
@testable import TidalSwiftLib

struct AccountBackupTests {
	typealias Plan = AccountRestorePlan
	
	static func item(_ id: Int, type: PlaylistExport.Item.Kind = .track, isrc: String? = nil) -> PlaylistExport.Item {
		PlaylistExport.Item(type: type, id: id, title: "Song \(id)", artists: ["Artist"], isrc: isrc, duration: 200)
	}
	
	static func artist(_ id: Int, date: Date? = nil) -> AccountBackup.ArtistEntry {
		AccountBackup.ArtistEntry(id: id, name: "Artist \(id)", dateAdded: date)
	}
	
	static func mix(_ id: String) -> AccountBackup.MixEntry {
		AccountBackup.MixEntry(id: id, title: "Mix \(id)", subTitle: nil, dateAdded: nil)
	}
	
	static func favorite(_ uuid: String) -> AccountBackup.PlaylistEntry {
		AccountBackup.PlaylistEntry(uuid: uuid, title: "Favorite \(uuid)", creator: "Someone", dateAdded: nil)
	}
	
	static func favorites(tracks: [Int] = [], artists: [Int] = [], playlists: [String] = [], mixes: [String]? = []) -> AccountBackup.FavoriteLists {
		AccountBackup.FavoriteLists(tracks: tracks.map { item($0) }, videos: [], albums: [], artists: artists.map { artist($0) }, playlists: playlists.map(favorite), mixes: mixes?.map(mix))
	}
	
	static func export(uuid: String, title: String, description: String? = nil, items: [Int]) throws -> PlaylistExport {
		let items = String(decoding: try ExportCoding.encoder.encode(items.map { item($0) }), as: UTF8.self)
		let json = """
			{
				"formatVersion": 1, "exportedAt": "2026-11-25T10:00:00Z", "uuid": "\(uuid)", "url": "http://www.tidal.com/playlist/\(uuid)",
				"title": "\(title)", "description": \(description.map { "\"\($0)\"" } ?? "null"), "public": false, "creator": "Me",
				"created": "2026-11-20T10:00:00Z", "lastUpdated": "2026-11-25T10:00:00Z", "items": \(items)
			}
			"""
		return try PlaylistExport(data: Data(json.utf8))
	}
	
	static func existing(uuid: String, title: String, description: String? = nil, items: [Int], isPublic: Bool = false) -> Plan.ExistingPlaylist {
		Plan.ExistingPlaylist(uuid: uuid, title: title, description: description, itemIds: items, isPublic: isPublic)
	}
	
	static func backup(favorites: AccountBackup.FavoriteLists = favorites(), playlists: [PlaylistExport] = [], folders: [AccountBackup.FolderEntry]? = []) -> AccountBackup {
		AccountBackup(exportedAt: Date(timeIntervalSince1970: 1_795_600_000), userId: 1, favorites: favorites, playlists: playlists, folders: folders)
	}
	
	static func date(_ day: Int) -> Date {
		Date(timeIntervalSince1970: 1_700_000_000 + Double(day) * 86_400)
	}
	
	static func folder(_ id: String, _ name: String, in parent: String? = nil, day: Int = 0, playlists: [(String, Int)] = []) -> AccountBackup.FolderEntry {
		AccountBackup.FolderEntry(id: id, name: name, parent: parent, dateAdded: date(day), playlists: playlists.map { AccountBackup.FolderPlaylist(uuid: $0.0, dateAdded: date($0.1)) })
	}
	
	static func collectionFolder(_ id: String, _ name: String, in parent: String? = nil) -> CollectionItem {
		CollectionItem(trn: CollectionItem.trn(folder: id), itemType: .folder, addedAt: nil, name: name, parent: parent.map(CollectionItem.Parent.init))
	}
	
	static func collectionPlaylist(_ uuid: String, in parent: String? = nil, day: Int = 0) -> CollectionItem {
		CollectionItem(trn: CollectionItem.trn(playlist: uuid), itemType: .playlist, addedAt: date(day), name: uuid, parent: parent.map(CollectionItem.Parent.init))
	}
	
	// MARK: File
	
	@Test func roundTrips() throws {
		let backup = Self.backup(
			favorites: Self.favorites(tracks: [1, 2], artists: [3], mixes: ["m"]),
			playlists: [try Self.export(uuid: "a", title: "Mine", items: [4, 5])],
			folders: [Self.folder("f", "Folder", playlists: [("a", 1)])]
		)
		let data = try backup.data()
		let decoded = try AccountBackup(data: data)
		#expect(decoded == backup)
		#expect(decoded.playlists.first?.items.map(\.id) == [4, 5])
		#expect(decoded.folders?.first?.playlists.map(\.uuid) == ["a"])
		#expect(try decoded.data() == data)
	}
	
	@Test func rejectsNewerFormat() {
		#expect(throws: AccountBackupError.unsupportedFormatVersion(3)) {
			try AccountBackup(data: Data(#"{ "formatVersion": 3 }"#.utf8))
		}
	}
	
	/// Backups of version 1 have no folders and mixes, so a restore leaves them alone, even with override
	@Test func readsVersion1AndLeavesFoldersAndMixes() throws {
		let data = try Self.backup(favorites: Self.favorites(mixes: [])).data()
		var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
		json["formatVersion"] = 1
		json["folders"] = nil
		var favorites = try #require(json["favorites"] as? [String: Any])
		favorites["mixes"] = nil
		json["favorites"] = favorites
		let backup = try AccountBackup(data: JSONSerialization.data(withJSONObject: json))
		#expect(backup.formatVersion == 1)
		#expect(backup.folders == nil)
		#expect(backup.favorites.mixes == nil)
		
		let plan = Plan(backup: backup, current: Self.favorites(mixes: ["m"]), existing: [], collection: nil, options: .init(override: true, deletePlaylists: true))
		#expect(plan.mixes.isEmpty)
		#expect(plan.folders.isEmpty)
		#expect(plan.isEmpty)
	}
	
	@Test func readsDatesOfV2() throws {
		let expected = Date(timeIntervalSince1970: 1_772_130_494.163)
		for string in ["2026-02-26T18:28:14.163+0000", "2026-02-26T18:28:14.163Z", "2026-02-26T18:28:14.163756Z"] {
			let date = try #require(Date(v2String: string), "\(string)")
			#expect(abs(date.timeIntervalSince(expected)) < 0.001, "\(string)")
		}
		#expect(Date(v2String: "2026-02-26T18:28:14Z") == Date(timeIntervalSince1970: 1_772_130_494))
		#expect(Date(v2String: "yesterday") == nil)
	}
	
	// MARK: Favorites
	
	/// The backup lists the newest first, and they're added oldest first so the newest ends up on top
	@Test func addsMissingFavoritesOldestFirst() {
		let changes = Plan.changes([5, 4, 3, 2, 1, 3], current: [2, 9], key: { $0 }, override: false)
		#expect(changes.add == [3, 1, 4, 5])
		#expect(changes.remove.isEmpty)
	}
	
	@Test func overrideRemovesFavoritesTheBackupDoesNotHave() {
		let changes = Plan.changes([2, 1], current: [3, 2, 9], key: { $0 }, override: true)
		#expect(changes.add == [1])
		#expect(changes.remove == [3, 9])
	}
	
	@Test func restoresMixes() {
		let backup = Self.backup(favorites: Self.favorites(mixes: ["b", "a"]))
		let plan = Plan(backup: backup, current: Self.favorites(mixes: ["a", "x"]), existing: [], collection: nil, options: .init(override: true))
		#expect(plan.mixes.add.map(\.id) == ["b"])
		#expect(plan.mixes.remove.map(\.id) == ["x"])
	}
	
	// MARK: Own playlists
	
	@Test func findsPlaylistsByUUIDThenUniqueTitle() throws {
		let backup = [
			try Self.export(uuid: "kept", title: "Renamed later", items: [1]),
			try Self.export(uuid: "gone", title: "Restored before", items: [2]),
			try Self.export(uuid: "twice-1", title: "Twice", items: [3]),
			try Self.export(uuid: "twice-2", title: "Twice", items: [4]),
			try Self.export(uuid: "new", title: "New", items: [5]),
		]
		let existing = [
			Self.existing(uuid: "kept", title: "Another title", items: [1]),
			Self.existing(uuid: "other-uuid", title: "Restored before", items: [2]),
			Self.existing(uuid: "twice-x", title: "Twice", items: [3]),
			Self.existing(uuid: "extra", title: "Not in backup", items: []),
		]
		let changes = Plan.playlistChanges(backup, existing: existing, options: .init())
		#expect(changes.count == 5)
		guard case let .unchanged(_, kept) = changes[0], case let .unchanged(_, restored) = changes[1] else {
			Issue.record("Expected matches, got \(changes)")
			return
		}
		#expect(kept.uuid == "kept")
		#expect(restored.uuid == "other-uuid")
		// The title is in the backup twice, so it's ambiguous
		for change in changes[2...] {
			guard case .create = change else {
				Issue.record("Expected a new playlist, got \(change)")
				return
			}
		}
	}
	
	@Test func appendsMissingItemsWithoutOverride() throws {
		let backup = [try Self.export(uuid: "a", title: "A", items: [1, 2, 3, 2])]
		let changes = Plan.playlistChanges(backup, existing: [Self.existing(uuid: "a", title: "Other", items: [2, 7])], options: .init())
		guard case let .append(_, playlist, count) = changes.first else {
			Issue.record("Expected an append, got \(changes)")
			return
		}
		#expect(playlist.uuid == "a")
		#expect(count == 2)
	}
	
	@Test func overrideReplacesChangedPlaylists() throws {
		let backup = [
			try Self.export(uuid: "same", title: "Same", description: "Text", items: [1, 2]),
			try Self.export(uuid: "order", title: "Order", items: [1, 2]),
			try Self.export(uuid: "title", title: "Title", items: [1]),
			try Self.export(uuid: "public", title: "Public", items: [1]),
		]
		let existing = [
			Self.existing(uuid: "same", title: "Same", description: "Text", items: [1, 2]),
			Self.existing(uuid: "order", title: "Order", description: "", items: [2, 1]),
			Self.existing(uuid: "title", title: "Changed", items: [1]),
			Self.existing(uuid: "public", title: "Public", items: [1], isPublic: true),
			Self.existing(uuid: "extra", title: "Extra", items: []),
		]
		let changes = Plan.playlistChanges(backup, existing: existing, options: .init(override: true))
		#expect(changes.map(\.isUnchanged) == [true, false, false, false])
		for change in changes[1...] {
			guard case .replace = change else {
				Issue.record("Expected a replacement, got \(change)")
				return
			}
		}
	}
	
	@Test func deletesPlaylistsOnlyWhenAsked() throws {
		let backup = [try Self.export(uuid: "a", title: "A", items: [])]
		let existing = [Self.existing(uuid: "a", title: "A", items: []), Self.existing(uuid: "b", title: "B", items: [])]
		#expect(Plan.playlistChanges(backup, existing: existing, options: .init(override: true)).count == 1)
		let changes = Plan.playlistChanges(backup, existing: existing, options: .init(deletePlaylists: true))
		guard case let .delete(playlist) = changes.last, changes.count == 2 else {
			Issue.record("Expected a deletion, got \(changes)")
			return
		}
		#expect(playlist.uuid == "b")
	}
	
	@Test func emptyPlanForRestoredAccount() throws {
		let favorites = Self.favorites(tracks: [1, 2], artists: [3], playlists: ["p"], mixes: ["m"])
		let backup = Self.backup(
			favorites: favorites,
			playlists: [try Self.export(uuid: "a", title: "A", items: [1])],
			folders: [Self.folder("f", "Folder", playlists: [("a", 1), ("p", 2)]), Self.folder("g", "Sub", in: "f")]
		)
		let collection = [
			Self.collectionFolder("f", "Folder"),
			Self.collectionFolder("g2", "Sub", in: "f"),
			Self.collectionPlaylist("a2", in: "f"),
			Self.collectionPlaylist("p", in: "f"),
		]
		let plan = Plan(backup: backup, current: favorites, existing: [Self.existing(uuid: "a2", title: "A", items: [1])], collection: collection, options: .init(override: true))
		#expect(plan.folders.matches == ["f": "f", "g": "g2"])
		#expect(plan.isEmpty)
	}
	
	// MARK: Folders
	
	/// Tidal allows folders whose parent is gone and cycles, which the backup puts at the root
	@Test func foldersFromListing() {
		let items = [
			Self.collectionPlaylist("old", in: "a", day: 1),
			Self.collectionFolder("b", "B", in: "a"),
			Self.collectionFolder("a", "A"),
			Self.collectionPlaylist("new", in: "a", day: 2),
			Self.collectionFolder("orphan", "Orphan", in: "deleted"),
			Self.collectionFolder("x", "X", in: "y"),
			Self.collectionFolder("y", "Y", in: "x"),
			Self.collectionPlaylist("root"),
		]
		let folders = AccountBackup.folders(from: items)
		let parents = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.parent) })
		#expect(parents["a"] == .some(nil))
		#expect(parents["b"] == "a")
		#expect(parents["orphan"] == .some(nil))
		// Exactly one of the cycle is put at the root
		#expect([parents["x"] ?? nil, parents["y"] ?? nil].filter { $0 == nil }.count == 1)
		#expect(folders.first { $0.id == "a" }?.playlists.map(\.uuid) == ["new", "old"])
		let order = folders.map(\.id)
		#expect(order.firstIndex(of: "a")! < order.firstIndex(of: "b")!)
	}
	
	/// A folder that is in a cycle's folder keeps its parent, the cycle is broken where it closes
	@Test func breaksCycleWhereItCloses() {
		let parents = AccountBackup.soundParents(["d": "a", "a": "c", "c": "b", "b": "a"], order: ["d", "a", "b", "c"])
		#expect(parents["d"] == "a")
		#expect(parents["a"] == "c")
		#expect(parents["c"] == "b")
		#expect(parents["b"] == .some(nil))
	}
	
	static func folderChanges(_ backup: [AccountBackup.FolderEntry], collection: [CollectionItem], titles: [String: String], options: AccountRestoreOptions = .init()) -> FolderChanges {
		var parents: [String: String?] = [:]
		var playlistParents: [String: String] = [:]
		for item in collection {
			parents[item.trn] = item.parent?.id
			if item.itemType == .playlist, let parent = item.parent?.id {
				playlistParents[item.id] = parent
			}
		}
		let existing = collection.filter { $0.itemType == .folder }.map { FolderChanges.ExistingFolder(id: $0.id, name: $0.name, parent: $0.parent?.id) }
		return Plan.folderChanges(AccountBackup.parentsFirst(backup), existing: existing, playlistParents: playlistParents, playlistTitles: titles, currentParents: parents, options: options)
	}
	
	@Test func findsFoldersByIdThenNameWithinParent() {
		let backup = [
			Self.folder("rock", "Rock"),
			Self.folder("live", "Live", in: "rock"),
			Self.folder("jazz", "Jazz"),
			Self.folder("live2", "Live", in: "jazz"),
		]
		let collection = [
			Self.collectionFolder("rock-new", "Rock"),
			Self.collectionFolder("live-new", "Live", in: "rock-new"),
			Self.collectionFolder("jazz", "Renamed"),
			Self.collectionFolder("live-elsewhere", "Live"),
		]
		let changes = Self.folderChanges(backup, collection: collection, titles: [:])
		#expect(changes.matches == ["rock": "rock-new", "live": "live-new", "jazz": "jazz"])
		// Jazz's Live is in another folder in the account, so it's a new one
		#expect(changes.create.map(\.id) == ["live2"])
		#expect(changes.moves.map(\.item) == [.folder("live2")])
		#expect(changes.rename.isEmpty)
	}
	
	/// Without override, only what's at the root is put into folders, in the order the folder got them
	@Test func placesNewAndRootItemsWithoutOverride() {
		let backup = [
			Self.folder("a", "A", playlists: [("newer", 3), ("older", 1), ("elsewhere", 2), ("unknown", 4)]),
			Self.folder("b", "B", in: "a"),
		]
		let collection = [
			Self.collectionFolder("a", "A"),
			Self.collectionFolder("b", "B"),
			Self.collectionFolder("other", "Other"),
			Self.collectionPlaylist("older"),
			Self.collectionPlaylist("elsewhere", in: "other"),
		]
		let titles = ["newer": "Newer", "older": "Older", "elsewhere": "Elsewhere"]
		let changes = Self.folderChanges(backup, collection: collection, titles: titles)
		#expect(changes.create.isEmpty)
		#expect(changes.moves.map(\.item) == [.folder("b"), .playlist("older"), .playlist("newer")])
		#expect(changes.moves.map(\.to) == ["a", "a", "a"])
		#expect(changes.delete.isEmpty)
	}
	
	@Test func overrideMovesRenamesAndDeletes() {
		let backup = [
			Self.folder("a", "A", playlists: [("p", 1)]),
			Self.folder("b", "B"),
		]
		let collection = [
			Self.collectionFolder("a", "Old name", in: "b"),
			Self.collectionFolder("b", "B"),
			Self.collectionFolder("extra", "Extra"),
			Self.collectionPlaylist("p", in: "extra"),
			Self.collectionPlaylist("q", in: "a"),
		]
		let titles = ["p": "P", "q": "Q"]
		let changes = Self.folderChanges(backup, collection: collection, titles: titles, options: .init(override: true))
		#expect(changes.rename.map(\.name) == ["A"])
		// Moves to the root have no date, so they come first
		#expect(changes.moves.map(\.item) == [.folder("a"), .playlist("q"), .playlist("p")])
		#expect(changes.moves.map(\.to) == [nil, nil, "a"])
		#expect(changes.delete.isEmpty)
		
		let deleting = Self.folderChanges(backup, collection: collection, titles: titles, options: .init(override: true, deletePlaylists: true))
		#expect(deleting.delete.map(\.id) == ["extra"])
	}
}

/// Restoring favorites and folders against a fake Tidal
@MainActor
struct FavoritesRestorerTests {
	nonisolated static let notFound = RejectedRequestTests.notFound
	
	let fake = FakeTransport()
	let session: Session
	
	init() {
		session = Session(config: Config(accessToken: "token", refreshToken: "", clientID: "client"), keychainService: "de.melgu.TidalSwiftLib.unit-tests")
		session.countryCode = "DE"
		session.userId = 1
		session.favorites = Favorites(session: session, userId: 1)
		session.transport = fake.transport
	}
	
	func restorer(alternatives: @escaping (String) async -> [Track]? = { _ in nil }) -> FavoritesRestorer {
		FavoritesRestorer(favorites: session.favorites!, alternatives: alternatives, progress: nil)
	}
	
	/// The resources of an `openapi.tidal.com` request, as (id, addedAt)
	nonisolated static func resources(of request: URLRequest) -> [(id: String, addedAt: String?)] {
		guard let body = request.httpBody,
			let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
			let data = json["data"] as? [[String: Any]] else {
			return []
		}
		return data.map { ($0["id"] as? String ?? "", ($0["meta"] as? [String: Any])?["addedAt"] as? String) }
	}
	
	nonisolated static func isOpenAPIAdd(_ request: URLRequest) -> Bool {
		request.httpMethod == "POST" && request.url?.host() == "openapi.tidal.com"
	}
	
	/// Answers adds as Tidal's official API does, skipping the unknown IDs
	func answerAdds(unknown: Set<String> = []) {
		fake.answer { request in
			guard Self.isOpenAPIAdd(request) else {
				return nil
			}
			let skipped = Self.resources(of: request).filter { unknown.contains($0.id) }.map { #"{"id":"\#($0.id)","type":"x","reason":"NOT_FOUND"}"# }
			return .init(statusCode: 200, body: #"{"data":[],"meta":{"skipped":[\#(skipped.joined(separator: ","))]}}"#)
		}
	}
	
	var addRequests: [URLRequest] {
		fake.requests.filter(Self.isOpenAPIAdd)
	}
	
	var addedIds: [String] {
		addRequests.flatMap { Self.resources(of: $0).map(\.id) }
	}
	
	@Test func addsInBatchesWithDatesAndListsMissing() async throws {
		answerAdds(unknown: ["2"])
		let changes = AccountRestorePlan.Changes(add: (1...60).map { AccountBackupTests.artist($0, date: AccountBackupTests.date($0)) }, remove: [])
		let result = try await restorer().restore(changes, kind: .artists, id: { String($0.id) }, date: \.dateAdded)
		#expect(addRequests.count == 2)
		#expect(addRequests.allSatisfy { $0.url?.path() == "/v2/userCollectionArtists/me/relationships/items" })
		#expect(addRequests.first?.value(forHTTPHeaderField: "Content-Type") == "application/vnd.api+json")
		#expect(addedIds == (1...60).map(String.init))
		#expect(Self.resources(of: addRequests[0]).first?.addedAt == "2023-11-15T22:13:20Z")
		#expect(result.added.count == 59)
		#expect(result.missing.map(\.id) == [2])
	}
	
	@Test func stopsWhenTidalFails() async {
		fake.answer("POST", 500)
		let changes = AccountRestorePlan.Changes(add: (1...60).map { AccountBackupTests.artist($0) }, remove: [])
		await #expect(throws: AccountRestoreError.couldNotAddFavorites(.artists)) {
			try await restorer().restore(changes, kind: .artists, id: { String($0.id) }, date: \.dateAdded)
		}
		#expect(addRequests.count == 1)
	}
	
	@Test func removesInBatches() async throws {
		let changes = AccountRestorePlan.Changes(add: [], remove: (1...60).map { AccountBackupTests.artist($0) })
		let result = try await restorer().restore(changes, kind: .artists, id: { String($0.id) }, date: \.dateAdded)
		#expect(result.removed.count == 60)
		let deletes = fake.requests.filter { $0.httpMethod == "DELETE" }.map { $0.url!.lastPathComponent }
		let first: [String] = (1...50).map(String.init)
		let second: [String] = (51...60).map(String.init)
		#expect(deletes == [first.joined(separator: ","), second.joined(separator: ",")])
	}
	
	@Test func failedRemovalThrows() async {
		fake.answer("DELETE", 500)
		let changes = AccountRestorePlan.Changes(add: [], remove: [AccountBackupTests.artist(1)])
		await #expect(throws: AccountRestoreError.couldNotRemoveFavorites(.artists)) {
			try await restorer().restore(changes, kind: .artists, id: { String($0.id) }, date: \.dateAdded)
		}
	}
	
	/// A track Tidal no longer knows is replaced with the date of the original, and the replacement isn't removed as a favorite the backup doesn't have
	@Test func replacesUnknownTracksAndKeepsThem() async throws {
		answerAdds(unknown: ["1"])
		let replacement = try PlaylistImporterTests.track(id: 8, title: "Song 1")
		let changes = AccountRestorePlan.Changes(
			add: [AccountBackupTests.item(1, isrc: "ISRC").dated(AccountBackupTests.date(1)), AccountBackupTests.item(2)],
			remove: [AccountBackupTests.item(8), AccountBackupTests.item(9)]
		)
		let (result, replaced) = try await restorer(alternatives: { $0 == "ISRC" ? [replacement] : nil }).restore(items: changes, kind: .tracks)
		#expect(addedIds == ["1", "2", "8"])
		#expect(Self.resources(of: addRequests[1]).first?.addedAt == "2023-11-15T22:13:20Z")
		#expect(result.added.map(\.id) == [2])
		#expect(replaced.map(\.track.id) == [8])
		#expect(result.removed.map(\.id) == [9])
	}
	
	@Test func videosWithoutIdAreMissing() async throws {
		answerAdds(unknown: ["1"])
		let changes = AccountRestorePlan.Changes(add: [AccountBackupTests.item(1, type: .video)], remove: [])
		let (result, replaced) = try await restorer().restore(items: changes, kind: .videos)
		#expect(result.missing.map(\.id) == [1])
		#expect(replaced.isEmpty)
	}
	
	/// Tidal can't set the date of a mix, so they're added one by one
	@Test func addsMixesOneByOne() async throws {
		fake.answer { request in
			guard request.httpMethod == "PUT" else {
				return nil
			}
			let notAdded = request.url?.query()?.contains("mixIds=b") == true ? #"["b"]"# : "[]"
			return .init(statusCode: 200, body: #"{"addedItems":[],"itemsNotAdded":\#(notAdded)}"#)
		}
		let changes = AccountRestorePlan.Changes(add: ["a", "b", "c"].map(AccountBackupTests.mix), remove: [AccountBackupTests.mix("x")])
		let result = try await restorer().restore(changes, kind: .mixes, id: \.id, date: \.dateAdded)
		let paths = fake.requests.compactMap { $0.url?.path() }
		#expect(paths == Array(repeating: "/v2/favorites/mixes/add", count: 3) + ["/v2/favorites/mixes/remove"])
		#expect(result.added.map(\.id) == ["a", "c"])
		#expect(result.missing.map(\.id) == ["b"])
		#expect(result.removed.map(\.id) == ["x"])
	}
	
	// MARK: Folders
	
	/// Answers creating folders with new IDs, and records every change as (path, trns or name, folderId)
	func answerFolders() {
		fake.answer { request in
			guard request.httpMethod == "PUT", request.url?.path().hasSuffix("/create-folder") == true else {
				return nil
			}
			let name = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "name" }?.value ?? ""
			return .init(statusCode: 200, body: #"{"trn":"trn:folder:new-\#(name)","itemType":"FOLDER","name":"\#(name)","parent":null}"#)
		}
	}
	
	var folderChanges: [String] {
		fake.requests.compactMap { request -> String? in
			guard let url = request.url, request.httpMethod == "PUT" else {
				return nil
			}
			let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
			let what = query["trns"] ?? query["name"] ?? ""
			return "\(url.lastPathComponent) \(what)" + (query["folderId"].map { " → \($0)" } ?? "")
		}
	}
	
	@Test func createsFoldersAndMovesOneByOne() async throws {
		answerFolders()
		let backup = [
			AccountBackupTests.folder("a", "A", playlists: [("p2", 2), ("p1", 1)]),
			AccountBackupTests.folder("b", "B", in: "a"),
		]
		let changes = AccountBackupTests.folderChanges(backup, collection: [AccountBackupTests.collectionPlaylist("p1")], titles: ["p1": "P1", "p2": "P2"])
		let result = try await FolderRestorer(folders: session.playlistFolders, playlistUUIDs: ["p1": "p1", "p2": "p2-new"]).restore(changes)
		#expect(folderChanges == [
			"create-folder A → root",
			"create-folder B → root",
			"move trn:folder:new-B → new-A",
			"move trn:playlist:p1 → new-A",
			"move trn:playlist:p2-new → new-A",
		])
		#expect(result.created == ["A", "B"])
		#expect(result.moved.count == 3)
		#expect(result.skipped.isEmpty)
	}
	
	/// Without override, a folder at the root isn't put into a folder that is inside it
	@Test func skipsMovesThatMakeCycles() async throws {
		let backup = [
			AccountBackupTests.folder("b", "B"),
			AccountBackupTests.folder("a", "A", in: "b"),
		]
		let collection = [AccountBackupTests.collectionFolder("a", "A"), AccountBackupTests.collectionFolder("b", "B", in: "a")]
		let changes = AccountBackupTests.folderChanges(backup, collection: collection, titles: [:])
		#expect(changes.moves.map(\.item) == [.folder("a")])
		let result = try await FolderRestorer(folders: session.playlistFolders, playlistUUIDs: [:]).restore(changes)
		#expect(folderChanges.isEmpty)
		#expect(result.skipped.map(\.item) == [.folder("a")])
	}
	
	/// With override, folders that move go to the root first, so the same swap works
	@Test func overrideSwapsFoldersThroughTheRoot() async throws {
		let backup = [
			AccountBackupTests.folder("b", "B"),
			AccountBackupTests.folder("a", "A", in: "b"),
		]
		let collection = [AccountBackupTests.collectionFolder("a", "A"), AccountBackupTests.collectionFolder("b", "B", in: "a")]
		let changes = AccountBackupTests.folderChanges(backup, collection: collection, titles: [:], options: .init(override: true))
		_ = try await FolderRestorer(folders: session.playlistFolders, playlistUUIDs: [:]).restore(changes)
		#expect(folderChanges == ["move trn:folder:b → root", "move trn:folder:a → b"])
	}
	
	/// Tidal leaves the contents of a deleted folder behind, so they're moved to the root first. Deleted playlists are left out.
	@Test func emptiesFoldersBeforeDeleting() async throws {
		let collection = [
			AccountBackupTests.collectionFolder("x", "X"),
			AccountBackupTests.collectionFolder("y", "Y", in: "x"),
			AccountBackupTests.collectionPlaylist("kept", in: "y"),
			AccountBackupTests.collectionPlaylist("deleted", in: "x"),
		]
		let changes = AccountBackupTests.folderChanges([], collection: collection, titles: [:], options: .init(override: true, deletePlaylists: true))
		#expect(Set(changes.delete.map(\.id)) == ["x", "y"])
		_ = try await FolderRestorer(folders: session.playlistFolders, playlistUUIDs: [:], removedPlaylists: ["deleted"]).restore(changes)
		let deleted = changes.delete.map { "trn:folder:\($0.id)" }.joined(separator: ",")
		#expect(folderChanges == ["move trn:playlist:kept → root", "remove \(deleted)"])
	}
	
	@Test func failedFolderChangeThrows() async {
		fake.answer("PUT", 500)
		let changes = AccountBackupTests.folderChanges([AccountBackupTests.folder("a", "A")], collection: [], titles: [:])
		await #expect(throws: AccountRestoreError.couldNotChangeFolders) {
			try await FolderRestorer(folders: session.playlistFolders, playlistUUIDs: [:]).restore(changes)
		}
	}
}

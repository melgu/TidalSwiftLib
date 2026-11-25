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
	
	static func artist(_ id: Int) -> AccountBackup.ArtistEntry {
		AccountBackup.ArtistEntry(id: id, name: "Artist \(id)", dateAdded: nil)
	}
	
	static func favorites(tracks: [Int] = [], artists: [Int] = []) -> AccountBackup.FavoriteLists {
		AccountBackup.FavoriteLists(tracks: tracks.map { item($0) }, videos: [], albums: [], artists: artists.map(artist), playlists: [])
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
	
	static func existing(uuid: String, title: String, description: String? = nil, items: [Int]) -> Plan.ExistingPlaylist {
		Plan.ExistingPlaylist(uuid: uuid, title: title, description: description, itemIds: items)
	}
	
	static func backup(favorites: AccountBackup.FavoriteLists = favorites(), playlists: [PlaylistExport] = []) -> AccountBackup {
		AccountBackup(exportedAt: Date(timeIntervalSince1970: 1_795_600_000), userId: 1, favorites: favorites, playlists: playlists)
	}
	
	// MARK: File
	
	@Test func roundTrips() throws {
		let backup = Self.backup(favorites: Self.favorites(tracks: [1, 2], artists: [3]), playlists: [try Self.export(uuid: "a", title: "Mine", items: [4, 5])])
		let data = try backup.data()
		let decoded = try AccountBackup(data: data)
		#expect(decoded == backup)
		#expect(decoded.playlists.first?.items.map(\.id) == [4, 5])
		#expect(try decoded.data() == data)
	}
	
	@Test func rejectsNewerFormat() {
		#expect(throws: AccountBackupError.unsupportedFormatVersion(2)) {
			try AccountBackup(data: Data(#"{ "formatVersion": 2 }"#.utf8))
		}
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
		]
		let existing = [
			Self.existing(uuid: "same", title: "Same", description: "Text", items: [1, 2]),
			Self.existing(uuid: "order", title: "Order", description: "", items: [2, 1]),
			Self.existing(uuid: "title", title: "Changed", items: [1]),
			Self.existing(uuid: "extra", title: "Extra", items: []),
		]
		let changes = Plan.playlistChanges(backup, existing: existing, options: .init(override: true))
		#expect(changes.map(\.isUnchanged) == [true, false, false])
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
		let favorites = Self.favorites(tracks: [1, 2], artists: [3])
		let backup = Self.backup(favorites: favorites, playlists: [try Self.export(uuid: "a", title: "A", items: [1])])
		let plan = Plan(backup: backup, current: favorites, existing: [Self.existing(uuid: "a", title: "A", items: [1])], options: .init(override: true))
		#expect(plan.isEmpty)
	}
}

/// Restoring favorites against a fake Tidal
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
	
	/// The value of a POST's form parameter
	nonisolated static func parameter(_ name: String, of request: URLRequest) -> String? {
		let body = request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
		return URLComponents(string: "?" + body)?.queryItems?.first { $0.name == name }?.value
	}
	
	var addedIds: [String] {
		fake.requests.filter { $0.httpMethod == "POST" }.compactMap { Self.parameter("artistIds", of: $0) ?? Self.parameter("trackIds", of: $0) }
	}
	
	@Test func addsOneByOneAndListsMissing() async throws {
		fake.answer { request in
			Self.parameter("artistIds", of: request) == "2" ? .init(statusCode: 404, body: Self.notFound) : nil
		}
		let changes = AccountRestorePlan.Changes(add: [1, 2, 3].map(AccountBackupTests.artist), remove: [])
		let result = try await restorer().restore(changes, kind: .artists) { String($0.id) }
		#expect(addedIds == ["1", "2", "3"])
		#expect(result.added.map(\.id) == [1, 3])
		#expect(result.missing.map(\.id) == [2])
	}
	
	@Test func stopsWhenTidalFails() async {
		fake.answer("POST", 500)
		let changes = AccountRestorePlan.Changes(add: [1, 2].map(AccountBackupTests.artist), remove: [])
		await #expect(throws: AccountRestoreError.couldNotAddFavorites(.artists)) {
			try await restorer().restore(changes, kind: .artists) { String($0.id) }
		}
		#expect(addedIds == ["1"])
	}
	
	@Test func removesInBatches() async throws {
		let changes = AccountRestorePlan.Changes(add: [], remove: (1...60).map(AccountBackupTests.artist))
		let result = try await restorer().restore(changes, kind: .artists) { String($0.id) }
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
			try await restorer().restore(changes, kind: .artists) { String($0.id) }
		}
	}
	
	/// A track Tidal no longer knows is replaced, and the replacement isn't removed as a favorite the backup doesn't have
	@Test func replacesUnknownTracksAndKeepsThem() async throws {
		fake.answer { request in
			Self.parameter("trackIds", of: request) == "1" ? .init(statusCode: 404, body: Self.notFound) : nil
		}
		let replacement = try PlaylistImporterTests.track(id: 8, title: "Song 1")
		let changes = AccountRestorePlan.Changes(
			add: [AccountBackupTests.item(1, isrc: "ISRC"), AccountBackupTests.item(2)],
			remove: [AccountBackupTests.item(8), AccountBackupTests.item(9)]
		)
		let (result, replaced) = try await restorer(alternatives: { $0 == "ISRC" ? [replacement] : nil }).restore(items: changes, kind: .tracks)
		#expect(addedIds == ["1", "8", "2"])
		#expect(result.added.map(\.id) == [2])
		#expect(replaced.map(\.track.id) == [8])
		#expect(result.removed.map(\.id) == [9])
	}
	
	@Test func videosWithoutIdAreMissing() async throws {
		fake.answer("POST", 404, body: Self.notFound)
		let changes = AccountRestorePlan.Changes(add: [AccountBackupTests.item(1, type: .video)], remove: [])
		let (result, replaced) = try await restorer().restore(items: changes, kind: .videos)
		#expect(result.missing.map(\.id) == [1])
		#expect(replaced.isEmpty)
	}
}

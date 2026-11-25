//
//  AccountRestore.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 25.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation

nonisolated public struct AccountRestoreOptions: Equatable, Sendable {
	/// Also removes favorites the backup doesn't have, and replaces the title, description and items of playlists with those of the backup
	public var override: Bool
	/// Deletes own playlists that aren't in the backup
	public var deletePlaylists: Bool
	
	public init(override: Bool = false, deletePlaylists: Bool = false) {
		self.override = override
		self.deletePlaylists = deletePlaylists
	}
}

/// What restoring a backup changes, made with ``Session/restorePlan(for:options:)``, to show it before ``Session/restore(_:progress:)`` does it.
///
/// Own playlists of the backup are found by their UUID, or else by their title if exactly one playlist has it.
/// A playlist the backup created on an earlier restore has a new UUID, so the title finds it.
nonisolated public struct AccountRestorePlan: Sendable {
	public struct Changes<Entry: Sendable>: Sendable {
		/// Oldest first, the order they're added in, so the newest ends up on top
		public let add: [Entry]
		/// Favorites the backup doesn't have, only with ``AccountRestoreOptions/override``
		public let remove: [Entry]
		
		public var isEmpty: Bool {
			add.isEmpty && remove.isEmpty
		}
	}
	
	/// One of the account's own playlists
	public struct ExistingPlaylist: Equatable, Sendable {
		public let uuid: String
		public let title: String
		public let description: String?
		/// Track and video IDs
		public let itemIds: [Int]
	}
	
	public enum PlaylistChange: Sendable {
		case create(PlaylistExport)
		/// Appends the items the playlist doesn't have, as many as `count`
		case append(PlaylistExport, to: ExistingPlaylist, count: Int)
		/// Replaces title, description and items, only with ``AccountRestoreOptions/override``
		case replace(PlaylistExport, ExistingPlaylist)
		case unchanged(PlaylistExport, ExistingPlaylist)
		/// Not in the backup, only with ``AccountRestoreOptions/deletePlaylists``
		case delete(ExistingPlaylist)
		
		public var title: String {
			switch self {
			case let .create(export), let .append(export, _, _), let .replace(export, _), let .unchanged(export, _): export.title
			case let .delete(playlist): playlist.title
			}
		}
		
		public var isUnchanged: Bool {
			if case .unchanged = self {
				return true
			}
			return false
		}
	}
	
	public let backup: AccountBackup
	public let options: AccountRestoreOptions
	public let tracks: Changes<PlaylistExport.Item>
	public let videos: Changes<PlaylistExport.Item>
	public let albums: Changes<AccountBackup.AlbumEntry>
	public let artists: Changes<AccountBackup.ArtistEntry>
	/// Favorite playlists of others
	public let playlists: Changes<AccountBackup.PlaylistEntry>
	/// Every own playlist of the backup, and the ones to delete
	public let ownPlaylists: [PlaylistChange]
	
	public var isEmpty: Bool {
		tracks.isEmpty && videos.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty && ownPlaylists.allSatisfy(\.isUnchanged)
	}
	
	/// - Parameters:
	///   - current: The account's favorites, without its own playlists
	///   - existing: The account's own playlists
	init(backup: AccountBackup, current: AccountBackup.FavoriteLists, existing: [ExistingPlaylist], options: AccountRestoreOptions) {
		self.backup = backup
		self.options = options
		let favorites = backup.favorites
		tracks = Self.changes(favorites.tracks, current: current.tracks, key: \.id, override: options.override)
		videos = Self.changes(favorites.videos, current: current.videos, key: \.id, override: options.override)
		albums = Self.changes(favorites.albums, current: current.albums, key: \.id, override: options.override)
		artists = Self.changes(favorites.artists, current: current.artists, key: \.id, override: options.override)
		playlists = Self.changes(favorites.playlists, current: current.playlists, key: \.uuid, override: options.override)
		ownPlaylists = Self.playlistChanges(backup.playlists, existing: existing, options: options)
	}
	
	/// - Parameter backup: Newest first, as Tidal lists them
	static func changes<Entry, Key: Hashable>(_ backup: [Entry], current: [Entry], key: (Entry) -> Key, override: Bool) -> Changes<Entry> {
		var seen = Set(current.map(key))
		let add = backup.reversed().filter { seen.insert(key($0)).inserted }
		let kept = Set(backup.map(key))
		let remove = override ? current.filter { !kept.contains(key($0)) } : []
		return Changes(add: add, remove: remove)
	}
	
	static func playlistChanges(_ backup: [PlaylistExport], existing: [ExistingPlaylist], options: AccountRestoreOptions) -> [PlaylistChange] {
		var unmatched = existing
		var matches: [Int: ExistingPlaylist] = [:]
		for (index, export) in backup.enumerated() {
			if let match = unmatched.firstIndex(where: { $0.uuid == export.uuid }) {
				matches[index] = unmatched.remove(at: match)
			}
		}
		// A title is only taken as a match if it's unique on both sides
		for (index, export) in backup.enumerated() where matches[index] == nil {
			let sameInBackup = backup.indices.filter { matches[$0] == nil && backup[$0].title == export.title }
			let sameInAccount = unmatched.indices.filter { unmatched[$0].title == export.title }
			if sameInBackup.count == 1, sameInAccount.count == 1 {
				matches[index] = unmatched.remove(at: sameInAccount[0])
			}
		}
		
		var changes: [PlaylistChange] = backup.enumerated().map { index, export in
			guard let playlist = matches[index] else {
				return .create(export)
			}
			let ids = export.items.map(\.id)
			if options.override {
				let same = playlist.title == export.title && (playlist.description ?? "") == (export.description ?? "") && playlist.itemIds == ids
				return same ? .unchanged(export, playlist) : .replace(export, playlist)
			}
			var seen = Set(playlist.itemIds)
			let missing = ids.filter { seen.insert($0).inserted }.count
			return missing == 0 ? .unchanged(export, playlist) : .append(export, to: playlist, count: missing)
		}
		if options.deletePlaylists {
			changes += unmatched.map(PlaylistChange.delete)
		}
		return changes
	}
}

public struct AccountRestoreResult {
	public struct Favorites<Entry> {
		public internal(set) var added: [Entry] = []
		/// Tidal no longer has them
		public internal(set) var missing: [Entry] = []
		public internal(set) var removed: [Entry] = []
	}
	
	public struct PlaylistResult {
		public let change: AccountRestorePlan.PlaylistChange
		/// Nil for unchanged and deleted playlists
		public let imported: PlaylistImportResult?
	}
	
	public internal(set) var tracks = Favorites<PlaylistExport.Item>()
	/// Tidal no longer knows their ID, so another track of the same recording was added in their place
	public internal(set) var replacedTracks: [PlaylistImportResult.Replacement] = []
	public internal(set) var videos = Favorites<PlaylistExport.Item>()
	public internal(set) var albums = Favorites<AccountBackup.AlbumEntry>()
	public internal(set) var artists = Favorites<AccountBackup.ArtistEntry>()
	public internal(set) var playlists = Favorites<AccountBackup.PlaylistEntry>()
	public internal(set) var ownPlaylists: [PlaylistResult] = []
}

nonisolated public enum AccountRestoreError: Error, Equatable, CustomStringConvertible {
	case notLoggedIn
	case couldNotRestorePlaylist(title: String, PlaylistImportError)
	case couldNotDeletePlaylist(title: String)
	case couldNotAddFavorites(FavoriteKind)
	case couldNotRemoveFavorites(FavoriteKind)
	
	public var description: String {
		let message = switch self {
		case .notLoggedIn: "Not logged in"
		case let .couldNotRestorePlaylist(title, error): "Couldn't restore \(title): \(error.description)"
		case let .couldNotDeletePlaylist(title): "Couldn't delete \(title)"
		case let .couldNotAddFavorites(kind): "Couldn't add the favorite \(kind.rawValue)"
		case let .couldNotRemoveFavorites(kind): "Couldn't remove the favorite \(kind.rawValue)"
		}
		return message + ". Restoring again continues with what is still missing."
	}
}

public enum AccountRestoreProgress: Sendable {
	/// - Parameter number: Starts at 1
	case restoringPlaylist(title: String, number: Int, of: Int)
	case addingFavorites(FavoriteKind, count: Int)
	case removingFavorites(FavoriteKind, count: Int)
}

extension Session {
	/// Compares a backup with the account. Changes nothing.
	public func restorePlan(for backup: AccountBackup, options: AccountRestoreOptions = .init()) async throws -> AccountRestorePlan {
		let (current, own) = try await currentFavorites()
		var existing: [AccountRestorePlan.ExistingPlaylist] = []
		for playlist in own {
			guard let items = await playlistItems(playlistId: playlist.uuid) else {
				throw AccountBackupError.couldNotLoadPlaylist(title: playlist.title)
			}
			existing.append(AccountRestorePlan.ExistingPlaylist(uuid: playlist.uuid, title: playlist.title, description: playlist.description, itemIds: items.map(\.mediaId)))
		}
		return AccountRestorePlan(backup: backup, current: current, existing: existing, options: options)
	}
	
	/// Makes the changes of the plan: own playlists first, then the favorites, which are added one by one to keep their order.
	///
	/// Items whose ID Tidal no longer knows are replaced by another track of the same recording or listed as missing, as with ``PlaylistEditing/importPlaylist(_:mode:)``.
	/// - Throws: ``AccountRestoreError`` when Tidal rejects a change. The changes before it are made, so a new plan continues where it stopped.
	public func restore(_ plan: AccountRestorePlan, progress: ((AccountRestoreProgress) -> Void)? = nil) async throws -> AccountRestoreResult {
		guard let favorites else {
			throw AccountRestoreError.notLoggedIn
		}
		var result = AccountRestoreResult()
		
		let changed = plan.ownPlaylists.filter { !$0.isUnchanged }
		for change in plan.ownPlaylists where change.isUnchanged {
			result.ownPlaylists.append(.init(change: change, imported: nil))
		}
		for (index, change) in changed.enumerated() {
			progress?(.restoringPlaylist(title: change.title, number: index + 1, of: changed.count))
			result.ownPlaylists.append(.init(change: change, imported: try await restore(change)))
		}
		
		let restorer = FavoritesRestorer(favorites: favorites, alternatives: { isrc in await self.tracks(isrc: isrc) }, progress: progress)
		result.artists = try await restorer.restore(plan.artists, kind: .artists) { String($0.id) }
		result.albums = try await restorer.restore(plan.albums, kind: .albums) { String($0.id) }
		(result.tracks, result.replacedTracks) = try await restorer.restore(items: plan.tracks, kind: .tracks)
		(result.videos, _) = try await restorer.restore(items: plan.videos, kind: .videos)
		result.playlists = try await restorer.restore(plan.playlists, kind: .playlists, id: \.uuid)
		return result
	}
	
	private func restore(_ change: AccountRestorePlan.PlaylistChange) async throws -> PlaylistImportResult? {
		let mode: PlaylistImportMode
		let export: PlaylistExport
		switch change {
		case .unchanged:
			return nil
		case let .delete(playlist):
			guard await playlistEditing.delete(playlistId: playlist.uuid) else {
				throw AccountRestoreError.couldNotDeletePlaylist(title: playlist.title)
			}
			return nil
		case let .create(created):
			(export, mode) = (created, .new)
		case let .append(appended, playlist, _):
			(export, mode) = (appended, .append(playlistId: playlist.uuid, duplicates: false))
		case let .replace(replacement, playlist):
			(export, mode) = (replacement, .replace(playlistId: playlist.uuid))
		}
		do {
			return try await playlistEditing.importPlaylist(export, mode: mode)
		} catch let error as PlaylistImportError {
			throw AccountRestoreError.couldNotRestorePlaylist(title: export.title, error)
		}
	}
}

/// Adds and removes the favorites of a plan
struct FavoritesRestorer {
	/// Kept short, as the IDs are part of the URL
	static let removeBatchSize = 50
	
	let favorites: Favorites
	let alternatives: (String) async -> [Track]?
	let progress: ((AccountRestoreProgress) -> Void)?
	
	/// Adds one by one, as favorites added together get the same date and lose their order
	func restore<Entry>(_ changes: AccountRestorePlan.Changes<Entry>, kind: FavoriteKind, id: (Entry) -> String) async throws -> AccountRestoreResult.Favorites<Entry> {
		var result = AccountRestoreResult.Favorites<Entry>()
		if !changes.add.isEmpty {
			progress?(.addingFavorites(kind, count: changes.add.count))
		}
		for entry in changes.add {
			switch await favorites.add([id(entry)], kind: kind) {
			case .added: result.added.append(entry)
			case .notFound: result.missing.append(entry)
			case .failed: throw AccountRestoreError.couldNotAddFavorites(kind)
			}
		}
		result.removed = try await remove(changes.remove, kind: kind, id: id)
		if !changes.isEmpty {
			await favorites.refreshCache(of: kind)
		}
		return result
	}
	
	/// Tracks and videos, replacing tracks Tidal no longer knows
	func restore(items changes: AccountRestorePlan.Changes<PlaylistExport.Item>, kind: FavoriteKind) async throws -> (AccountRestoreResult.Favorites<PlaylistExport.Item>, [PlaylistImportResult.Replacement]) {
		var result = AccountRestoreResult.Favorites<PlaylistExport.Item>()
		if !changes.add.isEmpty {
			progress?(.addingFavorites(kind, count: changes.add.count))
		}
		var importer = PlaylistImporter(
			batchSize: 1,
			add: { ids in await favorites.add(ids.map(String.init), kind: kind) },
			alternatives: alternatives
		)
		do {
			try await importer.add(changes.add)
		} catch {
			throw AccountRestoreError.couldNotAddFavorites(kind)
		}
		result.added = importer.added
		result.missing = importer.missing
		// A replacement can be one of the favorites the backup doesn't have, which would otherwise be removed again
		let replacements = Set(importer.replaced.map(\.track.id))
		result.removed = try await remove(changes.remove.filter { !replacements.contains($0.id) }, kind: kind) { String($0.id) }
		if !changes.isEmpty {
			await favorites.refreshCache(of: kind)
		}
		return (result, importer.replaced)
	}
	
	private func remove<Entry>(_ entries: [Entry], kind: FavoriteKind, id: (Entry) -> String) async throws -> [Entry] {
		guard !entries.isEmpty else {
			return []
		}
		progress?(.removingFavorites(kind, count: entries.count))
		for start in stride(from: 0, to: entries.count, by: Self.removeBatchSize) {
			let batch = entries[start..<min(start + Self.removeBatchSize, entries.count)]
			guard await favorites.remove(batch.map(id), kind: kind) else {
				throw AccountRestoreError.couldNotRemoveFavorites(kind)
			}
		}
		return entries
	}
}

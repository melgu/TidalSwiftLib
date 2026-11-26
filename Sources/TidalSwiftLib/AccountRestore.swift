//
//  AccountRestore.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 25.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation

nonisolated public struct AccountRestoreOptions: Equatable, Sendable {
	/// Also removes favorites the backup doesn't have, replaces the title, description and items of playlists with those of the backup,
	/// renames folders and moves folders and playlists to where the backup has them
	public var override: Bool
	/// Deletes own playlists and folders that aren't in the backup. The contents of a deleted folder are moved to the root.
	public var deletePlaylists: Bool
	
	public init(override: Bool = false, deletePlaylists: Bool = false) {
		self.override = override
		self.deletePlaylists = deletePlaylists
	}
}

/// What restoring a backup changes, made with ``Session/restorePlan(for:options:)``, to show it before ``Session/restore(_:progress:)`` does it.
///
/// Own playlists of the backup are found by their UUID, or else by their title if exactly one playlist has it.
/// A playlist the backup created on an earlier restore has a new UUID, so the title finds it. Folders are found the same way, by their ID or their name within their parent.
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
		
		/// The account's playlist it changes, nil for one to create
		var existing: ExistingPlaylist? {
			switch self {
			case .create: nil
			case let .append(_, playlist, _), let .replace(_, playlist), let .unchanged(_, playlist), let .delete(playlist): playlist
			}
		}
		
		var export: PlaylistExport? {
			switch self {
			case let .create(export), let .append(export, _, _), let .replace(export, _), let .unchanged(export, _): export
			case .delete: nil
			}
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
	/// Empty for backups without mixes
	public let mixes: Changes<AccountBackup.MixEntry>
	/// Every own playlist of the backup, and the ones to delete
	public let ownPlaylists: [PlaylistChange]
	/// Empty for backups without folders
	public let folders: FolderChanges
	
	public var isEmpty: Bool {
		tracks.isEmpty && videos.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty && mixes.isEmpty
			&& ownPlaylists.allSatisfy(\.isUnchanged) && folders.isEmpty
	}
	
	/// - Parameters:
	///   - current: The account's favorites, without its own playlists
	///   - existing: The account's own playlists
	///   - collection: The account's folders and where its playlists are, nil if the backup has no folders
	init(backup: AccountBackup, current: AccountBackup.FavoriteLists, existing: [ExistingPlaylist], collection: [CollectionItem]?, options: AccountRestoreOptions) {
		self.backup = backup
		self.options = options
		let favorites = backup.favorites
		tracks = Self.changes(favorites.tracks, current: current.tracks, key: \.id, override: options.override)
		videos = Self.changes(favorites.videos, current: current.videos, key: \.id, override: options.override)
		albums = Self.changes(favorites.albums, current: current.albums, key: \.id, override: options.override)
		artists = Self.changes(favorites.artists, current: current.artists, key: \.id, override: options.override)
		playlists = Self.changes(favorites.playlists, current: current.playlists, key: \.uuid, override: options.override)
		if let backupMixes = favorites.mixes {
			mixes = Self.changes(backupMixes, current: current.mixes ?? [], key: \.id, override: options.override)
		} else {
			mixes = Changes(add: [], remove: [])
		}
		ownPlaylists = Self.playlistChanges(backup.playlists, existing: existing, options: options)
		
		guard let backupFolders = backup.folders, let collection else {
			folders = .empty
			return
		}
		// Where each playlist of the backup is now, by its UUID in the backup
		var parentsByTrn: [String: String?] = [:]
		for item in collection {
			parentsByTrn[item.trn] = item.parent?.id
		}
		var playlistParents: [String: String] = [:]
		var titles: [String: String] = [:]
		for change in ownPlaylists {
			guard let export = change.export else {
				continue
			}
			titles[export.uuid] = export.title
			if let uuid = change.existing?.uuid, let parent = parentsByTrn[CollectionItem.trn(playlist: uuid)] ?? nil {
				playlistParents[export.uuid] = parent
			}
		}
		for favorite in favorites.playlists {
			titles[favorite.uuid] = favorite.title
			if let parent = parentsByTrn[CollectionItem.trn(playlist: favorite.uuid)] ?? nil {
				playlistParents[favorite.uuid] = parent
			}
		}
		let existingFolders = collection.filter { $0.itemType == .folder }
		let soundParents = AccountBackup.soundParents(Dictionary(existingFolders.map { ($0.id, $0.parent?.id) }, uniquingKeysWith: { first, _ in first }), order: existingFolders.map(\.id))
		folders = Self.folderChanges(
			AccountBackup.parentsFirst(backupFolders),
			existing: existingFolders.map { FolderChanges.ExistingFolder(id: $0.id, name: $0.name, parent: soundParents[$0.id] ?? nil) },
			playlistParents: playlistParents,
			playlistTitles: titles,
			currentParents: parentsByTrn,
			options: options
		)
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
	
	/// - Parameters:
	///   - backup: Parents first
	///   - existing: The account's folders, with sound parents
	///   - playlistParents: The folder each playlist of the backup is in now, by its UUID in the backup. Playlists at the root, or still to create or add, aren't in it.
	///   - playlistTitles: The playlists of the backup that will be in the account, by their UUID in the backup
	///   - currentParents: The folder of every folder and playlist in the account, by its TRN
	static func folderChanges(_ backup: [AccountBackup.FolderEntry], existing: [FolderChanges.ExistingFolder], playlistParents: [String: String], playlistTitles: [String: String], currentParents: [String: String?], options: AccountRestoreOptions) -> FolderChanges {
		var matches: [String: String] = [:]
		var unmatched = existing
		for folder in backup {
			if let match = unmatched.firstIndex(where: { $0.id == folder.id }) {
				matches[folder.id] = unmatched.remove(at: match).id
			}
		}
		// By name within the same parent, if it's unique on both sides. Parents come first, so their match is known.
		for folder in backup where matches[folder.id] == nil {
			let parent: String?
			if let backupParent = folder.parent {
				guard let match = matches[backupParent] else {
					// The parent is created, so this one is too
					continue
				}
				parent = match
			} else {
				parent = nil
			}
			let sameInBackup = backup.filter { matches[$0.id] == nil && $0.name == folder.name && $0.parent == folder.parent }
			let sameInAccount = unmatched.indices.filter { unmatched[$0].name == folder.name && unmatched[$0].parent == parent }
			if sameInBackup.count == 1, sameInAccount.count == 1 {
				matches[folder.id] = unmatched.remove(at: sameInAccount[0]).id
			}
		}
		let existingById = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		let names = Dictionary(backup.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
		
		/// Whether an item in `current` is where the backup has it
		func isInPlace(current: String?, target: String?) -> Bool {
			guard let target else {
				return current == nil
			}
			return matches[target] != nil && matches[target] == current
		}
		
		var folderMoves: [FolderChanges.Move] = []
		for folder in backup {
			let current = matches[folder.id].flatMap { existingById[$0]?.parent }
			let needsMove = if matches[folder.id] == nil {
				folder.parent != nil
			} else if options.override {
				!isInPlace(current: current, target: folder.parent)
			} else {
				// Without override, only what's at the root is put into a folder
				current == nil && folder.parent != nil
			}
			if needsMove {
				folderMoves.append(.init(item: .folder(folder.id), title: folder.name, to: folder.parent, folderName: folder.parent.flatMap { names[$0] }, dateAdded: folder.dateAdded))
			}
		}
		
		var playlistMoves: [FolderChanges.Move] = []
		var inBackupFolders: Set<String> = []
		for folder in backup {
			for playlist in folder.playlists {
				inBackupFolders.insert(playlist.uuid)
				guard let title = playlistTitles[playlist.uuid] else {
					continue
				}
				let current = playlistParents[playlist.uuid]
				let needsMove = options.override ? !isInPlace(current: current, target: folder.id) : current == nil
				if needsMove {
					playlistMoves.append(.init(item: .playlist(playlist.uuid), title: title, to: folder.id, folderName: folder.name, dateAdded: playlist.dateAdded))
				}
			}
		}
		if options.override {
			// Playlists the backup has at the root
			for (uuid, title) in playlistTitles.sorted(by: { $0.key < $1.key }) where !inBackupFolders.contains(uuid) && playlistParents[uuid] != nil {
				playlistMoves.append(.init(item: .playlist(uuid), title: title, to: nil, folderName: nil, dateAdded: nil))
			}
		}
		// Oldest first, as a folder lists them by when they were put into it
		playlistMoves = playlistMoves.enumerated()
			.sorted { ($0.element.dateAdded ?? .distantPast, $0.offset) < ($1.element.dateAdded ?? .distantPast, $1.offset) }
			.map(\.element)
		
		let matched = Set(matches.values)
		return FolderChanges(
			create: backup.filter { matches[$0.id] == nil },
			rename: options.override ? backup.compactMap { folder in
				guard let existing = matches[folder.id].flatMap({ existingById[$0] }), existing.name != folder.name else {
					return nil
				}
				return FolderChanges.Rename(folder: existing, name: folder.name)
			} : [],
			moves: folderMoves + playlistMoves,
			delete: options.deletePlaylists ? existing.filter { !matched.contains($0.id) } : [],
			matches: matches,
			currentParents: currentParents
		)
	}
}

/// What a restore changes in the folders of the playlists
nonisolated public struct FolderChanges: Sendable {
	public struct ExistingFolder: Equatable, Sendable {
		public let id: String
		public let name: String
		/// Nil at the root
		public let parent: String?
	}
	
	public struct Rename: Equatable, Sendable {
		public let folder: ExistingFolder
		public let name: String
	}
	
	public enum Item: Equatable, Sendable {
		/// By its ID in the backup
		case folder(String)
		/// By its UUID in the backup
		case playlist(String)
	}
	
	public struct Move: Equatable, Sendable {
		public let item: Item
		/// The name of the folder or the title of the playlist
		public let title: String
		/// The ID of the folder in the backup, nil for the root
		public let to: String?
		public let folderName: String?
		/// When the backup's folder got it
		let dateAdded: Date?
	}
	
	/// Parents first. They're created at the root, and moves put them into their parent.
	public let create: [AccountBackup.FolderEntry]
	/// Only with ``AccountRestoreOptions/override``
	public let rename: [Rename]
	/// Folders parents first, then playlists oldest first
	public let moves: [Move]
	/// Only with ``AccountRestoreOptions/deletePlaylists``
	public let delete: [ExistingFolder]
	/// The account's folder for each folder of the backup that has one
	let matches: [String: String]
	/// The folder of every folder and playlist in the account, by its TRN
	let currentParents: [String: String?]
	
	public var isEmpty: Bool {
		create.isEmpty && rename.isEmpty && moves.isEmpty && delete.isEmpty
	}
	
	static let empty = FolderChanges(create: [], rename: [], moves: [], delete: [], matches: [:], currentParents: [:])
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
	
	public struct FolderResult {
		/// Their names
		public internal(set) var created: [String] = []
		public internal(set) var renamed: [FolderChanges.Rename] = []
		public internal(set) var moved: [FolderChanges.Move] = []
		/// Playlists Tidal no longer has, and moves that would put a folder into itself
		public internal(set) var skipped: [FolderChanges.Move] = []
		public internal(set) var deleted: [FolderChanges.ExistingFolder] = []
	}
	
	public internal(set) var tracks = Favorites<PlaylistExport.Item>()
	/// Tidal no longer knows their ID, so another track of the same recording was added in their place
	public internal(set) var replacedTracks: [PlaylistImportResult.Replacement] = []
	public internal(set) var videos = Favorites<PlaylistExport.Item>()
	public internal(set) var albums = Favorites<AccountBackup.AlbumEntry>()
	public internal(set) var artists = Favorites<AccountBackup.ArtistEntry>()
	public internal(set) var playlists = Favorites<AccountBackup.PlaylistEntry>()
	public internal(set) var mixes = Favorites<AccountBackup.MixEntry>()
	public internal(set) var ownPlaylists: [PlaylistResult] = []
	public internal(set) var folders = FolderResult()
}

nonisolated public enum AccountRestoreError: Error, Equatable, CustomStringConvertible {
	case notLoggedIn
	case couldNotRestorePlaylist(title: String, PlaylistImportError)
	case couldNotDeletePlaylist(title: String)
	case couldNotAddFavorites(FavoriteKind)
	case couldNotRemoveFavorites(FavoriteKind)
	case couldNotChangeFolders
	
	public var description: String {
		let message = switch self {
		case .notLoggedIn: "Not logged in"
		case let .couldNotRestorePlaylist(title, error): "Couldn't restore \(title): \(error.description)"
		case let .couldNotDeletePlaylist(title): "Couldn't delete \(title)"
		case let .couldNotAddFavorites(kind): "Couldn't add the favorite \(kind.rawValue)"
		case let .couldNotRemoveFavorites(kind): "Couldn't remove the favorite \(kind.rawValue)"
		case .couldNotChangeFolders: "Couldn't change the folders"
		}
		return message + ". Restoring again continues with what is still missing."
	}
}

public enum AccountRestoreProgress: Sendable {
	/// - Parameter number: Starts at 1
	case restoringPlaylist(title: String, number: Int, of: Int)
	case addingFavorites(FavoriteKind, count: Int)
	case removingFavorites(FavoriteKind, count: Int)
	case restoringFolders
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
		let collection = backup.folders == nil ? nil : try await currentFolderItems()
		return AccountRestorePlan(backup: backup, current: current, existing: existing, collection: collection, options: options)
	}
	
	/// Makes the changes of the plan: own playlists first, then the favorites with the dates of the backup, then the folders.
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
		result.artists = try await restorer.restore(plan.artists, kind: .artists, id: { String($0.id) }, date: \.dateAdded)
		result.albums = try await restorer.restore(plan.albums, kind: .albums, id: { String($0.id) }, date: \.dateAdded)
		(result.tracks, result.replacedTracks) = try await restorer.restore(items: plan.tracks, kind: .tracks)
		(result.videos, _) = try await restorer.restore(items: plan.videos, kind: .videos)
		result.playlists = try await restorer.restore(plan.playlists, kind: .playlists, id: \.uuid, date: \.dateAdded)
		result.mixes = try await restorer.restore(plan.mixes, kind: .mixes, id: \.id, date: \.dateAdded)
		
		if !plan.folders.isEmpty {
			progress?(.restoringFolders)
			// The playlists' UUIDs in the account, by their UUID in the backup
			var uuids: [String: String] = [:]
			for playlist in result.ownPlaylists {
				guard let export = playlist.change.export else {
					continue
				}
				uuids[export.uuid] = playlist.imported?.playlist.uuid ?? playlist.change.existing?.uuid
			}
			let missingFavorites = Set(result.playlists.missing.map(\.uuid))
			for favorite in plan.backup.favorites.playlists where !missingFavorites.contains(favorite.uuid) {
				uuids[favorite.uuid] = favorite.uuid
			}
			var removed = Set(result.playlists.removed.map(\.uuid))
			for playlist in result.ownPlaylists {
				if case let .delete(deleted) = playlist.change {
					removed.insert(deleted.uuid)
				}
			}
			result.folders = try await FolderRestorer(folders: playlistFolders, playlistUUIDs: uuids, removedPlaylists: removed).restore(plan.folders)
		}
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
	
	/// Adds them with their dates, in batches, apart from mixes: Tidal can't set their date, so they're added one by one, which keeps their order
	func restore<Entry>(_ changes: AccountRestorePlan.Changes<Entry>, kind: FavoriteKind, id: (Entry) -> String, date: (Entry) -> Date?) async throws -> AccountRestoreResult.Favorites<Entry> {
		var result = AccountRestoreResult.Favorites<Entry>()
		if !changes.add.isEmpty {
			progress?(.addingFavorites(kind, count: changes.add.count))
		}
		let batchSize = kind == .mixes ? 1 : Favorites.addBatchSize
		for start in stride(from: 0, to: changes.add.count, by: batchSize) {
			let batch = changes.add[start..<min(start + batchSize, changes.add.count)]
			guard let notFound = await favorites.add(batch.map { DatedFavorite(id: id($0), addedAt: date($0)) }, kind: kind) else {
				throw AccountRestoreError.couldNotAddFavorites(kind)
			}
			for entry in batch {
				if notFound.contains(id(entry)) {
					result.missing.append(entry)
				} else {
					result.added.append(entry)
				}
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
			batchSize: Favorites.addBatchSize,
			add: { items in
				guard let notFound = await favorites.add(items.map { DatedFavorite(id: String($0.id), addedAt: $0.dateAdded) }, kind: kind) else {
					return .failed
				}
				return notFound.isEmpty ? .added : .partlyAdded(notFound: Set(notFound.compactMap(Int.init)))
			},
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

/// Makes the folder changes of a plan, keeping track of the tree, as Tidal accepts moves that make cycles
struct FolderRestorer {
	let folders: PlaylistFolders
	/// The playlists' UUIDs in the account, by their UUID in the backup. Playlists without one are skipped.
	let playlistUUIDs: [String: String]
	/// Playlists the restore deleted or removed from the favorites, which are no longer in the folders
	var removedPlaylists: Set<String> = []
	
	func restore(_ changes: FolderChanges) async throws -> AccountRestoreResult.FolderResult {
		var result = AccountRestoreResult.FolderResult()
		var ids = changes.matches
		var parents = changes.currentParents
		for uuid in removedPlaylists {
			parents[CollectionItem.trn(playlist: uuid)] = nil
		}
		do {
			for folder in changes.create {
				let id = try await folders.createFolder(name: folder.name)
				ids[folder.id] = id
				parents[CollectionItem.trn(folder: id)] = .some(nil)
				result.created.append(folder.name)
			}
			for rename in changes.rename {
				try await folders.rename(folderId: rename.folder.id, to: rename.name)
				result.renamed.append(rename)
			}
			
			// Folders that move go to the root first, so moving one into another can't make a cycle with where they were
			let detached = changes.moves.compactMap { move -> String? in
				guard case let .folder(backupId) = move.item, let id = ids[backupId] else {
					return nil
				}
				let trn = CollectionItem.trn(folder: id)
				return (parents[trn] ?? nil) == nil ? nil : trn
			}
			if !detached.isEmpty {
				try await folders.move(detached, to: nil)
				detached.forEach { parents[$0] = .some(nil) }
			}
			
			for move in changes.moves {
				let trn: String
				var folderId: String?
				switch move.item {
				case let .folder(backupId):
					guard let id = ids[backupId] else {
						result.skipped.append(move)
						continue
					}
					trn = CollectionItem.trn(folder: id)
					folderId = id
				case let .playlist(backupUUID):
					guard let uuid = playlistUUIDs[backupUUID] else {
						result.skipped.append(move)
						continue
					}
					trn = CollectionItem.trn(playlist: uuid)
				}
				let target = move.to.flatMap { ids[$0] }
				if move.to != nil && target == nil {
					result.skipped.append(move)
					continue
				}
				if let folderId, let target, Self.isWithin(target, folder: folderId, parents: parents) {
					result.skipped.append(move)
					continue
				}
				// A folder moved to the root before is there already
				if let parent = parents[trn], parent == target {
					result.moved.append(move)
					continue
				}
				try await folders.move([trn], to: target)
				parents[trn] = .some(target)
				result.moved.append(move)
			}
			
			if !changes.delete.isEmpty {
				let deleted = Set(changes.delete.map(\.id))
				// Tidal leaves the contents of a deleted folder behind, where only the flattened listing finds them
				let deletedTrns = Set(deleted.map(CollectionItem.trn(folder:)))
				let contents = parents.compactMap { trn, parent -> String? in
					guard let parent, deleted.contains(parent), !deletedTrns.contains(trn) else {
						return nil
					}
					return trn
				}.sorted()
				if !contents.isEmpty {
					try await folders.move(contents, to: nil)
				}
				try await folders.deleteFolders(changes.delete.map(\.id))
				result.deleted = changes.delete
			}
		} catch {
			throw AccountRestoreError.couldNotChangeFolders
		}
		return result
	}
	
	/// Whether `target` is `folder` or inside it
	static func isWithin(_ target: String, folder: String, parents: [String: String?]) -> Bool {
		var current: String? = target
		var seen: Set<String> = []
		while let id = current, seen.insert(id).inserted {
			if id == folder {
				return true
			}
			current = parents[CollectionItem.trn(folder: id)] ?? nil
		}
		return false
	}
}

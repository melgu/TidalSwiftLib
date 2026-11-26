//
//  Backup.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 25.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation

public enum AccountBackupProgress: Sendable {
	case loadingFavorites
	case loadingFolders
	/// - Parameter number: Starts at 1
	case loadingPlaylist(title: String, number: Int, of: Int)
}

extension Session {
	/// Loads the favorites and the items of all own playlists.
	/// - Throws: ``AccountBackupError`` if any part can't be loaded, as a backup with gaps would restore an account with gaps
	public func backup(progress: ((AccountBackupProgress) -> Void)? = nil) async throws -> AccountBackup {
		guard let userId else {
			throw AccountBackupError.notLoggedIn
		}
		progress?(.loadingFavorites)
		let (current, own) = try await currentFavorites()
		progress?(.loadingFolders)
		let folders = AccountBackup.folders(from: try await currentFolderItems())
		var playlists: [PlaylistExport] = []
		for (index, playlist) in own.enumerated() {
			progress?(.loadingPlaylist(title: playlist.title, number: index + 1, of: own.count))
			guard let items = await playlistItems(playlistId: playlist.uuid) else {
				throw AccountBackupError.couldNotLoadPlaylist(title: playlist.title)
			}
			playlists.append(PlaylistExport(playlist: playlist, items: items))
		}
		return AccountBackup(userId: userId, favorites: current, playlists: playlists, folders: folders)
	}
	
	func currentFolderItems() async throws -> [CollectionItem] {
		do {
			return try await playlistFolders.items()
		} catch {
			throw AccountBackupError.couldNotLoadFolders
		}
	}
	
	/// The favorites, without the own playlists, and the own playlists
	func currentFavorites() async throws -> (AccountBackup.FavoriteLists, own: [Playlist]) {
		guard let favorites, let userId else {
			throw AccountBackupError.notLoggedIn
		}
		guard let tracks = await favorites.tracks() else {
			throw AccountBackupError.couldNotLoadFavorites(.tracks)
		}
		guard let videos = await favorites.videos() else {
			throw AccountBackupError.couldNotLoadFavorites(.videos)
		}
		guard let albums = await favorites.albums() else {
			throw AccountBackupError.couldNotLoadFavorites(.albums)
		}
		guard let artists = await favorites.artists() else {
			throw AccountBackupError.couldNotLoadFavorites(.artists)
		}
		guard let playlists = await favorites.playlists() else {
			throw AccountBackupError.couldNotLoadFavorites(.playlists)
		}
		guard let mixes = await favorites.mixes() else {
			throw AccountBackupError.couldNotLoadFavorites(.mixes)
		}
		let (own, others) = playlists.reduce(into: ([Playlist](), [FavoritePlaylist]())) { result, favorite in
			if favorite.playlist.creator.id == userId {
				result.0.append(favorite.playlist)
			} else {
				result.1.append(favorite)
			}
		}
		return (AccountBackup.FavoriteLists(tracks: tracks, videos: videos, albums: albums, artists: artists, playlists: others, mixes: mixes), own)
	}
}

nonisolated extension AccountBackup {
	/// The folders of Tidal's listing, parents first. Folders whose parent is gone, or that are in a cycle, Tidal allows both, are put at the root.
	static func folders(from items: [CollectionItem]) -> [FolderEntry] {
		let folderItems = items.filter { $0.itemType == .folder }
		let parents = soundParents(Dictionary(folderItems.map { ($0.id, $0.parent?.id) }, uniquingKeysWith: { first, _ in first }), order: folderItems.map(\.id))
		let entries = folderItems.map { folder in
			let playlists = items
				.filter { $0.itemType == .playlist && $0.parent?.id == folder.id }
				.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
				.map { FolderPlaylist(uuid: $0.id, dateAdded: $0.addedAt) }
			return FolderEntry(id: folder.id, name: folder.name, parent: parents[folder.id] ?? nil, dateAdded: folder.addedAt, playlists: playlists)
		}
		return parentsFirst(entries)
	}
	
	/// The parents with each one that's missing set to nil, for the root, and each cycle broken where it closes
	/// - Parameter order: The IDs in the order to check them, so the result doesn't depend on the dictionary's order
	static func soundParents(_ parents: [String: String?], order: [String]) -> [String: String?] {
		var parents = parents
		for id in order {
			var seen: Set<String> = [id]
			var node = id
			while let parent = parents[node] ?? nil {
				guard parents[parent] != nil, !seen.contains(parent) else {
					parents[node] = .some(nil)
					break
				}
				seen.insert(parent)
				node = parent
			}
		}
		return parents
	}
	
	/// Sorted by depth, so every folder comes after its parent, and by date within a depth
	static func parentsFirst(_ folders: [FolderEntry]) -> [FolderEntry] {
		let parents = soundParents(Dictionary(folders.map { ($0.id, $0.parent) }, uniquingKeysWith: { first, _ in first }), order: folders.map(\.id))
		func depth(_ id: String) -> Int {
			var depth = 0
			var current = parents[id] ?? nil
			while let parent = current {
				depth += 1
				current = parents[parent] ?? nil
			}
			return depth
		}
		return folders
			.map { FolderEntry(id: $0.id, name: $0.name, parent: parents[$0.id] ?? nil, dateAdded: $0.dateAdded, playlists: $0.playlists) }
			.enumerated()
			.sorted { (depth($0.element.id), $0.element.dateAdded ?? .distantPast, $0.offset) < (depth($1.element.id), $1.element.dateAdded ?? .distantPast, $1.offset) }
			.map(\.element)
	}
}

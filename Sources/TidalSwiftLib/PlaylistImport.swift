//
//  PlaylistImport.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 25.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation

public enum PlaylistImportMode: Equatable, Sendable {
	/// Creates a playlist with the title and description of the file
	case new
	/// Adds the items to the end of one of the user's playlists
	/// - Parameter duplicates: Whether to also add the items the playlist already has. Without, an item that is in the file more than once is added once.
	case append(playlistId: String, duplicates: Bool)
	/// Replaces the title, description and items of one of the user's playlists with those of the file
	case replace(playlistId: String)
}

public struct PlaylistImportResult {
	public let playlist: Playlist
	/// Added by their own ID
	public let added: [PlaylistExport.Item]
	/// Tidal no longer knows their ID, so another track of the same recording was added in their place
	public let replaced: [Replacement]
	/// Already in the playlist
	public let skipped: [PlaylistExport.Item]
	/// Tidal no longer has them
	public let missing: [PlaylistExport.Item]
	
	public struct Replacement {
		public let original: PlaylistExport.Item
		public let track: Track
	}
}

public enum PlaylistImportError: Error, Equatable, CustomStringConvertible {
	case couldNotCreatePlaylist
	case couldNotReadPlaylist
	case couldNotRemoveItems
	case couldNotEditPlaylist
	/// The items before were added
	case couldNotAddItems
	
	public var description: String {
		switch self {
		case .couldNotCreatePlaylist: "Couldn't create the playlist"
		case .couldNotReadPlaylist: "Couldn't read the playlist"
		case .couldNotRemoveItems: "Couldn't remove the items of the playlist"
		case .couldNotEditPlaylist: "Couldn't change the title and description of the playlist"
		case .couldNotAddItems: "Couldn't add all items to the playlist. The ones before were added."
		}
	}
}

extension PlaylistEditing {
	/// Adds the items of an export to a playlist, in their order.
	///
	/// Items whose ID Tidal no longer knows are looked up by their ISRC and replaced by another track of the same recording.
	/// The others are skipped and listed in ``PlaylistImportResult/missing``.
	public func importPlaylist(_ export: PlaylistExport, mode: PlaylistImportMode) async throws -> PlaylistImportResult {
		var items = export.items
		var skipped: [PlaylistExport.Item] = []
		let playlistId: String
		switch mode {
		case .new:
			guard let playlist = await create(title: export.title, description: export.description ?? "") else {
				throw PlaylistImportError.couldNotCreatePlaylist
			}
			playlistId = playlist.uuid
		case let .append(id, duplicates):
			guard let existing = await session.playlistItems(playlistId: id) else {
				throw PlaylistImportError.couldNotReadPlaylist
			}
			if !duplicates {
				var seen = Set(existing.map(\.mediaId))
				(items, skipped) = items.reduce(into: ([], [])) { result, item in
					if seen.insert(item.id).inserted {
						result.0.append(item)
					} else {
						result.1.append(item)
					}
				}
			}
			playlistId = id
		case let .replace(id):
			guard let existing = await session.playlistItems(playlistId: id) else {
				throw PlaylistImportError.couldNotReadPlaylist
			}
			guard await removeItems(atIndices: Array(existing.indices), from: id) else {
				throw PlaylistImportError.couldNotRemoveItems
			}
			guard await edit(playlistId: id, title: export.title, description: export.description ?? "") else {
				throw PlaylistImportError.couldNotEditPlaylist
			}
			playlistId = id
		}
		
		// Duplicates are already left out above where they aren't wanted
		var importer = PlaylistImporter(
			add: { ids in await self.add(ids, to: playlistId, duplicate: true) },
			alternatives: { isrc in await self.session.tracks(isrc: isrc) }
		)
		try await importer.add(items)
		
		guard let playlist = await session.playlist(playlistId: playlistId) else {
			throw PlaylistImportError.couldNotReadPlaylist
		}
		return PlaylistImportResult(playlist: playlist, added: importer.added, replaced: importer.replaced, skipped: skipped, missing: importer.missing)
	}
}

/// Adds items in batches and finds the ones Tidal doesn't know, as a single unknown ID fails the whole batch
struct PlaylistImporter {
	/// Tidal takes at least 500 at once, fewer keep the requests small
	static let defaultBatchSize = 100
	
	let batchSize: Int
	let add: ([Int]) async -> AddOutcome
	let alternatives: (String) async -> [Track]?
	
	private(set) var added: [PlaylistExport.Item] = []
	private(set) var replaced: [PlaylistImportResult.Replacement] = []
	private(set) var missing: [PlaylistExport.Item] = []
	
	/// - Parameter batchSize: 1 adds the items one by one, e.g. to favorites, where items added together get the same date and lose their order
	init(batchSize: Int = defaultBatchSize, add: @escaping ([Int]) async -> AddOutcome, alternatives: @escaping (String) async -> [Track]?) {
		self.batchSize = batchSize
		self.add = add
		self.alternatives = alternatives
	}
	
	mutating func add(_ items: [PlaylistExport.Item]) async throws {
		for start in stride(from: 0, to: items.count, by: batchSize) {
			try await addBatch(Array(items[start..<min(start + batchSize, items.count)]))
		}
	}
	
	/// Splits a batch Tidal rejects into halves until the unknown items are found, which keeps the order
	private mutating func addBatch(_ items: [PlaylistExport.Item]) async throws {
		switch await add(items.map(\.id)) {
		case .added:
			added += items
		case .failed:
			throw PlaylistImportError.couldNotAddItems
		case .notFound:
			if items.count == 1 {
				try await replace(items[0])
			} else {
				let middle = items.count / 2
				try await addBatch(Array(items[..<middle]))
				try await addBatch(Array(items[middle...]))
			}
		}
	}
	
	private mutating func replace(_ item: PlaylistExport.Item) async throws {
		// Videos have no ISRC
		guard let isrc = item.isrc, let candidates = await alternatives(isrc) else {
			missing.append(item)
			return
		}
		guard let track = Self.bestAlternative(for: item, among: candidates) else {
			missing.append(item)
			return
		}
		switch await add([track.id]) {
		case .added:
			replaced.append(PlaylistImportResult.Replacement(original: item, track: track))
		case .notFound:
			missing.append(item)
		case .failed:
			throw PlaylistImportError.couldNotAddItems
		}
	}
	
	/// A playable track of the recording, preferring the same title and version and then the closest duration
	static func bestAlternative(for item: PlaylistExport.Item, among tracks: [Track]) -> Track? {
		tracks
			.filter { $0.id != item.id && $0.isPlayable }
			.min { score($0, for: item) < score($1, for: item) }
	}
	
	private static func score(_ track: Track, for item: PlaylistExport.Item) -> (Int, Int, Int) {
		(
			track.title.lowercased() == item.title.lowercased() ? 0 : 1,
			track.version?.lowercased() == item.version?.lowercased() ? 0 : 1,
			abs(track.duration - item.duration)
		)
	}
}

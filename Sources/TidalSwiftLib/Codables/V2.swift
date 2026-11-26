//
//  V2.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 26.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation

// MARK: - Playlist folders (api.tidal.com/v2/my-collection)

/// A folder or playlist in the account's collection of playlists, which holds own playlists and favorite playlists of others
nonisolated struct CollectionItem: Decodable, Equatable, Sendable {
	enum ItemType: String, Decodable, Sendable {
		case folder = "FOLDER"
		case playlist = "PLAYLIST"
	}
	
	struct Parent: Decodable, Equatable, Sendable {
		let id: String
	}
	
	/// `trn:folder:<id>` or `trn:playlist:<uuid>`
	let trn: String
	let itemType: ItemType
	/// When it was put into its folder
	let addedAt: Date?
	let name: String
	/// Nil at the root
	let parent: Parent?
	
	/// The folder's ID or the playlist's UUID
	var id: String {
		String(trn.split(separator: ":", maxSplits: 2).last ?? "")
	}
	
	static func trn(folder id: String) -> String {
		"trn:folder:\(id)"
	}
	
	static func trn(playlist uuid: String) -> String {
		"trn:playlist:\(uuid)"
	}
}

nonisolated struct CollectionPage: Decodable, Sendable {
	let items: [CollectionItem]
	/// Nil on the last page
	let cursor: String?
}

// MARK: - Favorite mixes (api.tidal.com/v2/favorites/mixes)

nonisolated public struct FavoriteMix: Decodable, Equatable, Sendable {
	public let id: String
	public let title: String
	public let subTitle: String?
	public let mixType: String?
	public let dateAdded: Date?
}

nonisolated struct FavoriteMixesPage: Decodable, Sendable {
	let items: [FavoriteMix]
	let cursor: String?
}

nonisolated struct FavoriteMixesChange: Decodable, Sendable {
	let addedItems: [String]?
	/// Mixes Tidal doesn't know
	let itemsNotAdded: [String]?
}

// MARK: - Favorites (openapi.tidal.com/v2/userCollection…)

/// The favorites to add or remove
nonisolated struct CollectionItemsDocument: Encodable, Sendable {
	struct Resource: Encodable, Sendable {
		struct Meta: Encodable, Sendable {
			let addedAt: Date
		}
		
		let id: String
		let type: String
		/// Only for adding. Without, Tidal takes the current date.
		let meta: Meta?
	}
	
	let data: [Resource]
}

nonisolated struct CollectionItemsAnswer: Decodable, Sendable {
	struct Meta: Decodable, Sendable {
		let skipped: [Skipped]?
	}
	
	struct Skipped: Decodable, Sendable {
		let id: String
		/// `NOT_FOUND` for an ID Tidal doesn't know, `ALREADY_PRESENT` for a favorite already
		let reason: String
	}
	
	let meta: Meta?
	
	/// The IDs Tidal doesn't know, which it didn't add
	var notFound: Set<String> {
		Set((meta?.skipped ?? []).filter { $0.reason == "NOT_FOUND" }.map(\.id))
	}
}

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
	
	/// A folder's details
	struct FolderData: Decodable, Equatable, Sendable {
		let createdAt: Date?
		let totalNumberOfItems: Int?
	}
	
	/// `trn:folder:<id>` or `trn:playlist:<uuid>`
	let trn: String
	let itemType: ItemType
	/// When it was put into its folder
	let addedAt: Date?
	let name: String
	/// Nil at the root
	let parent: Parent?
	/// Nil if Tidal's answer didn't have it or it couldn't be read
	var folder: FolderData? = nil
	var playlist: V2Playlist? = nil
	
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

nonisolated extension CollectionItem {
	private enum CodingKeys: String, CodingKey {
		case trn, itemType, addedAt, name, parent, data
	}
	
	/// Reads `data` leniently, as the listing is still usable without it
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		trn = try container.decode(String.self, forKey: .trn)
		itemType = try container.decode(ItemType.self, forKey: .itemType)
		addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt)
		name = try container.decode(String.self, forKey: .name)
		parent = try container.decodeIfPresent(Parent.self, forKey: .parent)
		switch itemType {
		case .folder: folder = try? container.decodeIfPresent(FolderData.self, forKey: .data)
		case .playlist: playlist = try? container.decodeIfPresent(V2Playlist.self, forKey: .data)
		}
	}
}

/// A playlist as the v2 API has it, with its visibility as `sharingLevel` instead of `publicPlaylist`
nonisolated struct V2Playlist: Decodable, Equatable, Sendable {
	struct Creator: Decodable, Equatable, Sendable {
		let id: Int?
		let name: String?
		let picture: String?
	}
	
	let uuid: String
	let type: String
	let creator: Creator
	/// `PUBLIC` or `PRIVATE`
	let sharingLevel: String?
	let title: String
	let description: String?
	let image: String?
	let squareImage: String?
	let url: URL
	let created: Date
	let lastUpdated: Date
	let duration: Int
	let numberOfTracks: Int
	let numberOfVideos: Int
}

extension Playlist {
	/// - Note: v2 has no popularity, so it's 0
	init?(_ playlist: V2Playlist) {
		guard let type = PlaylistType(rawValue: playlist.type) else {
			return nil
		}
		self.init(
			uuid: playlist.uuid,
			title: playlist.title,
			numberOfTracks: playlist.numberOfTracks,
			numberOfVideos: playlist.numberOfVideos,
			creator: PlaylistCreator(id: playlist.creator.id, name: playlist.creator.name, url: nil, picture: playlist.creator.picture, popularity: nil),
			description: playlist.description,
			duration: playlist.duration,
			lastUpdated: playlist.lastUpdated,
			created: playlist.created,
			type: type,
			publicPlaylist: playlist.sharingLevel == "PUBLIC",
			url: playlist.url,
			image: playlist.image,
			popularity: 0,
			squareImage: playlist.squareImage
		)
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

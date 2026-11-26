//
//  PlaylistFolders.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 26.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation

/// The folders of the account's playlists, through the v2 API.
///
/// Tidal doesn't keep the tree sound: it accepts a move that makes a cycle, and deleting a folder that isn't empty leaves its contents
/// pointing to a folder that no longer exists, where only ``items()`` still lists them. So callers check for cycles and empty a folder first.
/// See `docs/v2-api.md`.
struct PlaylistFolders {
	/// Tidal's maximum
	static let pageSize = 50
	
	unowned let session: Session
	
	private var baseUrl: String {
		"\(AuthInformation.APIv2Location)/my-collection/playlists/folders"
	}
	
	private var parameters: [String: String] {
		session.countryCode.map { ["countryCode": $0] } ?? [:]
	}
	
	/// All folders and playlists, own ones and favorites of others, each with its parent
	func items() async throws -> [CollectionItem] {
		var items: [CollectionItem] = []
		var cursor: String?
		repeat {
			var parameters = parameters
			parameters["limit"] = "\(Self.pageSize)"
			parameters["order"] = "DATE"
			parameters["orderDirection"] = "ASC"
			parameters["cursor"] = cursor
			let response = try await session.get(url: URL(string: "\(baseUrl)/flattened")!, parameters: parameters)
			let page = try JSONDecoder.v2.decode(CollectionPage.self, from: response.data)
			items += page.items
			cursor = page.cursor
		} while cursor != nil
		return items
	}
	
	/// Creates a folder at the root, as Tidal ignores another parent here
	/// - Returns: Its ID
	func createFolder(name: String) async throws -> String {
		var parameters = parameters
		parameters["name"] = name
		parameters["folderId"] = "root"
		let item: CollectionItem = try await session.put(url: URL(string: "\(baseUrl)/create-folder")!, parameters: parameters)
		return item.id
	}
	
	/// Moves folders and playlists, given by their TRN, into a folder, or to the root for nil
	func move(_ trns: [String], to folderId: String?) async throws {
		var parameters = parameters
		parameters["trns"] = trns.joined(separator: ",")
		parameters["folderId"] = folderId ?? "root"
		try await session.put(url: URL(string: "\(baseUrl)/move")!, parameters: parameters)
	}
	
	func rename(folderId: String, to name: String) async throws {
		var parameters = parameters
		parameters["trn"] = CollectionItem.trn(folder: folderId)
		parameters["name"] = name
		try await session.put(url: URL(string: "\(baseUrl)/rename")!, parameters: parameters)
	}
	
	/// Deletes folders, which should be empty. Never pass playlists here: Tidal deletes own playlists that are removed this way.
	func deleteFolders(_ ids: [String]) async throws {
		var parameters = parameters
		parameters["trns"] = ids.map(CollectionItem.trn(folder:)).joined(separator: ",")
		try await session.put(url: URL(string: "\(baseUrl)/remove")!, parameters: parameters)
	}
}

extension Session {
	var playlistFolders: PlaylistFolders {
		PlaylistFolders(session: self)
	}
}

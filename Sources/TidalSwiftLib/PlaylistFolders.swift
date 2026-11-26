//
//  PlaylistFolders.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 26.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation

/// A folder of the account's playlists
public struct PlaylistFolder: Equatable, Hashable, Identifiable, Sendable {
	public let id: String
	public let name: String
	/// The ID of the folder it is in, nil at the root
	public let parentId: String?
	/// When it was put into its parent
	public let addedAt: Date?
	public let createdAt: Date?
	/// Folders and playlists directly in it
	public let numberOfItems: Int?
}

/// A folder or a playlist in the account's collection of playlists
public enum PlaylistFolderItem: Equatable {
	case folder(PlaylistFolder)
	/// An own playlist or a favorite playlist of others
	/// - Parameters:
	///   - folderId: The folder it is in, nil at the root
	///   - addedAt: When it was put into its folder
	case playlist(Playlist, folderId: String?, addedAt: Date?)
	
	public var folderId: String? {
		switch self {
		case let .folder(folder): folder.parentId
		case let .playlist(_, folderId, _): folderId
		}
	}
}

/// The folders of the account's playlists, through the v2 API. Get it from ``Session/playlistFolders``.
///
/// Tidal doesn't keep the tree sound itself: it accepts a move that makes a cycle, and deleting a folder that isn't empty leaves its contents
/// pointing to a folder that no longer exists. The public methods guard against both. See `docs/v2-api.md`.
public struct PlaylistFolders {
	/// Tidal's maximum
	static let pageSize = 50
	
	unowned let session: Session
	
	private var baseUrl: String {
		"\(AuthInformation.APIv2Location)/my-collection/playlists/folders"
	}
	
	private var parameters: [String: String] {
		session.countryCode.map { ["countryCode": $0] } ?? [:]
	}
	
	// MARK: - Reading
	
	/// The folders and playlists directly in a folder, newest first
	/// - Parameter folderId: Nil for the root
	public func contents(of folderId: String? = nil) async -> [PlaylistFolderItem]? {
		guard let items = try? await pages(url: URL(string: baseUrl)!, extra: ["folderId": folderId ?? "root"]) else {
			return nil
		}
		return items.compactMap { Self.item($0, parent: $0.parent?.id) }
	}
	
	/// Every folder and playlist, each with its folder, newest first.
	/// Folders whose parent Tidal deleted, or that are in a cycle, are listed at the root.
	public func all() async -> [PlaylistFolderItem]? {
		guard let items = try? await items() else {
			return nil
		}
		let folders = items.filter { $0.itemType == .folder }
		let known = Set(folders.map(\.id))
		let parents = AccountBackup.soundParents(Dictionary(folders.map { ($0.id, $0.parent?.id) }, uniquingKeysWith: { first, _ in first }), order: folders.map(\.id))
		return items.reversed().compactMap { item in
			let parent: String?
			if item.itemType == .folder {
				parent = parents[item.id] ?? nil
			} else if let id = item.parent?.id, known.contains(id) {
				parent = id
			} else {
				parent = nil
			}
			return Self.item(item, parent: parent)
		}
	}
	
	private static func item(_ item: CollectionItem, parent: String?) -> PlaylistFolderItem? {
		switch item.itemType {
		case .folder:
			return .folder(PlaylistFolder(id: item.id, name: item.name, parentId: parent, addedAt: item.addedAt, createdAt: item.folder?.createdAt, numberOfItems: item.folder?.totalNumberOfItems))
		case .playlist:
			guard let playlist = item.playlist.flatMap(Playlist.init) else {
				return nil
			}
			return .playlist(playlist, folderId: parent, addedAt: item.addedAt)
		}
	}
	
	// MARK: - Changing
	
	/// Creates a folder
	/// - Parameter parentId: The folder to create it in, nil for the root
	public func create(name: String, in parentId: String? = nil) async -> PlaylistFolder? {
		guard let id = try? await createFolder(name: name) else {
			return nil
		}
		if let parentId {
			// Tidal creates folders at the root only
			guard (try? await move([CollectionItem.trn(folder: id)], to: parentId)) != nil else {
				try? await deleteFolders([id])
				return nil
			}
		}
		return PlaylistFolder(id: id, name: name, parentId: parentId, addedAt: .now, createdAt: .now, numberOfItems: 0)
	}
	
	public func rename(folderId: String, to name: String) async -> Bool {
		(try? await renameFolder(folderId, to: name)) != nil
	}
	
	/// Moves playlists into a folder. Each playlist is only in one folder, so this takes them out of their current one.
	/// - Parameter folderId: Nil for the root
	public func move(playlists uuids: [String], to folderId: String?) async -> Bool {
		guard !uuids.isEmpty else {
			return true
		}
		return (try? await move(uuids.map(CollectionItem.trn(playlist:)), to: folderId)) != nil
	}
	
	/// Moves a folder with its contents into another folder
	/// - Parameter parentId: Nil for the root
	/// - Returns: False also if `parentId` is the folder itself or inside it, which Tidal would accept and then lose the folder in a cycle
	public func move(folderId: String, to parentId: String?) async -> Bool {
		if let parentId {
			guard let items = try? await items() else {
				return false
			}
			var parents: [String: String?] = [:]
			for item in items where item.itemType == .folder {
				parents[item.trn] = item.parent?.id
			}
			guard !FolderRestorer.isWithin(parentId, folder: folderId, parents: parents) else {
				return false
			}
		}
		return (try? await move([CollectionItem.trn(folder: folderId)], to: parentId)) != nil
	}
	
	/// Deletes a folder, moving its folders and playlists to the root first, as Tidal leaves them behind otherwise
	public func delete(folderId: String) async -> Bool {
		guard let items = try? await items() else {
			return false
		}
		let contents = items.filter { $0.parent?.id == folderId }.map(\.trn)
		do {
			if !contents.isEmpty {
				try await move(contents, to: nil)
			}
			try await deleteFolders([folderId])
			return true
		} catch {
			return false
		}
	}
	
	// MARK: - Tidal's endpoints
	
	/// All folders and playlists, own ones and favorites of others, each with its parent as Tidal has it, oldest first
	func items() async throws -> [CollectionItem] {
		try await pages(url: URL(string: "\(baseUrl)/flattened")!, extra: [:])
	}
	
	private func pages(url: URL, extra: [String: String]) async throws -> [CollectionItem] {
		var items: [CollectionItem] = []
		var cursor: String?
		repeat {
			var parameters = parameters.merging(extra) { _, new in new }
			parameters["limit"] = "\(Self.pageSize)"
			parameters["order"] = "DATE"
			parameters["orderDirection"] = "ASC"
			parameters["cursor"] = cursor
			let response = try await session.get(url: url, parameters: parameters)
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
	
	/// Moves folders and playlists, given by their TRN, into a folder, or to the root for nil. Doesn't check for cycles.
	func move(_ trns: [String], to folderId: String?) async throws {
		var parameters = parameters
		parameters["trns"] = trns.joined(separator: ",")
		parameters["folderId"] = folderId ?? "root"
		try await session.put(url: URL(string: "\(baseUrl)/move")!, parameters: parameters)
	}
	
	func renameFolder(_ folderId: String, to name: String) async throws {
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
	/// The folders of the account's playlists
	public var playlistFolders: PlaylistFolders {
		PlaylistFolders(session: self)
	}
}

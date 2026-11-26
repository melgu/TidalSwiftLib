//
//  PlaylistEditing.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 01.08.20.
//  Copyright © 2020 Melvin Gundlach. All rights reserved.
//

import Foundation

/// What adding IDs to a playlist or the favorites came to
enum AddOutcome: Equatable {
	case added
	/// Tidal doesn't know one of the IDs, and added none of them
	case notFound
	/// Tidal added all but these, which it doesn't know
	case partlyAdded(notFound: Set<Int>)
	case failed
}

public class PlaylistEditing {
	unowned let session: Session
	private let baseUrl: String
	
	init(session: Session) {
		self.session = session
		self.baseUrl = "\(AuthInformation.APILocation)/playlists"
	}
	
	private func etag(for playlistId: String) async -> Int {
		let url = URL(string: "\(baseUrl)/\(playlistId)")!
		do {
			let response = try await session.get(url: url, parameters: session.sessionParameters)
			return response.etag ?? -1
		} catch {
			return -1
		}
	}
	
	/// - Parameter trackIds: Track or video IDs, as Tidal takes both
	/// - Returns: False also if Tidal doesn't know one of the IDs, which fails the whole request
	public func addTracks(_ trackIds: [Int], to playlistId: String, duplicate: Bool) async -> Bool {
		if case .added = await add(trackIds, to: playlistId, duplicate: duplicate) {
			return true
		}
		return false
	}
	
	func add(_ ids: [Int], to playlistId: String, duplicate: Bool) async -> AddOutcome {
		let url = URL(string: "\(baseUrl)/\(playlistId)/items")!
		var parameters = session.sessionParameters
		parameters["trackIds"] = ids.map(String.init).joined(separator: ",")
		// Without duplicates, Tidal leaves out the IDs already in the playlist and adds the others
		parameters["onDupes"] = duplicate ? "ADD" : "FAIL"
		do {
			_ = try await session.post(url: url, parameters: parameters, etag: etag(for: playlistId))
			return .added
		} catch let error as RequestError where error.statusCode == 404 {
			return .notFound
		} catch {
			return .failed
		}
	}
	
	public func addTrack(_ trackId: Int, to playlistId: String, duplicate: Bool) async -> Bool {
		await addTracks([trackId], to: playlistId, duplicate: duplicate)
	}
	
	public func removeItem(atIndex index: Int, from playlistId: String) async -> Bool {
		let url = URL(string: "\(baseUrl)/\(playlistId)/items/\(index)")!
		var parameters = session.sessionParameters
		parameters["order"] = "INDEX"
		parameters["orderDirection"] = "ASC"
		do {
			_ = try await session.delete(url: url, parameters: parameters, etag: etag(for: playlistId))
			return true
		} catch {
			return false
		}
	}
	
	/// Removes several items with few requests
	/// - Parameter indices: Positions before the removal, starting at 0
	/// - Returns: False if a request failed. The items of the requests before it are removed by then.
	public func removeItems(atIndices indices: [Int], from playlistId: String) async -> Bool {
		// From the back, so the positions of the later requests stay the same
		let sorted = Set(indices).sorted(by: >)
		for start in stride(from: 0, to: sorted.count, by: 500) {
			let chunk = sorted[start..<min(start + 500, sorted.count)].sorted()
			let url = URL(string: "\(baseUrl)/\(playlistId)/items/\(chunk.map(String.init).joined(separator: ","))")!
			do {
				_ = try await session.delete(url: url, parameters: session.sessionParameters, etag: etag(for: playlistId))
			} catch {
				return false
			}
		}
		return true
	}
	
	/// - Parameter toIndex: The position the item ends up at, e.g. 2 moves the first of `[a, b, c]` to the end
	public func moveItem(fromIndex: Int, toIndex: Int, in playlistId: String) async -> Bool {
		let url = URL(string: "\(baseUrl)/\(playlistId)/items/\(fromIndex)")!
		var parameters = session.sessionParameters
		parameters["toIndex"] = "\(toIndex)"
		do {
			_ = try await session.post(url: url, parameters: parameters, etag: etag(for: playlistId))
			return true
		} catch {
			return false
		}
	}
	
	// MARK: By entry
	
	/// Items sent in one request
	static let itemBatchSize = 20
	
	/// Removes the items wherever they are now, by the ID of their entry, so changes to the playlist meanwhile can't make it remove another one.
	/// Through Tidal's official API. Items already removed are ignored.
	/// - Parameter items: As ``Session/playlistItems(playlistId:)`` lists them, which gives each entry its ID
	/// - Returns: False also if an item has no entry ID. The batches before a failed one are removed by then.
	public func remove(_ items: [PlaylistItem], from playlistId: String) async -> Bool {
		await sendItems(.delete, items, before: nil, playlistId: playlistId)
	}
	
	/// Moves the items in front of another one, keeping their order, or to the end, by the ID of their entry.
	/// Through Tidal's official API.
	/// - Parameters:
	///   - items: As ``Session/playlistItems(playlistId:)`` lists them, which gives each entry its ID
	///   - before: The item to move them in front of, nil for the end
	/// - Returns: False also if an item has no entry ID
	public func move(_ items: [PlaylistItem], before: PlaylistItem?, in playlistId: String) async -> Bool {
		await sendItems(.patch, items, before: before, playlistId: playlistId)
	}
	
	private func sendItems(_ method: Network.HttpMethod, _ items: [PlaylistItem], before: PlaylistItem?, playlistId: String) async -> Bool {
		let url = URL(string: "\(AuthInformation.OpenAPILocation)/playlists/\(playlistId)/relationships/items")!
		let parameters = session.countryCode.map { ["countryCode": $0] } ?? [:]
		// Each batch goes in front of the same item, or to the end, after the batch before, so the order stays
		for start in stride(from: 0, to: items.count, by: Self.itemBatchSize) {
			guard let document = PlaylistItemsDocument(Array(items[start..<min(start + Self.itemBatchSize, items.count)]), before: before) else {
				return false
			}
			do {
				let _: IgnoredAnswer = try await session.send(method, url: url, parameters: parameters, document: document)
			} catch {
				return false
			}
		}
		return true
	}
	
	public func create(title: String, description: String) async -> Playlist? {
		guard let userId = session.userId else {
			return nil
		}
		let url = URL(string: "\(AuthInformation.APILocation)/users/\(userId)/playlists")!
		var parameters = session.sessionParameters
		parameters["title"] = "\(title)"
		parameters["description"] = "\(description)"
		do {
			let response: Playlist = try await session.post(url: url, parameters: parameters)
			return response
		} catch {
			return nil
		}
	}
	
	public func edit(playlistId: String, title: String, description: String) async -> Bool {
		let url = URL(string: "\(baseUrl)/\(playlistId)")!
		var parameters = session.sessionParameters
		parameters["title"] = "\(title)"
		parameters["description"] = "\(description)"
		do {
			_ = try await session.post(url: url, parameters: parameters)
			return true
		} catch {
			return false
		}
	}
	
	/// Makes a playlist public, so others can find it on the profile, or private. Through the v2 API, as v1 can't change it.
	public func setPublic(_ isPublic: Bool, playlistId: String) async -> Bool {
		let url = URL(string: "\(AuthInformation.APIv2Location)/playlists/\(playlistId)/\(isPublic ? "set-public" : "set-private")")!
		do {
			try await session.put(url: url, parameters: session.countryCode.map { ["countryCode": $0] } ?? [:])
			return true
		} catch {
			return false
		}
	}
	
	public func delete(playlistId: String) async -> Bool {
		let url = URL(string: "\(baseUrl)/\(playlistId)")!
		do {
			_ = try await session.delete(url: url, parameters: session.sessionParameters, etag: etag(for: playlistId))
			return true
		} catch {
			return false
		}
	}
}

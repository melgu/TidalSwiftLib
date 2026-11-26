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

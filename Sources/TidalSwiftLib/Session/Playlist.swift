//
//  Playlist.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 01.08.20.
//  Copyright © 2020 Melvin Gundlach. All rights reserved.
//

import Foundation

public enum PlaylistOrder: String {
	case dateAdded = "DATE"
	case name = "NAME"
}

extension Session {
	public func playlist(playlistId: String) async -> Playlist? {
		let url = URL(string: "\(AuthInformation.APILocation)/playlists/\(playlistId)")!
		do {
			let response: Playlist = try await get(url: url, parameters: sessionParameters)
			return response
		} catch {
			return nil
		}
	}
	
	/// The tracks of a playlist. Tidal returns each video as its "Audio from video" track,
	/// so the positions match those of ``playlistItems(playlistId:)``.
	public func playlistTracks(playlistId: String) async -> [Track]? {
		let url = URL(string: "\(AuthInformation.APILocation)/playlists/\(playlistId)/tracks")!
		return await allPlaylistPages(Tracks.self, url: url, pageSize: 999)
	}
	
	/// The tracks and videos of a playlist, in the order of the positions that
	/// ``PlaylistEditing/removeItem(atIndex:from:)`` and ``PlaylistEditing/moveItem(fromIndex:toIndex:in:)`` take
	public func playlistItems(playlistId: String) async -> [PlaylistItem]? {
		let url = URL(string: "\(AuthInformation.APILocation)/playlists/\(playlistId)/items")!
		// Maximum of 100 allowed by Tidal
		return await allPlaylistPages(PlaylistItems.self, url: url, pageSize: 100)
	}
	
	private func allPlaylistPages<Page: PagedList>(_ pageType: Page.Type, url: URL, pageSize: Int) async -> [Page.Item]? {
		var items: [Page.Item] = []
		var offset = 0
		while true {
			var parameters = sessionParameters
			parameters["limit"] = "\(pageSize)"
			parameters["offset"] = "\(offset)"
			do {
				let page: Page = try await get(url: url, parameters: parameters)
				items += page.items
				// Tidal may use a smaller page size than asked for
				offset += max(page.limit, 1)
				if offset >= page.totalNumberOfItems {
					return items
				}
			} catch {
				return nil
			}
		}
	}
}

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
		var playlists: [PlaylistExport] = []
		for (index, playlist) in own.enumerated() {
			progress?(.loadingPlaylist(title: playlist.title, number: index + 1, of: own.count))
			guard let items = await playlistItems(playlistId: playlist.uuid) else {
				throw AccountBackupError.couldNotLoadPlaylist(title: playlist.title)
			}
			playlists.append(PlaylistExport(playlist: playlist, items: items))
		}
		return AccountBackup(userId: userId, favorites: current, playlists: playlists)
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
		let (own, others) = playlists.reduce(into: ([Playlist](), [FavoritePlaylist]())) { result, favorite in
			if favorite.playlist.creator.id == userId {
				result.0.append(favorite.playlist)
			} else {
				result.1.append(favorite)
			}
		}
		return (AccountBackup.FavoriteLists(tracks: tracks, videos: videos, albums: albums, artists: artists, playlists: others), own)
	}
}

//
//  AccountBackup.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 25.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation

/// The favorites and own playlists of an account as a file, made with ``Session/backup(progress:)``.
///
/// Like ``PlaylistExport``, it keeps IDs and what's needed to recognize the items or find them again, not the library's models.
/// Restore it with ``Session/restorePlan(for:options:)`` and ``Session/restore(_:progress:)``.
nonisolated public struct AccountBackup: Codable, Equatable, Sendable {
	/// Files with a higher version can't be read
	public static let currentFormatVersion = 1
	
	public let formatVersion: Int
	public let exportedAt: Date
	/// The account the backup was made of
	public let userId: Int
	public let favorites: FavoriteLists
	/// The account's own playlists, in Tidal's order. Favorite playlists of others are in ``favorites``.
	public let playlists: [PlaylistExport]
	
	/// Newest first, as Tidal lists them. Their dates can't be restored, as Tidal sets them when adding.
	public struct FavoriteLists: Codable, Equatable, Sendable {
		public let tracks: [PlaylistExport.Item]
		public let videos: [PlaylistExport.Item]
		public let albums: [AlbumEntry]
		public let artists: [ArtistEntry]
		/// Playlists of others
		public let playlists: [PlaylistEntry]
		
		public var count: Int {
			tracks.count + videos.count + albums.count + artists.count + playlists.count
		}
		
		init(tracks: [PlaylistExport.Item], videos: [PlaylistExport.Item], albums: [AlbumEntry], artists: [ArtistEntry], playlists: [PlaylistEntry]) {
			self.tracks = tracks
			self.videos = videos
			self.albums = albums
			self.artists = artists
			self.playlists = playlists
		}
		
		/// - Parameter playlists: Without the account's own playlists
		@MainActor init(tracks: [FavoriteTrack], videos: [FavoriteVideo], albums: [FavoriteAlbum], artists: [FavoriteArtist], playlists: [FavoritePlaylist]) {
			self.tracks = tracks.map { PlaylistExport.Item(.track($0.item)).dated($0.created) }
			self.videos = videos.map { PlaylistExport.Item(.video($0.item)).dated($0.created) }
			self.albums = albums.map { AlbumEntry(id: $0.item.id, title: $0.item.title, version: $0.item.version, artists: ($0.item.artists ?? []).map(\.name), upc: $0.item.upc, dateAdded: $0.created) }
			self.artists = artists.map { ArtistEntry(id: $0.item.id, name: $0.item.name, dateAdded: $0.created) }
			self.playlists = playlists.map { PlaylistEntry(uuid: $0.playlist.uuid, title: $0.playlist.title, creator: $0.playlist.creator.name, dateAdded: $0.created) }
		}
	}
	
	public struct AlbumEntry: Codable, Equatable, Sendable {
		public let id: Int
		public let title: String
		public let version: String?
		public let artists: [String]
		public let upc: String?
		public let dateAdded: Date?
	}
	
	public struct ArtistEntry: Codable, Equatable, Sendable {
		public let id: Int
		public let name: String
		public let dateAdded: Date?
	}
	
	public struct PlaylistEntry: Codable, Equatable, Sendable {
		public let uuid: String
		public let title: String
		/// The name of the creator
		public let creator: String?
		public let dateAdded: Date?
	}
	
	init(exportedAt: Date = .now, userId: Int, favorites: FavoriteLists, playlists: [PlaylistExport]) {
		formatVersion = Self.currentFormatVersion
		self.exportedAt = exportedAt
		self.userId = userId
		self.favorites = favorites
		self.playlists = playlists
	}
	
	/// Reads a file written by ``data()``
	/// - Throws: ``AccountBackupError/unsupportedFormatVersion(_:)`` for files of a newer version, or a `DecodingError`
	public init(data: Data) throws {
		let version = try ExportCoding.formatVersion(of: data)
		guard version <= Self.currentFormatVersion else {
			throw AccountBackupError.unsupportedFormatVersion(version)
		}
		self = try ExportCoding.decoder.decode(Self.self, from: data)
	}
	
	/// Pretty-printed JSON with sorted keys, so backups can be compared with a diff
	public func data() throws -> Data {
		try ExportCoding.encoder.encode(self)
	}
}

nonisolated public enum AccountBackupError: Error, Equatable, CustomStringConvertible {
	case unsupportedFormatVersion(Int)
	case notLoggedIn
	case couldNotLoadFavorites(FavoriteKind)
	case couldNotLoadPlaylist(title: String)
	
	public var description: String {
		switch self {
		case let .unsupportedFormatVersion(version):
			"The file has format version \(version), but only versions up to \(AccountBackup.currentFormatVersion) can be read. Update to read it."
		case .notLoggedIn:
			"Not logged in"
		case let .couldNotLoadFavorites(kind):
			"Couldn't load the favorite \(kind.rawValue)"
		case let .couldNotLoadPlaylist(title):
			"Couldn't load the items of \(title)"
		}
	}
}

nonisolated extension PlaylistExport.Item {
	/// With the date it was added to the favorites
	func dated(_ date: Date) -> Self {
		Self(type: type, id: id, title: title, version: version, artists: artists, album: album, isrc: isrc, duration: duration, dateAdded: date)
	}
}

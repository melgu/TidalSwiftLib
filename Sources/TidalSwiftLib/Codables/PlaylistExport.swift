//
//  PlaylistExport.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 25.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation

/// A playlist as a file, to back it up or copy it to another playlist or account.
///
/// It keeps the IDs of the items and what's needed to recognize them or find them again, not the library's models,
/// so the file stays readable and doesn't change with them. Import it with ``PlaylistEditing/importPlaylist(_:mode:)``.
nonisolated public struct PlaylistExport: Codable, Equatable, Sendable {
	/// Files with a higher version can't be read
	public static let currentFormatVersion = 1
	
	public let formatVersion: Int
	public let exportedAt: Date
	public let uuid: String
	public let url: URL
	public let title: String
	public let description: String?
	public let isPublic: Bool
	/// The name of the creator
	public let creator: String?
	public let created: Date
	public let lastUpdated: Date
	public let items: [Item]
	
	public struct Item: Codable, Equatable, Sendable {
		public enum Kind: String, Codable, Sendable {
			case track, video
		}
		
		public let type: Kind
		/// The track or video ID
		public let id: Int
		public let title: String
		public let version: String?
		public let artists: [String]
		/// Only for tracks
		public let album: String?
		/// Only for tracks. Finds the recording again if Tidal no longer knows its ID.
		public let isrc: String?
		/// In seconds
		public let duration: Int
		/// When it was added to the playlist. Can't be restored, as Tidal sets it when adding.
		public let dateAdded: Date?
		
		@MainActor public init(_ item: PlaylistItem) {
			switch item {
			case let .track(track):
				type = .track
				version = track.version
				album = track.album.title
				isrc = track.isrc
			case .video:
				type = .video
				version = nil
				album = nil
				isrc = nil
			}
			id = item.mediaId
			title = item.title
			artists = item.artists.map(\.name)
			duration = item.duration
			dateAdded = item.dateAdded
		}
		
		init(type: Kind, id: Int, title: String, version: String? = nil, artists: [String], album: String? = nil, isrc: String? = nil, duration: Int, dateAdded: Date? = nil) {
			self.type = type
			self.id = id
			self.title = title
			self.version = version
			self.artists = artists
			self.album = album
			self.isrc = isrc
			self.duration = duration
			self.dateAdded = dateAdded
		}
	}
	
	private enum CodingKeys: String, CodingKey {
		case formatVersion, exportedAt, uuid, url, title, description
		case isPublic = "public"
		case creator, created, lastUpdated, items
	}
	
	@MainActor public init(playlist: Playlist, items: [PlaylistItem], exportedAt: Date = .now) {
		formatVersion = Self.currentFormatVersion
		self.exportedAt = exportedAt
		uuid = playlist.uuid
		url = playlist.url
		title = playlist.title
		description = playlist.description
		isPublic = playlist.publicPlaylist
		creator = playlist.creator.name
		created = playlist.created
		lastUpdated = playlist.lastUpdated
		self.items = items.map(Item.init)
	}
	
	/// Reads a file written by ``data()``
	/// - Throws: ``PlaylistExportError/unsupportedFormatVersion(_:)`` for files of a newer version, or a `DecodingError`
	public init(data: Data) throws {
		struct Version: Decodable {
			let formatVersion: Int
		}
		let decoder = Self.decoder
		let version = try decoder.decode(Version.self, from: data).formatVersion
		guard version <= Self.currentFormatVersion else {
			throw PlaylistExportError.unsupportedFormatVersion(version)
		}
		self = try decoder.decode(Self.self, from: data)
	}
	
	/// Pretty-printed JSON with sorted keys, so exports of the same playlist can be compared with a diff
	public func data() throws -> Data {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		encoder.dateEncodingStrategy = .iso8601
		return try encoder.encode(self)
	}
	
	private static var decoder: JSONDecoder {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return decoder
	}
}

nonisolated public enum PlaylistExportError: Error, Equatable, CustomStringConvertible {
	case unsupportedFormatVersion(Int)
	
	public var description: String {
		switch self {
		case let .unsupportedFormatVersion(version):
			"The file has format version \(version), but only versions up to \(PlaylistExport.currentFormatVersion) can be read. Update to read it."
		}
	}
}

//
//  Playlist.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 01.08.20.
//  Copyright © 2020 Melvin Gundlach. All rights reserved.
//

import Foundation

struct Playlists: Decodable {
	let limit: Int
	let offset: Int
	let totalNumberOfItems: Int
	let items: [Playlist]
}

struct PlaylistItems: @MainActor PagedList {
	let limit: Int
	let offset: Int
	let totalNumberOfItems: Int
	let items: [PlaylistItem]
}

/// A track or video in a playlist
public enum PlaylistItem: Codable, Equatable, Hashable, Identifiable {
	case track(Track)
	case video(Video)
	
	/// Unique within the playlist, even when it contains a track or video more than once
	public var id: String {
		switch self {
		case let .track(track):
			track.itemUuid?.uuidString ?? "track-\(track.id)"
		case let .video(video):
			video.itemUuid?.uuidString ?? "video-\(video.id)"
		}
	}
	
	/// The track or video ID. ``PlaylistEditing/addTracks(_:to:duplicate:)`` takes both, as they share one number space.
	public var mediaId: Int {
		switch self {
		case let .track(track): track.id
		case let .video(video): video.id
		}
	}
	
	public var track: Track? {
		if case let .track(track) = self {
			return track
		}
		return nil
	}
	
	public var video: Video? {
		if case let .video(video) = self {
			return video
		}
		return nil
	}
	
	public var title: String {
		switch self {
		case let .track(track): track.title
		case let .video(video): video.title
		}
	}
	
	public var artists: [Artist] {
		switch self {
		case let .track(track): track.artists
		case let .video(video): video.artists
		}
	}
	
	/// In seconds
	public var duration: Int {
		switch self {
		case let .track(track): track.duration
		case let .video(video): video.duration
		}
	}
	
	/// When it was added to the playlist
	public var dateAdded: Date? {
		switch self {
		case let .track(track): track.dateAdded
		case let .video(video): video.dateAdded
		}
	}
	
	private enum CodingKeys: String, CodingKey {
		case type, item
	}
	
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let type = try container.decode(String.self, forKey: .type)
		switch type {
		case "track":
			self = .track(try container.decode(Track.self, forKey: .item))
		case "video":
			self = .video(try container.decode(Video.self, forKey: .item))
		default:
			// Not skipped, as the positions of the items after it would no longer match Tidal's
			throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown playlist item type \(type)")
		}
	}
	
	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		switch self {
		case let .track(track):
			try container.encode("track", forKey: .type)
			try container.encode(track, forKey: .item)
		case let .video(video):
			try container.encode("video", forKey: .type)
			try container.encode(video, forKey: .item)
		}
	}
}

public enum PlaylistType: String, Codable {
	case user = "USER"
	case editorial = "EDITORIAL"
	case artist = "ARTIST"
	case podcast = "PODCAST"
	// Haven't seen others yet
}

public struct Playlist: Codable, Equatable, Identifiable, Hashable {
	public var id: String { uuid }
	
	public let uuid: String
	public let title: String
	public let numberOfTracks: Int
	public let numberOfVideos: Int
	public let creator: PlaylistCreator
	public let description: String?
	public let duration: Int
	public let lastUpdated: Date
	public let created: Date
	public let type: PlaylistType
	public let publicPlaylist: Bool
	public let url: URL
	public let image: String?
	public let popularity: Int
	public let squareImage: String?
	
	public func isInFavorites(session: Session) async -> Bool? {
		await session.favorites?.doFavoritesContainPlaylist(playlistId: uuid)
	}
	
	public func imageUrl(session: Session, resolution: Int, resolutionY: Int? = nil) -> URL? {
		if squareImage == nil && image == nil {
			return nil
		}
		
		if let resolutionY = resolutionY {
			return session.imageUrl(imageId: squareImage ?? image!, resolution: resolution, resolutionY: resolutionY)
		}
		
		if let squareImage = squareImage {
			return session.imageUrl(imageId: squareImage, resolution: resolution)
		} else {
			return session.imageUrl(imageId: image!, resolution: 480, resolutionY: 320)
		}
	}
	
	// Offline
	
	// Playlist Editing
	
	public func addTracks(_ tracks: [Track], duplicate: Bool, session: Session) async -> Bool {
		return await session.playlistEditing.addTracks(tracks.map(\.id), to: uuid, duplicate: duplicate)
	}
	
	public func addTrack(_ track: Track, duplicate: Bool, session: Session) async -> Bool {
		return await session.playlistEditing.addTrack(track.id, to: uuid, duplicate: duplicate)
	}
	
	public func removeItem(atIndex index: Int, session: Session) async -> Bool {
		return await session.playlistEditing.removeItem(atIndex: index, from: uuid)
	}
	
	public func addVideos(_ videos: [Video], duplicate: Bool, session: Session) async -> Bool {
		return await session.playlistEditing.addTracks(videos.map(\.id), to: uuid, duplicate: duplicate)
	}
	
	public func addVideo(_ video: Video, duplicate: Bool, session: Session) async -> Bool {
		return await session.playlistEditing.addTrack(video.id, to: uuid, duplicate: duplicate)
	}
	
	public func moveItem(fromIndex: Int, toIndex: Int, session: Session) async -> Bool {
		return await session.playlistEditing.moveItem(fromIndex: fromIndex, toIndex: toIndex, in: uuid)
	}
	
	public func edit(title: String, description: String, session: Session) async -> Bool {
		return await session.playlistEditing.edit(playlistId: uuid, title: title, description: description)
	}
	
	public func delete(session: Session) async -> Bool {
		return await session.playlistEditing.delete(playlistId: uuid)
	}
	
	public static func == (lhs: Playlist, rhs: Playlist) -> Bool {
		lhs.uuid == rhs.uuid
	}
	
	public func hash(into hasher: inout Hasher) {
		hasher.combine(uuid)
	}
}

public struct PlaylistCreator: Codable {
	public let id: Int?
	public let name: String?
	public let url: URL?
	public let picture: String?
	public let popularity: Int?
	
	public func pictureUrl(session: Session, resolution: Int) -> URL? {
		guard let picture = picture else {
			return nil
		}
		return session.imageUrl(imageId: picture, resolution: resolution)
	}
}

public enum PlaylistSorting: Int, Codable {
	case dateAdded // to Favorites
	case title
	case lastUpdated
	case created
	case numberOfTracks
	case duration
	case type
	case popularity  // Optional
	case creator
}

extension Array where Element == Playlist {
	public func sortedPlaylists(by sorting: PlaylistSorting) -> [Playlist] {
		switch sorting {
		case .dateAdded:
			return self
		case .title:
			return self.sorted { $0.title.lowercased() < $1.title.lowercased() }
		case .lastUpdated:
			return self.sorted {
				($0.lastUpdated, $0.title.lowercased()) <
					($1.lastUpdated, $1.title.lowercased())
			}
		case .created:
			return self.sorted {
				($0.created, $0.title.lowercased()) <
					($1.created, $1.title.lowercased())
			}
		case .numberOfTracks:
			return self.sorted {
				($0.numberOfTracks, $0.title.lowercased()) <
					($1.numberOfTracks, $1.title.lowercased())
			}
		case .duration:
			return self.sorted {
				($0.duration, $0.title.lowercased()) <
					($1.duration, $1.title.lowercased())
			}
		case .type:
			return self.sorted {
				($0.type.rawValue, $0.title.lowercased()) <
					($1.type.rawValue, $1.title.lowercased())
			}
		case .popularity:
			return self.sorted {
				($0.popularity, $0.title.lowercased()) <
					($1.popularity, $1.title.lowercased())
			}
		case .creator:
			return self.sorted {
				($0.creator.name ?? "zzzzzzzzzz", $0.title.lowercased()) <
					($1.creator.name ?? "zzzzzzzzzz", $1.title.lowercased())
			}
		}
	}
}

//
//  Blocks.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 26.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation

nonisolated public enum BlockKind: String, CaseIterable, Sendable {
	case artists, tracks, videos
	
	/// The form parameter of a block
	var idParameter: String {
		switch self {
		case .artists: "artistId"
		case .tracks: "trackId"
		case .videos: "videoId"
		}
	}
}

/// Artists, tracks and videos the account blocked, so Tidal doesn't recommend or play them in mixes and radio. Get it from ``Session/blocks``.
public struct Blocks {
	/// Tidal's maximum
	static let pageSize = 50
	
	unowned let session: Session
	
	private func url(_ kind: BlockKind) -> URL? {
		session.userId.map { URL(string: "\(AuthInformation.APILocation)/users/\($0)/blocks/\(kind.rawValue)")! }
	}
	
	/// Newest first. `created` is when it was blocked.
	public func artists() async -> [FavoriteArtist]? {
		await allPages(FavoriteArtists.self, kind: .artists)
	}
	
	/// Newest first. `created` is when it was blocked.
	public func tracks() async -> [FavoriteTrack]? {
		await allPages(FavoriteTracks.self, kind: .tracks)
	}
	
	/// Newest first. `created` is when it was blocked.
	public func videos() async -> [FavoriteVideo]? {
		await allPages(FavoriteVideos.self, kind: .videos)
	}
	
	/// - Returns: False also for an ID Tidal doesn't know
	@discardableResult public func block(_ kind: BlockKind, id: Int) async -> Bool {
		await add(kind, id: id) == .added
	}
	
	/// Tidal accepts IDs that aren't blocked
	@discardableResult public func unblock(_ kind: BlockKind, id: Int) async -> Bool {
		guard let url = url(kind)?.appending(path: "\(id)") else {
			return false
		}
		do {
			_ = try await session.delete(url: url, parameters: session.sessionParameters)
			return true
		} catch {
			return false
		}
	}
	
	/// Blocking again is accepted and changes nothing
	func add(_ kind: BlockKind, id: Int) async -> AddOutcome {
		guard let url = url(kind) else {
			return .failed
		}
		var parameters = session.sessionParameters
		parameters[kind.idParameter] = "\(id)"
		do {
			_ = try await session.post(url: url, parameters: parameters)
			return .added
		} catch let error as RequestError where error.statusCode == 404 {
			return .notFound
		} catch {
			return .failed
		}
	}
	
	private func allPages<Page: PagedList>(_ pageType: Page.Type, kind: BlockKind) async -> [Page.Item]? {
		guard let url = url(kind) else {
			return nil
		}
		var items: [Page.Item] = []
		var offset = 0
		while true {
			var parameters = session.sessionParameters
			parameters["limit"] = "\(Self.pageSize)"
			parameters["offset"] = "\(offset)"
			do {
				let page: Page = try await session.get(url: url, parameters: parameters)
				items += page.items
				offset += Self.pageSize
				if offset >= page.totalNumberOfItems || page.items.isEmpty {
					return items
				}
			} catch {
				return nil
			}
		}
	}
}

extension Session {
	/// The artists, tracks and videos the account blocked
	public var blocks: Blocks {
		Blocks(session: self)
	}
}

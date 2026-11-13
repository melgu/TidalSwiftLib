//
//  Mix.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 01.08.20.
//  Copyright © 2020 Melvin Gundlach. All rights reserved.
//

import Foundation

struct Mixes: Decodable {
	let selfLink: URL?
	let id: String
	let title: String
	let rows: [MixesModules]
}

struct MixesModules: Decodable {
	let modules: [MixesModule]
}

struct MixesModule: Decodable {
	let id: String
	let width: Int
	let title: String
	let pagedList: MixesPagedList
}

struct MixesPagedList: Decodable {
	let limit: Int
	let offset: Int
	let totalNumberOfItems: Int
	let items: [MixesItem]
	let dataApiPath: String
}

public enum MixType: String, Codable {
	case header = "MIX_HEADER" // Because  of how Tidal structures its data
	case audio = "DAILY_MIX"
	case video = "VIDEO_DAILY_MIX"
	case discovery = "DISCOVERY_MIX"
}

public struct MixesItem: Codable, Equatable, Identifiable {
	public let id: String
	public let title: String
	public let subTitle: String
	/// The cover in several sizes. Optional, as mixes saved before it was added lack it.
	public let images: MixesImages?
	public let mixType: MixType
	
	/// The smallest cover that is at least `resolution` pixels wide, or the largest one there is
	public func imageUrl(resolution: Int) -> URL? {
		images?.url(resolution: resolution)
	}
	
	public static func == (lhs: MixesItem, rhs: MixesItem) -> Bool {
		lhs.id == rhs.id
	}
}

public struct MixesImages: Codable {
	public let small: MixesImage?
	public let medium: MixesImage?
	public let large: MixesImage?
	
	enum CodingKeys: String, CodingKey {
		case small = "SMALL"
		case medium = "MEDIUM"
		case large = "LARGE"
	}
	
	/// The smallest image that is at least `resolution` pixels wide, or the largest one there is
	public func url(resolution: Int) -> URL? {
		let available = [small, medium, large].compactMap { $0 }.sorted { $0.width < $1.width }
		return (available.first { $0.width >= resolution } ?? available.last)?.url
	}
}

public struct MixesImage: Codable {
	public let width: Int
	public let height: Int
	public let url: URL
}

struct Mix: Decodable {
	let selfLink: URL?
	let id: String
	let title: String
	let rows: [MixModules]
	// Aufpassen, da unterschiedliche Modules
	// Das interessante, welche Tracks enthält, ist [1]
}

struct MixModules: Decodable {
	let modules: [MixModule]
}

enum MixPlaylistType: String, Decodable {
	case header = "MIX_HEADER" // Because  of how Tidal structures its data
	case audio = "TRACK_LIST"
	case video = "VIDEO_LIST"
}

struct MixModule: Decodable {
	let id: String
	let title: String
	let type: MixPlaylistType
	let pagedList: Tracks?
}

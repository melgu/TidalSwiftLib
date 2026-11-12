//
//  Others.swift
//  TidalSwift
//
//  Created by Melvin Gundlach on 19.03.19.
//  Copyright © 2019 Melvin Gundlach. All rights reserved.
//

import Foundation

public enum AudioQuality: String, Codable {
	// Only the PKCE login gets Hi-Res. Tidal answers the device login's requests with 16 Bit / 44,1 kHz FLAC.
	// Tracks show Hi-Res via MediaMetadata instead.
	case max = "HI_RES_LOSSLESS"	// Max: Lossless, up to 24 Bit / 192 kHz
	case high = "LOSSLESS"			// High: Lossless, 16 Bit / 44,1 kHz
	case medium = "HIGH"			// Low: 320 kbps
	case low = "LOW"				// Low: 96 kbps
	
	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		let rawValue = try container.decode(String.self)
		if let quality = AudioQuality(rawValue: rawValue) {
			self = quality
		} else {
			throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown audio quality \(rawValue)")
		}
	}
}

public struct MediaMetadata: Codable {
	public let tags: [String]
}

extension AudioQuality: CaseIterable {}
extension AudioQuality: Identifiable {
	public var id: Self { self }
}

struct LoginResponse: Decodable {
	let userId: Int
	let sessionId: String
	let countryCode: String
}

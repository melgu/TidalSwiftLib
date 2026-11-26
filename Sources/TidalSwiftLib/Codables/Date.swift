//
//  Date.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 01.08.20.
//  Copyright © 2020 Melvin Gundlach. All rights reserved.
//

import Foundation

extension JSONDecoder {
	static let custom: JSONDecoder = {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601OptionalTime)
		return decoder
	}()
}

extension JSONDecoder {
	/// For the v2 APIs, whose dates come as `2026-02-26T18:28:14.163+0000`, `2026-11-24T20:51:10.937Z` or with microseconds, `2026-11-26T08:47:28.984575Z`
	nonisolated static let v2: JSONDecoder = {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .custom { decoder in
			let container = try decoder.singleValueContainer()
			let string = try container.decode(String.self)
			guard let date = Date(v2String: string) else {
				throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown date format: \(string)")
			}
			return date
		}
		return decoder
	}()
}

extension JSONEncoder {
	/// Dates as ISO 8601 with seconds, as the v2 APIs take them
	nonisolated static let v2: JSONEncoder = {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		return encoder
	}()
}

nonisolated extension Date {
	init?(v2String string: String) {
		// The fraction is cut to milliseconds, which is all ISO8601FormatStyle reads
		let trimmed = string.replacing(/(\.\d{3})\d+/) { $0.1 }
		let styles: [Date.ISO8601FormatStyle] = [
			.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted),
			.iso8601.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .omitted),
		]
		guard let date = styles.lazy.compactMap({ try? $0.parse(trimmed) }).first else {
			return nil
		}
		self = date
	}
}

nonisolated class OptionalTimeDateFormatter: DateFormatter {
	static let withoutTime: DateFormatter = {
		let formatter = DateFormatter()
		formatter.calendar = Calendar(identifier: .iso8601)
		formatter.timeZone = TimeZone(identifier: "UTC")
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()
	
	func setup() {
		self.calendar = Calendar(identifier: .iso8601)
		self.timeZone = TimeZone(identifier: "UTC")
		self.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZ"
	}
	
	override init() {
		super.init()
		setup()
	}
	
	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		setup()
	}
	
	override func date(from string: String) -> Date? {
		if let result = super.date(from: string) {
			return result
		}
		return OptionalTimeDateFormatter.withoutTime.date(from: string)
	}
}

extension DateFormatter {
	static let iso8601OptionalTime = OptionalTimeDateFormatter()
}

extension DateFormatter {
	public static let dateOnly: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = DateFormatter.Style.long
		formatter.timeStyle = DateFormatter.Style.none
		return formatter
	}()
}

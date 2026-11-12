//
//  DASHManifest.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 12.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation

/// The single audio representation of a track's DASH manifest, as `playbackinfopostpaywall` returns it to the PKCE client.
///
/// Tidal lists the segments with a `SegmentTemplate` and a `SegmentTimeline`:
/// an initialization segment and numbered fragmented MP4 media segments, all on absolute URLs with a time-limited token.
nonisolated struct DASHManifest: Sendable {
	enum ParseError: Error {
		/// The manifest uses features this parser doesn't handle, like encryption or several representations
		case unsupportedManifest
	}
	
	/// `flac` or an AAC codec string like `mp4a.40.2`
	let codecs: String
	let bandwidth: Int?
	let sampleRate: Int?
	let initializationSegment: URL
	let segments: [Segment]
	
	struct Segment: Sendable {
		let url: URL
		/// In seconds
		let duration: Double
	}
	
	var isFLAC: Bool {
		codecs.lowercased() == "flac"
	}
	
	/// In seconds
	var duration: Double {
		segments.reduce(0) { $0 + $1.duration }
	}
	
	init(_ data: Data) throws {
		let delegate = ParserDelegate()
		let parser = XMLParser(data: data)
		parser.delegate = delegate
		guard parser.parse(), !delegate.isProtected, delegate.representationCount == 1,
			  let codecs = delegate.codecs,
			  let initialization = delegate.initialization,
			  let media = delegate.media,
			  let initializationSegment = URL(string: initialization),
			  !delegate.timeline.isEmpty
		else {
			throw ParseError.unsupportedManifest
		}
		
		var segments: [Segment] = []
		var number = delegate.startNumber
		for entry in delegate.timeline {
			// A negative repeat count means "until the end of the period", which a static manifest doesn't need
			guard entry.repeatCount >= 0 else { throw ParseError.unsupportedManifest }
			for _ in 0...entry.repeatCount {
				guard let url = URL(string: media.replacingOccurrences(of: "$Number$", with: String(number))) else {
					throw ParseError.unsupportedManifest
				}
				segments.append(Segment(url: url, duration: Double(entry.duration) / Double(delegate.timescale)))
				number += 1
			}
		}
		
		self.codecs = codecs
		self.bandwidth = delegate.bandwidth
		self.sampleRate = delegate.sampleRate
		self.initializationSegment = initializationSegment
		self.segments = segments
	}
	
	/// An HLS media playlist with the same segments, which AVPlayer can play
	var hlsPlaylist: String {
		let targetDuration = Int((segments.map(\.duration).max() ?? 1).rounded(.up))
		var playlist = """
			#EXTM3U
			#EXT-X-VERSION:7
			#EXT-X-PLAYLIST-TYPE:VOD
			#EXT-X-INDEPENDENT-SEGMENTS
			#EXT-X-TARGETDURATION:\(targetDuration)
			#EXT-X-MAP:URI="\(initializationSegment.absoluteString)"
			
			"""
		for segment in segments {
			playlist += "#EXTINF:\(String(format: "%.6f", segment.duration)),\n\(segment.url.absoluteString)\n"
		}
		playlist += "#EXT-X-ENDLIST\n"
		return playlist
	}
}

private nonisolated final class ParserDelegate: NSObject, XMLParserDelegate {
	struct TimelineEntry {
		let duration: Int
		let repeatCount: Int
	}
	
	var representationCount = 0
	var isProtected = false
	var codecs: String?
	var bandwidth: Int?
	var sampleRate: Int?
	var timescale = 1
	var initialization: String?
	var media: String?
	var startNumber = 1
	var timeline: [TimelineEntry] = []
	
	func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
		switch elementName {
		case "Representation":
			representationCount += 1
			codecs = attributes["codecs"]
			bandwidth = attributes["bandwidth"].flatMap(Int.init)
			sampleRate = attributes["audioSamplingRate"].flatMap(Int.init)
		case "ContentProtection":
			isProtected = true
		case "SegmentTemplate":
			timescale = attributes["timescale"].flatMap(Int.init) ?? 1
			initialization = attributes["initialization"]
			media = attributes["media"]
			startNumber = attributes["startNumber"].flatMap(Int.init) ?? 1
		case "S":
			guard let duration = attributes["d"].flatMap(Int.init) else {
				parser.abortParsing()
				return
			}
			timeline.append(TimelineEntry(duration: duration, repeatCount: attributes["r"].flatMap(Int.init) ?? 0))
		default:
			break
		}
	}
}

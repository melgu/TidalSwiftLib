//
//  DASHStream.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 12.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import AVFoundation
import Foundation

/// Plays a DASH manifest by handing AVPlayer an equivalent HLS playlist.
///
/// AVPlayer neither plays DASH nor HLS playlists from local files, but it asks a resource loader for URLs with a custom scheme.
/// The loader answers the playlist request, AVPlayer loads the segments from Tidal itself.
nonisolated final class DASHAsset: AVURLAsset, @unchecked Sendable {
	static let scheme = "tidalswift-dash"
	
	/// The asset only holds its resource loader's delegate weakly
	private let loader: PlaylistLoader
	
	static func url(trackId: Int) -> URL {
		URL(string: "\(scheme)://track/\(trackId).m3u8")!
	}
	
	init(manifest: DASHManifest, trackId: Int, options: [String: Any]?) {
		loader = PlaylistLoader(playlist: Data(manifest.hlsPlaylist.utf8))
		super.init(url: Self.url(trackId: trackId), options: options)
		resourceLoader.setDelegate(loader, queue: .global(qos: .userInitiated))
	}
	
	private final class PlaylistLoader: NSObject, AVAssetResourceLoaderDelegate, Sendable {
		let playlist: Data
		
		init(playlist: Data) {
			self.playlist = playlist
		}
		
		func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
			guard loadingRequest.request.url?.scheme == DASHAsset.scheme else { return false }
			loadingRequest.dataRequest?.respond(with: playlist)
			loadingRequest.finishLoading()
			return true
		}
	}
}

/// Joins the segments of a DASH manifest into a single file
nonisolated enum DASHDownloader {
	enum DownloadError: Error {
		/// The initialization segment has no FLAC configuration
		case missingFLACConfiguration
		case malformedSegment
	}
	
	/// FLAC streams become a native FLAC file, other codecs a fragmented MP4 file
	@concurrent
	static func download(_ manifest: DASHManifest, to outputURL: URL) async throws {
		let fileManager = FileManager.default
		try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		let temporaryDirectory = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: outputURL, create: true)
		defer { try? fileManager.removeItem(at: temporaryDirectory) }
		
		let temporaryURL = temporaryDirectory.appendingPathComponent(outputURL.lastPathComponent)
		fileManager.createFile(atPath: temporaryURL.path, contents: nil)
		let handle = try FileHandle(forWritingTo: temporaryURL)
		defer { try? handle.close() }
		
		let initialization = try await HLSDownloader.fetch(manifest.initializationSegment).data
		if manifest.isFLAC {
			try handle.write(contentsOf: try flacHeader(fromInitializationSegment: initialization, duration: manifest.duration))
			try await HLSDownloader.fetchSegments(manifest.segments.map(\.url), progress: { _ in }) { segment in
				// Every sample in the fragments is a FLAC frame, so their media data is the FLAC stream
				for payload in try ISOBox.payloads(ofType: "mdat", in: segment) {
					try handle.write(contentsOf: payload)
				}
			}
		} else {
			try handle.write(contentsOf: initialization)
			try await HLSDownloader.fetchSegments(manifest.segments.map(\.url), progress: { _ in }) { segment in
				try handle.write(contentsOf: segment)
			}
		}
		try handle.close()
		
		if fileManager.fileExists(atPath: outputURL.path) {
			try fileManager.removeItem(at: outputURL)
		}
		try fileManager.moveItem(at: temporaryURL, to: outputURL)
	}
	
	/// The `fLaC` marker and the metadata blocks of the `dfLa` box (ISO/IEC 14496-12 FLAC mapping)
	private static func flacHeader(fromInitializationSegment initialization: Data, duration: Double) throws -> Data {
		guard let configuration = ISOBox.find("dfLa", in: initialization, path: ["moov", "trak", "mdia", "minf", "stbl", "stsd"]),
			  configuration.count >= 4 + 4 + 34
		else {
			throw DownloadError.missingFLACConfiguration
		}
		// Version and flags precede the blocks
		var blocks = Data(configuration.dropFirst(4))
		let start = blocks.startIndex
		guard blocks[start] & 0x7F == 0 else { throw DownloadError.missingFLACConfiguration }
		
		// The streaming encoder doesn't know the length, but seeking and duration display rely on it
		let streamInfo = start + 4
		let sampleRate = Int(blocks[streamInfo + 10]) << 12 | Int(blocks[streamInfo + 11]) << 4 | Int(blocks[streamInfo + 12]) >> 4
		let totalSamplesOffset = streamInfo + 13
		let existingTotal = (UInt64(blocks[totalSamplesOffset] & 0x0F) << 32) | blocks[(totalSamplesOffset + 1)...(totalSamplesOffset + 4)].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
		if existingTotal == 0, sampleRate > 0 {
			let totalSamples = UInt64((duration * Double(sampleRate)).rounded()) & 0xF_FFFF_FFFF
			blocks[totalSamplesOffset] = (blocks[totalSamplesOffset] & 0xF0) | UInt8(totalSamples >> 32)
			for index in 0..<4 {
				blocks[totalSamplesOffset + 1 + index] = UInt8((totalSamples >> (8 * (3 - index))) & 0xFF)
			}
		}
		return Data("fLaC".utf8) + blocks
	}
}

/// Reads boxes of the ISO base media file format (MP4)
nonisolated enum ISOBox {
	/// The top-level boxes of `data`, as type and payload
	static func boxes(in data: Data) throws -> [(type: String, payload: Data)] {
		var result: [(String, Data)] = []
		var offset = data.startIndex
		while offset < data.endIndex {
			guard data.endIndex - offset >= 8 else { throw DASHDownloader.DownloadError.malformedSegment }
			var size = data[offset..<(offset + 4)].reduce(0) { $0 << 8 | Int($1) }
			let type = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
			var headerLength = 8
			if size == 1 {
				guard data.endIndex - offset >= 16 else { throw DASHDownloader.DownloadError.malformedSegment }
				size = data[(offset + 8)..<(offset + 16)].reduce(0) { $0 << 8 | Int($1) }
				headerLength = 16
			} else if size == 0 {
				size = data.endIndex - offset
			}
			guard size >= headerLength, size <= data.endIndex - offset else { throw DASHDownloader.DownloadError.malformedSegment }
			result.append((type, data[(offset + headerLength)..<(offset + size)]))
			offset += size
		}
		return result
	}
	
	static func payloads(ofType type: String, in data: Data) throws -> [Data] {
		try boxes(in: data).filter { $0.type == type }.map(\.payload)
	}
	
	/// The payload of the first box of `type` below the container boxes of `path`
	static func find(_ type: String, in data: Data, path: [String]) -> Data? {
		var current = data
		for container in path {
			guard let next = try? payloads(ofType: container, in: current).first else { return nil }
			current = next
			if container == "stsd" {
				// Full box header and entry count, then the sample entries
				guard current.count > 8, let entry = try? boxes(in: current.dropFirst(8)).first else { return nil }
				// An audio sample entry has 28 bytes of fields before its child boxes
				guard entry.payload.count > 28 else { return nil }
				current = Data(entry.payload.dropFirst(28))
			}
		}
		return try? payloads(ofType: type, in: current).first
	}
}

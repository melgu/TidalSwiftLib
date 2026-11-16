//
//  TagWriterTests.swift
//  TidalSwiftLibTests
//

import AVFoundation
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import TidalSwiftLib

/// A temporary directory, removed again when the test ends
final class TemporaryDirectory {
	let url: URL
	
	init() throws {
		url = FileManager.default.temporaryDirectory.appendingPathComponent("TidalSwiftLibTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
	}
	
	deinit {
		try? FileManager.default.removeItem(at: url)
	}
}

private let tags = AudioTags(
	title: "Get Lucky (Radio Edit)",
	artist: "Daft Punk, Pharrell Williams",
	album: "Random Access Memories",
	albumArtist: "Daft Punk",
	trackNumber: 8,
	trackTotal: 13,
	discNumber: 1,
	discTotal: 1,
	releaseDate: "2013-05-17",
	copyright: "℗ 2013 Daft Life",
	isrc: "USQX91300108",
	isCompilation: false,
	isExplicit: true,
	cover: nil
)

/// A 2×3 PNG
private func pngCover() throws -> Data {
	let context = try #require(CGContext(data: nil, width: 2, height: 3, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
	context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
	context.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
	let image = try #require(context.makeImage())
	let data = NSMutableData()
	let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
	CGImageDestinationAddImage(destination, image, nil)
	#expect(CGImageDestinationFinalize(destination))
	return data as Data
}

// MARK: - FLAC

struct FLACTagWriterTests {
	struct Block: Equatable {
		var type: UInt8
		var body: Data
	}
	
	static let streamInfo = Block(type: 0, body: Data((0..<34).map { UInt8($0) }))
	static let seekTable = Block(type: 3, body: Data(repeating: 0xAB, count: 18))
	static let audioFrames = Data((0..<5000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
	
	/// `fLaC`, the given blocks and fake audio frames, which the writer copies without looking at them
	static func flacFile(_ blocks: [Block]) -> Data {
		var data = Data("fLaC".utf8)
		for (index, block) in blocks.enumerated() {
			data.append((index == blocks.count - 1 ? 0x80 : 0) | block.type)
			let length = UInt32(block.body.count)
			data.append(contentsOf: [UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)])
			data.append(block.body)
		}
		data.append(audioFrames)
		return data
	}
	
	/// The metadata blocks and the audio frames after them
	static func parse(_ data: Data) throws -> (blocks: [Block], audio: Data) {
		let bytes = [UInt8](data)
		try #require(bytes.count >= 4 && Data(bytes[0..<4]) == Data("fLaC".utf8))
		var offset = 4
		var blocks: [Block] = []
		var isLast = false
		while !isLast {
			try #require(offset + 4 <= bytes.count)
			isLast = bytes[offset] & 0x80 != 0
			let length = bytes[(offset + 1)...(offset + 3)].reduce(0) { $0 << 8 | Int($1) }
			try #require(offset + 4 + length <= bytes.count)
			blocks.append(Block(type: bytes[offset] & 0x7F, body: Data(bytes[(offset + 4)..<(offset + 4 + length)])))
			offset += 4 + length
		}
		return (blocks, Data(bytes[offset...]))
	}
	
	/// The vendor string and comments of a Vorbis comment block
	static func vorbisComment(_ body: Data) throws -> (vendor: String, comments: [String]) {
		let bytes = [UInt8](body)
		var offset = 0
		func readLength() throws -> Int {
			try #require(offset + 4 <= bytes.count)
			defer { offset += 4 }
			return bytes[offset..<(offset + 4)].reversed().reduce(0) { $0 << 8 | Int($1) }
		}
		func readString() throws -> String {
			let length = try readLength()
			try #require(offset + length <= bytes.count)
			defer { offset += length }
			return try #require(String(data: Data(bytes[offset..<(offset + length)]), encoding: .utf8))
		}
		let vendor = try readString()
		let count = try readLength()
		let comments = try (0..<count).map { _ in try readString() }
		#expect(offset == bytes.count)
		return (vendor, comments)
	}
	
	func write(_ tags: AudioTags, toFileWith blocks: [Block], in directory: TemporaryDirectory) async throws -> Data {
		let url = directory.url.appendingPathComponent("track.flac")
		try Self.flacFile(blocks).write(to: url)
		try await FLACTagWriter.write(tags, to: url)
		return try Data(contentsOf: url)
	}
	
	@Test func writesVorbisComment() async throws {
		let directory = try TemporaryDirectory()
		let (blocks, audio) = try Self.parse(await write(tags, toFileWith: [Self.streamInfo, Self.seekTable], in: directory))
		
		#expect(blocks.map(\.type) == [0, 3, 4, 1])
		#expect(blocks[0] == Self.streamInfo)
		#expect(blocks[1] == Self.seekTable)
		#expect(blocks[3].body == Data(count: 8192))
		#expect(audio == Self.audioFrames)
		
		let comment = try Self.vorbisComment(blocks[2].body)
		#expect(comment.vendor == "TidalSwift")
		#expect(comment.comments == [
			"TITLE=Get Lucky (Radio Edit)",
			"ARTIST=Daft Punk, Pharrell Williams",
			"ALBUM=Random Access Memories",
			"ALBUMARTIST=Daft Punk",
			"TRACKNUMBER=8",
			"TRACKTOTAL=13",
			"DISCNUMBER=1",
			"DISCTOTAL=1",
			"DATE=2013-05-17",
			"COPYRIGHT=℗ 2013 Daft Life",
			"ISRC=USQX91300108",
			"ITUNESADVISORY=1",
		])
	}
	
	@Test func leavesOutMissingTags() async throws {
		var sparse = tags
		sparse.artist = nil
		sparse.albumArtist = ""
		sparse.trackTotal = nil
		sparse.discTotal = nil
		sparse.releaseDate = nil
		sparse.copyright = nil
		sparse.isrc = nil
		sparse.isExplicit = false
		sparse.isCompilation = true
		
		let directory = try TemporaryDirectory()
		let (blocks, _) = try Self.parse(await write(sparse, toFileWith: [Self.streamInfo], in: directory))
		let comment = try Self.vorbisComment(try #require(blocks.first { $0.type == 4 }).body)
		
		#expect(comment.comments == [
			"TITLE=Get Lucky (Radio Edit)",
			"ALBUM=Random Access Memories",
			"TRACKNUMBER=8",
			"DISCNUMBER=1",
			"COMPILATION=1",
		])
	}
	
	@Test func replacesExistingTagsPictureAndPadding() async throws {
		let oldBlocks = [
			Self.streamInfo,
			Block(type: 4, body: Data("old comment".utf8)),
			Block(type: 6, body: Data("old picture".utf8)),
			Self.seekTable,
			Block(type: 1, body: Data(count: 100)),
			Block(type: 2, body: Data("application".utf8)),
		]
		let directory = try TemporaryDirectory()
		let (blocks, audio) = try Self.parse(await write(tags, toFileWith: oldBlocks, in: directory))
		
		#expect(blocks.map(\.type) == [0, 3, 2, 4, 1])
		#expect(blocks[2].body == Data("application".utf8))
		#expect(audio == Self.audioFrames)
	}
	
	@Test func rewritingKeepsOneSetOfTags() async throws {
		let directory = try TemporaryDirectory()
		let url = directory.url.appendingPathComponent("track.flac")
		try Self.flacFile([Self.streamInfo]).write(to: url)
		try await FLACTagWriter.write(tags, to: url)
		let once = try Data(contentsOf: url)
		try await FLACTagWriter.write(tags, to: url)
		
		#expect(try Data(contentsOf: url) == once)
	}
	
	@Test func writesPicture() async throws {
		var withCover = tags
		let cover = try pngCover()
		withCover.cover = cover
		
		let directory = try TemporaryDirectory()
		let (blocks, _) = try Self.parse(await write(withCover, toFileWith: [Self.streamInfo], in: directory))
		#expect(blocks.map(\.type) == [0, 4, 6, 1])
		
		let picture = [UInt8](blocks[2].body)
		func uint32(at offset: Int) -> Int {
			picture[offset..<(offset + 4)].reduce(0) { $0 << 8 | Int($1) }
		}
		let mime = "image/png"
		#expect(uint32(at: 0) == 3)
		#expect(uint32(at: 4) == mime.utf8.count)
		#expect(Data(picture[8..<(8 + mime.utf8.count)]) == Data(mime.utf8))
		let fields = 8 + mime.utf8.count
		#expect(uint32(at: fields) == 0)
		#expect(uint32(at: fields + 4) == 2)
		#expect(uint32(at: fields + 8) == 3)
		#expect(uint32(at: fields + 16) == 0)
		#expect(uint32(at: fields + 20) == cover.count)
		#expect(Data(picture[(fields + 24)...]) == cover)
	}
	
	@Test func skipsUnreadableCover() async throws {
		var withCover = tags
		withCover.cover = Data("not an image".utf8)
		
		let directory = try TemporaryDirectory()
		let (blocks, _) = try Self.parse(await write(withCover, toFileWith: [Self.streamInfo], in: directory))
		#expect(blocks.map(\.type) == [0, 4, 1])
	}
	
	@Test(arguments: [
		Data("OggS".utf8) + Data(count: 100),
		Data("fLa".utf8),
		Data("fLaC".utf8) + Data([0x80, 0x00, 0x00, 0x22]) + Data(count: 10),
		Data("fLaC".utf8) + Data([0x00, 0x00, 0x00, 0x22]) + Data(count: 34),
	])
	func rejectsInvalidFile(_ data: Data) async throws {
		let directory = try TemporaryDirectory()
		let url = directory.url.appendingPathComponent("track.flac")
		try data.write(to: url)
		
		await #expect(throws: (any Error).self) {
			try await FLACTagWriter.write(tags, to: url)
		}
		#expect(try Data(contentsOf: url) == data)
	}
}

// MARK: - MP4

struct MP4TagWriterTests {
	/// One second of silent AAC in an M4A container
	static func silentM4A(at url: URL) throws {
		let settings: [String: Any] = [
			AVFormatIDKey: kAudioFormatMPEG4AAC,
			AVSampleRateKey: 44100,
			AVNumberOfChannelsKey: 2,
		]
		let file = try AVAudioFile(forWriting: url, settings: settings)
		let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 44100))
		buffer.frameLength = 44100
		try file.write(from: buffer)
	}
	
	static func metadata(of url: URL) async throws -> [AVMetadataIdentifier: AVMetadataItem] {
		let items = try await AVURLAsset(url: url).load(.metadata)
		return Dictionary(items.compactMap { item in item.identifier.map { ($0, item) } }) { first, _ in first }
	}
	
	@Test func writesITunesMetadata() async throws {
		var withCover = tags
		withCover.isCompilation = true
		withCover.cover = try pngCover()
		
		let directory = try TemporaryDirectory()
		let url = directory.url.appendingPathComponent("track.m4a")
		try Self.silentM4A(at: url)
		try await MP4TagWriter.write(withCover, to: url)
		let metadata = try await Self.metadata(of: url)
		
		func string(_ identifier: AVMetadataIdentifier) async throws -> String? {
			try await metadata[identifier]?.load(.stringValue)
		}
		#expect(try await string(.iTunesMetadataSongName) == "Get Lucky (Radio Edit)")
		#expect(try await string(.iTunesMetadataArtist) == "Daft Punk, Pharrell Williams")
		#expect(try await string(.iTunesMetadataAlbum) == "Random Access Memories")
		#expect(try await string(.iTunesMetadataAlbumArtist) == "Daft Punk")
		#expect(try await string(.iTunesMetadataReleaseDate) == "2013-05-17")
		#expect(try await string(.iTunesMetadataCopyright) == "℗ 2013 Daft Life")
		
		let trackNumber = try await metadata[.iTunesMetadataTrackNumber]?.load(.dataValue)
		#expect(trackNumber == Data([0, 0, 0, 8, 0, 13, 0, 0]))
		let discNumber = try await metadata[.iTunesMetadataDiscNumber]?.load(.dataValue)
		#expect(discNumber == Data([0, 0, 0, 1, 0, 1]))
		
		#expect(try await metadata[.iTunesMetadataDiscCompilation]?.load(.numberValue) == 1)
		#expect(try await metadata[.iTunesMetadataContentRating]?.load(.numberValue) == 1)
		#expect(try await metadata[.iTunesMetadataCoverArt]?.load(.dataValue) == withCover.cover)
		
		let duration = try await AVURLAsset(url: url).load(.duration)
		#expect(abs(duration.seconds - 1) < 0.1)
	}
	
	@Test func leavesOutMissingTags() async throws {
		var sparse = tags
		sparse.artist = nil
		sparse.albumArtist = ""
		sparse.copyright = nil
		sparse.isExplicit = false
		
		let directory = try TemporaryDirectory()
		let url = directory.url.appendingPathComponent("track.m4a")
		try Self.silentM4A(at: url)
		try await MP4TagWriter.write(sparse, to: url)
		let metadata = try await Self.metadata(of: url)
		
		#expect(metadata[.iTunesMetadataArtist] == nil)
		#expect(metadata[.iTunesMetadataAlbumArtist] == nil)
		#expect(metadata[.iTunesMetadataCopyright] == nil)
		#expect(metadata[.iTunesMetadataContentRating] == nil)
		#expect(metadata[.iTunesMetadataDiscCompilation] == nil)
		#expect(metadata[.iTunesMetadataCoverArt] == nil)
		#expect(metadata[.iTunesMetadataSongName] != nil)
	}
}

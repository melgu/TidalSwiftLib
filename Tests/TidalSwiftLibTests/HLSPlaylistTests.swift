//
//  HLSPlaylistTests.swift
//  TidalSwiftLibTests
//

import Foundation
import Testing
@testable import TidalSwiftLib

struct HLSPlaylistTests {
	let baseURL = URL(string: "http://im-fa.manifest.tidal.com/1/manifests/master.m3u8?token=abc")!
	
	// MARK: - Master
	
	@Test func masterParsesVariants() throws {
		let text = """
			#EXTM3U
			#EXT-X-STREAM-INF:BANDWIDTH=441999,RESOLUTION=320x180,CODECS="mp4a.40.2,avc1.42c00d"
			320x180/index.m3u8?token=abc
			#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="mp4a.40.2,avc1.640028"
			http://im-fa.manifest.tidal.com/1/1080/index.m3u8
			"""
		let master = try HLSPlaylist.Master(text, baseURL: baseURL)
		
		#expect(master.variants.count == 2)
		#expect(master.variants[0].url.absoluteString == "http://im-fa.manifest.tidal.com/1/manifests/320x180/index.m3u8?token=abc")
		#expect(master.variants[0].bandwidth == 441999)
		#expect(master.variants[0].height == 180)
		#expect(master.variants[1].url.absoluteString == "http://im-fa.manifest.tidal.com/1/1080/index.m3u8")
		#expect(master.variants[1].height == 1080)
	}
	
	@Test func masterPicksHighestResolutionThenBandwidth() throws {
		let text = """
			#EXTM3U
			#EXT-X-STREAM-INF:BANDWIDTH=9000000,RESOLUTION=1280x720
			720.m3u8
			#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080
			1080-low.m3u8
			#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080
			1080-high.m3u8
			#EXT-X-STREAM-INF:BANDWIDTH=8000000,RESOLUTION=640x360
			360.m3u8
			"""
		let master = try HLSPlaylist.Master(text, baseURL: baseURL)
		
		#expect(master.best.url.lastPathComponent == "1080-high.m3u8")
	}
	
	@Test func masterSkipsVariantsWithoutBandwidth() throws {
		let text = """
			#EXTM3U
			#EXT-X-STREAM-INF:RESOLUTION=1920x1080
			no-bandwidth.m3u8
			#EXT-X-STREAM-INF:BANDWIDTH=100
			audio-only.m3u8
			"""
		let master = try HLSPlaylist.Master(text, baseURL: baseURL)
		
		#expect(master.variants.map(\.url.lastPathComponent) == ["audio-only.m3u8"])
		#expect(master.best.height == 0)
	}
	
	@Test func masterHandlesCRLFAndIndentation() throws {
		let text = "#EXTM3U\r\n  #EXT-X-STREAM-INF:BANDWIDTH=100,RESOLUTION=640x360\r\n\r\n  360.m3u8  \r\n"
		let master = try HLSPlaylist.Master(text, baseURL: baseURL)
		
		#expect(master.variants.map(\.url.lastPathComponent) == ["360.m3u8"])
	}
	
	@Test func masterWithoutVariantsThrows() {
		#expect(throws: HLSPlaylist.ParseError.self) {
			try HLSPlaylist.Master("#EXTM3U\n", baseURL: baseURL)
		}
	}
	
	// MARK: - Media
	
	@Test func mediaParsesTransportStreamSegments() throws {
		let text = """
			#EXTM3U
			#EXT-X-VERSION:3
			#EXT-X-TARGETDURATION:6
			#EXT-X-PLAYLIST-TYPE:VOD
			#EXT-X-KEY:METHOD=NONE
			#EXTINF:6.000,
			segment0.ts?Policy=a&Signature=b
			#EXTINF:6.000,
			http://vmz-ad-cf.video.tidal.com/segment1.ts
			#EXT-X-ENDLIST
			"""
		let media = try HLSPlaylist.Media(text, baseURL: baseURL)
		
		#expect(media.initializationSegment == nil)
		#expect(media.segments.map(\.absoluteString) == [
			"http://im-fa.manifest.tidal.com/1/manifests/segment0.ts?Policy=a&Signature=b",
			"http://vmz-ad-cf.video.tidal.com/segment1.ts",
		])
		#expect(media.allSegments == media.segments)
	}
	
	@Test func mediaPutsInitializationSegmentFirst() throws {
		let text = """
			#EXTM3U
			#EXT-X-MAP:URI="init.mp4?a=1,b=2"
			#EXTINF:4.0,
			1.mp4
			#EXTINF:4.0,
			2.mp4
			#EXT-X-ENDLIST
			"""
		let media = try HLSPlaylist.Media(text, baseURL: baseURL)
		
		#expect(media.initializationSegment?.lastPathComponent == "init.mp4")
		#expect(media.initializationSegment?.query == "a=1,b=2")
		#expect(media.allSegments.map(\.lastPathComponent) == ["init.mp4", "1.mp4", "2.mp4"])
	}
	
	@Test(arguments: [
		"#EXT-X-KEY:METHOD=AES-128,URI=\"https://example.com/key\"",
		"#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"skd://abc\"",
		"#EXT-X-BYTERANGE:1000@0",
		"#EXT-X-MAP:URI=\"init.mp4\",BYTERANGE=\"1000@0\"",
		"#EXT-X-MAP:BYTERANGE=\"1000@0\"",
	])
	func mediaRejectsUnsupportedTag(_ tag: String) {
		let text = """
			#EXTM3U
			\(tag)
			#EXTINF:4.0,
			1.mp4
			"""
		#expect(throws: HLSPlaylist.ParseError.self) {
			try HLSPlaylist.Media(text, baseURL: baseURL)
		}
	}
	
	@Test func mediaWithoutSegmentsThrows() {
		#expect(throws: HLSPlaylist.ParseError.self) {
			try HLSPlaylist.Media("#EXTM3U\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXT-X-ENDLIST\n", baseURL: baseURL)
		}
	}
}

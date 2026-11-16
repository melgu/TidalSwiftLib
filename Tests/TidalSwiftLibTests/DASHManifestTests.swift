//
//  DASHManifestTests.swift
//  TidalSwiftLibTests
//

import Foundation
import Testing
@testable import TidalSwiftLib

struct DASHManifestTests {
	/// Shaped like the manifests `playbackinfopostpaywall` returns, see docs/tidal-streaming-api.md
	static func manifest(
		codecs: String = "flac",
		representation: String? = nil,
		startNumber: String = " startNumber=\"1\"",
		timeline: String = "<S d=\"188416\" r=\"2\"/><S d=\"45056\"/>",
		extra: String = ""
	) -> Data {
		let representation = representation ?? """
			<Representation id="FLAC_HIRES,48000,24" codecs="\(codecs)" bandwidth="2304000" audioSamplingRate="48000">
				<SegmentTemplate timescale="48000" initialization="https://sp-ad-fa.audio.tidal.com/a/0.mp4?token=t&amp;info=i" media="https://sp-ad-fa.audio.tidal.com/a/$Number$.mp4?token=t&amp;info=i"\(startNumber)>
					<SegmentTimeline>\(timeline)</SegmentTimeline>
				</SegmentTemplate>
			</Representation>
			"""
		return Data("""
			<?xml version='1.0' encoding='UTF-8'?>
			<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" profiles="urn:mpeg:dash:profile:isoff-main:2011" type="static" mediaPresentationDuration="PT12.7S" minBufferTime="PT3.993S">
				<Period id="0">
					<AdaptationSet id="0" contentType="audio" mimeType="audio/mp4" segmentAlignment="true">
						\(extra)
						\(representation)
					</AdaptationSet>
				</Period>
			</MPD>
			""".utf8)
	}
	
	@Test func parsesFLACManifest() throws {
		let dash = try DASHManifest(Self.manifest())
		
		#expect(dash.codecs == "flac")
		#expect(dash.isFLAC)
		#expect(dash.bandwidth == 2304000)
		#expect(dash.sampleRate == 48000)
		#expect(dash.initializationSegment.absoluteString == "https://sp-ad-fa.audio.tidal.com/a/0.mp4?token=t&info=i")
		#expect(dash.segments.map(\.url.absoluteString) == (1...4).map { "https://sp-ad-fa.audio.tidal.com/a/\($0).mp4?token=t&info=i" })
		#expect(dash.segments.map(\.duration) == [188416, 188416, 188416, 45056].map { Double($0) / 48000 })
		#expect(abs(dash.duration - Double(3 * 188416 + 45056) / 48000) < 1e-9)
	}
	
	@Test func isFLACIgnoresCase() throws {
		#expect(try DASHManifest(Self.manifest(codecs: "fLaC")).isFLAC)
		#expect(try !DASHManifest(Self.manifest(codecs: "mp4a.40.2")).isFLAC)
	}
	
	@Test func numbersSegmentsFromStartNumber() throws {
		let fromFive = try DASHManifest(Self.manifest(startNumber: " startNumber=\"5\""))
		#expect(fromFive.segments.map(\.url.lastPathComponent) == ["5.mp4", "6.mp4", "7.mp4", "8.mp4"])
		
		let withoutStartNumber = try DASHManifest(Self.manifest(startNumber: ""))
		#expect(withoutStartNumber.segments.first?.url.lastPathComponent == "1.mp4")
	}
	
	@Test func rejectsProtectedManifest() {
		let data = Self.manifest(extra: "<ContentProtection schemeIdUri=\"urn:mpeg:dash:mp4protection:2011\" value=\"cenc\"/>")
		#expect(throws: DASHManifest.ParseError.self) {
			try DASHManifest(data)
		}
	}
	
	@Test func rejectsSeveralRepresentations() {
		let second = "<Representation id=\"LOW\" codecs=\"mp4a.40.2\" bandwidth=\"96000\"/>"
		#expect(throws: DASHManifest.ParseError.self) {
			try DASHManifest(Self.manifest(extra: second))
		}
	}
	
	@Test(arguments: [
		"",
		"<S d=\"188416\" r=\"-1\"/>",
		"<S r=\"2\"/>",
	])
	func rejectsTimeline(_ timeline: String) {
		#expect(throws: DASHManifest.ParseError.self) {
			try DASHManifest(Self.manifest(timeline: timeline))
		}
	}
	
	@Test func rejectsInvalidXML() {
		#expect(throws: DASHManifest.ParseError.self) {
			try DASHManifest(Data("<MPD><Period>".utf8))
		}
	}
	
	@Test func hlsPlaylistListsAllSegments() throws {
		let dash = try DASHManifest(Self.manifest())
		let playlist = dash.hlsPlaylist
		let lines = playlist.split(separator: "\n").map(String.init)
		
		#expect(lines.first == "#EXTM3U")
		#expect(lines.last == "#EXT-X-ENDLIST")
		#expect(lines.contains("#EXT-X-TARGETDURATION:4"))
		#expect(lines.contains("#EXT-X-MAP:URI=\"https://sp-ad-fa.audio.tidal.com/a/0.mp4?token=t&info=i\""))
		#expect(lines.filter { $0.hasPrefix("#EXTINF:") } == [
			"#EXTINF:3.925333,",
			"#EXTINF:3.925333,",
			"#EXTINF:3.925333,",
			"#EXTINF:0.938667,",
		])
	}
	
	@Test func hlsPlaylistRoundTrips() throws {
		let dash = try DASHManifest(Self.manifest())
		let media = try HLSPlaylist.Media(dash.hlsPlaylist, baseURL: URL(string: "tidal-dash://track")!)
		
		#expect(media.initializationSegment == dash.initializationSegment)
		#expect(media.segments == dash.segments.map(\.url))
	}
}

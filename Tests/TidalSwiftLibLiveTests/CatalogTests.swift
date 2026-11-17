//
//  CatalogTests.swift
//  TidalSwiftLibLiveTests
//

import Foundation
import Testing
@testable import TidalSwiftLib

extension LiveTests {
	@Suite struct Tracks {
		@Test func track() async throws {
			let session = try await LiveSession.session()
			let track = try #require(await session.track(trackId: TestItems.trackId))
			
			#expect(track.id == TestItems.trackId)
			#expect(track.title.contains("Get Lucky"))
			#expect(track.album.id == TestItems.albumId)
			#expect(track.duration > 0)
		}
		
		@Test func credits() async throws {
			let session = try await LiveSession.session()
			let credits = try #require(await session.trackCredits(trackId: TestItems.trackId))
			
			#expect(!credits.isEmpty)
			#expect(credits.allSatisfy { !$0.contributors.isEmpty })
		}
		
		@Test func lyrics() async throws {
			let session = try await LiveSession.session()
			let lyrics = try #require(await session.lyrics(trackId: TestItems.lyricsTrackId))
			
			#expect(lyrics.trackId == TestItems.lyricsTrackId)
			#expect(!lyrics.lyrics.isEmpty)
		}
		
		@Test func radio() async throws {
			let session = try await LiveSession.session()
			let tracks = try #require(await session.trackRadio(trackId: TestItems.trackId, limit: 10))
			
			#expect(!tracks.isEmpty)
			#expect(tracks.count <= 10)
		}
	}
	
	@Suite struct Albums {
		@Test func album() async throws {
			let session = try await LiveSession.session()
			let album = try #require(await session.album(albumId: TestItems.albumId))
			
			#expect(album.id == TestItems.albumId)
			#expect(album.title == "Random Access Memories")
			#expect(album.numberOfTracks == TestItems.albumTrackCount)
			#expect(album.releaseDate != nil)
		}
		
		@Test func tracks() async throws {
			let session = try await LiveSession.session()
			let tracks = try #require(await session.albumTracks(albumId: TestItems.albumId))
			
			#expect(tracks.count == TestItems.albumTrackCount)
			#expect(tracks.allSatisfy { $0.album.id == TestItems.albumId })
			#expect(tracks.map(\.trackNumber) == Array(1...TestItems.albumTrackCount))
			#expect(tracks.contains { $0.id == TestItems.trackId })
		}
		
		@Test func credits() async throws {
			let session = try await LiveSession.session()
			let credits = try #require(await session.albumCredits(albumId: TestItems.albumId))
			
			#expect(!credits.isEmpty)
		}
	}
	
	@Suite struct Artists {
		@Test func artist() async throws {
			let session = try await LiveSession.session()
			let artist = try #require(await session.artist(artistId: TestItems.artistId))
			
			#expect(artist.id == TestItems.artistId)
			#expect(artist.name == "Daft Punk")
		}
		
		@Test func albums() async throws {
			let session = try await LiveSession.session()
			let albums = try #require(await session.artistAlbums(artistId: TestItems.artistId))
			
			#expect(albums.contains { $0.id == TestItems.albumId })
		}
		
		@Test func singlesAndAppearances() async throws {
			let session = try await LiveSession.session()
			let singles = try #require(await session.artistAlbums(artistId: TestItems.artistId, filter: .epsAndSingles))
			let appearances = try #require(await session.artistAlbums(artistId: TestItems.artistId, filter: .appearances))
			
			#expect(!singles.isEmpty)
			#expect(!singles.contains { $0.id == TestItems.albumId })
			#expect(!appearances.contains { $0.id == TestItems.albumId })
		}
		
		@Test func topTracks() async throws {
			let session = try await LiveSession.session()
			let tracks = try #require(await session.artistTopTracks(artistId: TestItems.artistId, limit: 10))
			
			#expect(!tracks.isEmpty)
			#expect(tracks.count <= 10)
		}
		
		@Test func videos() async throws {
			let session = try await LiveSession.session()
			let videos = try #require(await session.artistVideos(artistId: TestItems.artistId))
			
			#expect(videos.contains { $0.id == TestItems.videoId })
		}
		
		@Test func similar() async throws {
			let session = try await LiveSession.session()
			let artists = try #require(await session.artistSimilar(artistId: TestItems.similarArtistId))
			
			#expect(!artists.isEmpty)
			#expect(!artists.contains { $0.id == TestItems.similarArtistId })
		}
		
		@Test func radio() async throws {
			let session = try await LiveSession.session()
			let tracks = try #require(await session.artistRadio(artistId: TestItems.artistId))
			#expect(!tracks.isEmpty)
			
			let page = try #require(await session.artistRadio(artistId: TestItems.artistId, limit: 10, offset: 10))
			#expect(page.count == 10)
		}
	}
	
	@Suite struct Playlists {
		@Test func playlist() async throws {
			let session = try await LiveSession.session()
			let playlist = try #require(await session.playlist(playlistId: TestItems.playlistId))
			
			#expect(playlist.uuid == TestItems.playlistId)
			#expect(playlist.title.contains("Daft Punk"))
			#expect(playlist.numberOfTracks > 0)
		}
		
		@Test func tracks() async throws {
			let session = try await LiveSession.session()
			let playlist = try #require(await session.playlist(playlistId: TestItems.playlistId))
			let tracks = try #require(await session.playlistTracks(playlistId: TestItems.playlistId))
			
			#expect(tracks.count == playlist.numberOfTracks)
		}
	}
	
	@Suite struct Videos {
		@Test func video() async throws {
			let session = try await LiveSession.session()
			let video = try #require(await session.video(videoId: TestItems.videoId))
			
			#expect(video.id == TestItems.videoId)
			#expect(video.title == "Lose Yourself to Dance")
			#expect(video.duration > 0)
		}
	}
	
	@Suite struct Search {
		@Test func search() async throws {
			let session = try await LiveSession.session()
			let results = try #require(await session.search(for: "Daft Punk Get Lucky", limit: 10))
			
			#expect(results.artists.contains { $0.id == TestItems.artistId })
			#expect(!results.tracks.isEmpty)
			#expect(results.tracks.count <= 10)
			#expect(!results.albums.isEmpty)
		}
		
		@Test func paging() async throws {
			let session = try await LiveSession.session()
			let first = try #require(await session.search(for: "Daft Punk", limit: 5))
			let second = try #require(await session.search(for: "Daft Punk", limit: 5, offset: 5))
			
			#expect(first.tracks.count == 5)
			#expect(Set(first.tracks.map(\.id)).isDisjoint(with: second.tracks.map(\.id)))
		}
	}
}

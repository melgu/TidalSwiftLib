//
//  AccountTests.swift
//  TidalSwiftLibLiveTests
//

import Foundation
import Testing
@testable import TidalSwiftLib

extension LiveTests {
	@Suite struct Login {
		@Test func refreshesAccessToken() async throws {
			let session = try await LiveSession.session()
			let oldToken = session.config.accessToken
			try await session.refreshAccessToken()
			
			#expect(!session.config.accessToken.isEmpty)
			#expect(session.config.accessToken != oldToken)
			#expect(try #require(session.config.tokenExpirationDate) > Date())
		}
		
		@Test func refreshesSecondLogin() async throws {
			let session = try await LiveSession.session()
			guard let secondConfig = session.secondConfig else {
				try Test.cancel("The test login has no second login")
			}
			try await session.refreshAccessToken(of: secondConfig)
			
			#expect(try #require(secondConfig.tokenExpirationDate) > Date())
		}
		
		@Test func user() async throws {
			let session = try await LiveSession.session()
			let userId = try #require(session.userId)
			let user = try #require(await session.user(userId: userId))
			
			#expect(user.id == userId)
			#expect(user.countryCode == session.countryCode)
		}
		
		@Test func subscription() async throws {
			let session = try await LiveSession.session()
			let subscription = try #require(await session.subscriptionInfo())
			
			#expect(subscription.validUntil > Date())
		}
	}
	
	@Suite struct Favorites {
		@Test func favorites() async throws {
			let session = try await LiveSession.session()
			let favorites = try #require(session.favorites)
			
			#expect(await favorites.artists() != nil)
			#expect(await favorites.albums() != nil)
			#expect(await favorites.tracks() != nil)
			#expect(await favorites.videos() != nil)
			#expect(await favorites.playlists() != nil)
		}
		
		@Test func sortedFavorites() async throws {
			let session = try await LiveSession.session()
			let favorites = try #require(session.favorites)
			let albums = try #require(await favorites.albums(order: .dateAdded, orderDirection: .descending))
			
			#expect(albums.map(\.created) == albums.map(\.created).sorted(by: >))
		}
		
		@Test func userPlaylists() async throws {
			let session = try await LiveSession.session()
			let userId = try #require(session.userId)
			let favorites = try #require(session.favorites)
			let playlists = try #require(await favorites.userPlaylists())
			
			#expect(playlists.allSatisfy { $0.creator.id == userId })
			#expect(await session.userPlaylists(userId: userId) != nil)
		}
	}
	
	@Suite struct Discovery {
		@Test func mixes() async throws {
			let session = try await LiveSession.session()
			let mixes = try #require(await session.mixes())
			let mix = try #require(mixes.first)
			let tracks = try #require(await session.mixPlaylistTracks(mixId: mix.id))
			
			#expect(!tracks.isEmpty)
		}
		
		@Test func featured() async throws {
			let session = try await LiveSession.session()
			
			#expect(await session.featured() != nil)
		}
		
		@Test func moods() async throws {
			let session = try await LiveSession.session()
			let moods = try #require(await session.moods())
			let mood = try #require(moods.first { $0.hasPlaylists })
			let playlists = try #require(await session.moodPlaylists(moodPath: mood.path))
			
			#expect(!playlists.isEmpty)
		}
		
		@Test func genres() async throws {
			let session = try await LiveSession.session()
			let genres = try #require(await session.genres())
			#expect(!genres.isEmpty)
			
			// Not the first genre, as "Local" claims tracks and albums, but Tidal answers 404 for them
			let genre = try #require(genres.first { $0.path == "Pop" })
			#expect(genre.hasTracks && genre.hasAlbums && genre.hasPlaylists)
			#expect(try #require(await session.genreTracks(genrePath: genre.path)).isEmpty == false)
			#expect(try #require(await session.genreAlbums(genreName: genre.path)).isEmpty == false)
			#expect(try #require(await session.genrePlaylists(genreName: genre.path)).isEmpty == false)
		}
	}
}

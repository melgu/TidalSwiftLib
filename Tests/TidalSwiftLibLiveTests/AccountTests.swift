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
		
		/// Restoring a backup right away changes nothing, also with override
		@Test func backupAndPlan() async throws {
			let session = try await LiveSession.session()
			let favorites = try #require(session.favorites)
			let backup = try await session.backup()
			#expect(backup.userId == session.userId)
			#expect(backup.favorites.tracks.count == (await favorites.tracks())?.count)
			#expect(backup.favorites.playlists.count + backup.playlists.count == (await favorites.playlists())?.count)
			#expect(backup.favorites.tracks.allSatisfy { $0.dateAdded != nil })
			#expect(backup.favorites.mixes?.count == (await favorites.mixes())?.count)
			#expect(backup.folders?.count == (try await session.playlistFolders.items()).filter { $0.itemType == .folder }.count)
			// The file keeps whole seconds
			#expect(try AccountBackup(data: backup.data()).data() == backup.data())
			
			let plan = try await session.restorePlan(for: backup, options: .init(override: true, deletePlaylists: true))
			#expect(plan.isEmpty)
			#expect(plan.ownPlaylists.count == backup.playlists.count)
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
			let items = try #require(await session.featured())
			
			#expect(!items.isEmpty)
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

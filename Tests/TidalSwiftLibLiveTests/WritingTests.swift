//
//  WritingTests.swift
//  TidalSwiftLibLiveTests
//

import Foundation
import Testing
@testable import TidalSwiftLib

/// Tests that change the account. Each one restores what it changed, even when it fails.
/// Disabled until they are needed: remove the `.disabled` trait to run them.
extension LiveTests {
	@Suite(.disabled("Changes the account"))
	struct Writing {
		/// Creates a playlist for the test and deletes it afterwards
		func withTemporaryPlaylist(_ body: (Session, Playlist) async throws -> Void) async throws {
			let session = try await LiveSession.session()
			let playlist = try #require(await session.playlistEditing.create(
				title: "TidalSwiftLib Test \(Date().formatted(.iso8601))",
				description: "Created by a test. Delete it if it is left over."
			))
			do {
				try await body(session, playlist)
			} catch {
				_ = await session.playlistEditing.delete(playlistId: playlist.uuid)
				throw error
			}
			#expect(await session.playlistEditing.delete(playlistId: playlist.uuid))
			#expect(await session.playlist(playlistId: playlist.uuid) == nil)
		}
		
		@Test func createAndEditPlaylist() async throws {
			try await withTemporaryPlaylist { session, playlist in
				#expect(playlist.numberOfTracks == 0)
				#expect(playlist.creator.id == session.userId)
				
				let title = "TidalSwiftLib Test C++ & Rock + Roll"
				#expect(await session.playlistEditing.edit(playlistId: playlist.uuid, title: title, description: "a+b=c"))
				let edited = try #require(await session.playlist(playlistId: playlist.uuid))
				#expect(edited.title == title)
				#expect(edited.description == "a+b=c")
			}
		}
		
		@Test func addMoveAndRemoveTracks() async throws {
			try await withTemporaryPlaylist { session, playlist in
				let albumTracks = try #require(await session.albumTracks(albumId: TestItems.albumId))
				let trackIds = albumTracks.prefix(3).map(\.id)
				#expect(await session.playlistEditing.addTracks(trackIds, to: playlist.uuid, duplicate: false))
				#expect(await session.playlistTracks(playlistId: playlist.uuid)?.map(\.id) == trackIds)
				
				#expect(await session.playlistEditing.addTrack(trackIds[0], to: playlist.uuid, duplicate: true))
				#expect(await session.playlistTracks(playlistId: playlist.uuid)?.map(\.id) == trackIds + [trackIds[0]])
				
				#expect(await session.playlistEditing.moveItem(fromIndex: 0, toIndex: 2, in: playlist.uuid))
				let moved = await session.playlistTracks(playlistId: playlist.uuid)?.map(\.id)
				#expect(moved == [trackIds[1], trackIds[2], trackIds[0], trackIds[0]])
				
				#expect(await session.playlistEditing.removeItem(atIndex: 3, from: playlist.uuid))
				#expect(await session.playlistEditing.removeItem(atIndex: 0, from: playlist.uuid))
				let remaining = await session.playlistTracks(playlistId: playlist.uuid)?.map(\.id)
				#expect(remaining == [trackIds[2], trackIds[0]])
			}
		}
		
		/// Videos take positions like tracks. The track list has their "Audio from video" track in their place.
		@Test func addAndRemoveVideo() async throws {
			try await withTemporaryPlaylist { session, playlist in
				let trackIds = [TestItems.trackId, TestItems.lyricsTrackId]
				#expect(await session.playlistEditing.addTrack(trackIds[0], to: playlist.uuid, duplicate: false))
				#expect(await session.playlistEditing.addTrack(TestItems.videoId, to: playlist.uuid, duplicate: false))
				#expect(await session.playlistEditing.addTrack(trackIds[1], to: playlist.uuid, duplicate: false))
				
				let items = try #require(await session.playlistItems(playlistId: playlist.uuid))
				#expect(items.map(\.track?.id) == [trackIds[0], nil, trackIds[1]])
				#expect(items[1].video?.id == TestItems.videoId)
				let tracks = try #require(await session.playlistTracks(playlistId: playlist.uuid))
				#expect(tracks.count == 3)
				
				#expect(await session.playlistEditing.removeItem(atIndex: 1, from: playlist.uuid))
				let remaining = try #require(await session.playlistItems(playlistId: playlist.uuid))
				#expect(remaining.map(\.track?.id) == trackIds)
			}
		}
		
		/// Tidal answers 404 and adds none of the IDs
		@Test func addUnknownTrack() async throws {
			try await withTemporaryPlaylist { session, playlist in
				#expect(await session.playlistEditing.addTracks([TestItems.trackId, 999_999_999], to: playlist.uuid, duplicate: false) == false)
				#expect(await session.playlistItems(playlistId: playlist.uuid)?.isEmpty == true)
			}
		}
		
		/// Tidal rejects these with a status code, which the functions report
		@Test func rejectedEdits() async throws {
			try await withTemporaryPlaylist { session, playlist in
				#expect(await session.playlistEditing.addTrack(TestItems.trackId, to: playlist.uuid, duplicate: false))
				#expect(await session.playlistEditing.removeItem(atIndex: 5, from: playlist.uuid) == false)
				#expect(await session.playlistEditing.moveItem(fromIndex: 5, toIndex: 0, in: playlist.uuid) == false)
				#expect(await session.playlistItems(playlistId: playlist.uuid)?.map(\.mediaId) == [TestItems.trackId])
			}
			let session = try await LiveSession.session()
			let missingPlaylist = "00000000-0000-4000-8000-000000000000"
			#expect(await session.playlistEditing.edit(playlistId: missingPlaylist, title: "Title", description: "") == false)
			#expect(await session.playlistEditing.delete(playlistId: missingPlaylist) == false)
			
			let favorites = try #require(session.favorites)
			let added = await favorites.addTrack(trackId: 999_999_999)
			if added {
				await favorites.removeTrack(trackId: 999_999_999)
			}
			#expect(added == false)
		}
		
		/// Toggles a favorite twice, so it ends as it was. An existing favorite loses its original date.
		@Test func toggleFavoriteTrack() async throws {
			let session = try await LiveSession.session()
			let favorites = try #require(session.favorites)
			let wasFavorite = try #require(await favorites.doFavoritesContainTrack(trackId: TestItems.trackId))
			
			if wasFavorite {
				#expect(await favorites.removeTrack(trackId: TestItems.trackId))
				#expect(await favorites.doFavoritesContainTrack(trackId: TestItems.trackId) == false)
				#expect(await favorites.addTrack(trackId: TestItems.trackId))
			} else {
				#expect(await favorites.addTrack(trackId: TestItems.trackId))
				#expect(await favorites.doFavoritesContainTrack(trackId: TestItems.trackId) == true)
				#expect(await favorites.removeTrack(trackId: TestItems.trackId))
			}
			#expect(await favorites.doFavoritesContainTrack(trackId: TestItems.trackId) == wasFavorite)
		}
	}
}

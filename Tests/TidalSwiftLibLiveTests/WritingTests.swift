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
				#expect(await session.playlistEditing.removeItems(atIndices: [0, 5], from: playlist.uuid) == false)
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
		
		@Test func removeSeveralItems() async throws {
			try await withTemporaryPlaylist { session, playlist in
				let albumTracks = try #require(await session.albumTracks(albumId: TestItems.albumId))
				let trackIds = albumTracks.prefix(4).map(\.id)
				#expect(await session.playlistEditing.addTracks(trackIds, to: playlist.uuid, duplicate: false))
				
				#expect(await session.playlistEditing.removeItems(atIndices: [3, 0, 2], from: playlist.uuid))
				#expect(await session.playlistItems(playlistId: playlist.uuid)?.map(\.mediaId) == [trackIds[1]])
			}
		}
		
		/// Imports a playlist as a new one, appends it to itself without duplicates and replaces it with another file
		@Test func importPlaylist() async throws {
			let session = try await LiveSession.session()
			let source = try #require(await session.exportPlaylist(playlistId: TestItems.playlistId))
			let imported = try await session.playlistEditing.importPlaylist(source, mode: .new)
			do {
				try await checkImports(into: imported, from: source, session: session)
			} catch {
				_ = await session.playlistEditing.delete(playlistId: imported.playlist.uuid)
				throw error
			}
			#expect(await session.playlistEditing.delete(playlistId: imported.playlist.uuid))
		}
		
		private func checkImports(into imported: PlaylistImportResult, from source: PlaylistExport, session: Session) async throws {
			#expect(imported.playlist.title == source.title)
			#expect(imported.added.map(\.id) == source.items.map(\.id))
			#expect(imported.missing.isEmpty)
			#expect(await session.playlistItems(playlistId: imported.playlist.uuid)?.map(\.mediaId) == source.items.map(\.id))
			
			let appended = try await session.playlistEditing.importPlaylist(source, mode: .append(playlistId: imported.playlist.uuid, duplicates: false))
			#expect(appended.added.isEmpty)
			#expect(appended.skipped.count == source.items.count)
			
			// A track whose ID Tidal no longer knows, and one it can't find again
			let track = try #require(await session.track(trackId: TestItems.trackId))
			let replacement = try PlaylistExport(data: source.data().replacing(
				Data(#""items" : ["#.utf8),
				with: Data("""
					"items" : [
						{ "type" : "track", "id" : 999999998, "title" : "\(track.title)", "artists" : [], "isrc" : "\(track.isrc ?? "")", "duration" : \(track.duration) },
						{ "type" : "video", "id" : 999999999, "title" : "Gone", "artists" : [], "duration" : 100 },
					""".utf8)
			))
			let replaced = try await session.playlistEditing.importPlaylist(replacement, mode: .replace(playlistId: imported.playlist.uuid))
			#expect(replaced.replaced.map(\.original.id) == [999_999_998])
			#expect(replaced.replaced.first?.track.isrc == track.isrc)
			#expect(replaced.missing.map(\.id) == [999_999_999])
			let items = try #require(await session.playlistItems(playlistId: imported.playlist.uuid))
			#expect(items.count == source.items.count + 1)
			#expect(items.first?.mediaId == replaced.replaced.first?.track.id)
		}
		
		/// Restores a fresh backup with an extra favorite and playlist, after a playlist changed.
		/// With override, it would also remove favorites added during the test, so it runs only for a moment.
		@Test func restoreBackup() async throws {
			try await withTemporaryPlaylist { session, playlist in
				let favorites = try #require(session.favorites)
				let albumTracks = try #require(await session.albumTracks(albumId: TestItems.albumId)).map(\.id)
				let favoriteTracks = Set(try #require(await favorites.tracks()).map(\.id))
				let extraFavorite = try #require(albumTracks.first { !favoriteTracks.contains($0) })
				#expect(await session.playlistEditing.addTrack(albumTracks[0], to: playlist.uuid, duplicate: false))
				
				let backup = try await session.backup()
				let extraTrack = try #require(await session.track(trackId: extraFavorite))
				let title = "TidalSwiftLib Test Restore \(Date().formatted(.iso8601))"
				let source = try #require(await session.exportPlaylist(playlistId: playlist.uuid))
				let extraPlaylist = try PlaylistExport(data: source.data()
					.replacing(Data(playlist.uuid.utf8), with: Data("00000000-0000-4000-8000-000000000001".utf8))
					.replacing(Data(#""title" : "\#(playlist.title)""#.utf8), with: Data(#""title" : "\#(title)""#.utf8))
					// Public, which the restore makes it again
					.replacing(Data(#""public" : false"#.utf8), with: Data(#""public" : true"#.utf8)))
				#expect(extraPlaylist.isPublic)
				// An old date, which the restore keeps
				let extraDate = Date(timeIntervalSince1970: 1_500_000_000)
				let folderName = "TidalSwiftLib Test Folder \(Date().formatted(.iso8601))"
				let folder = AccountBackup.FolderEntry(id: "00000000-0000-4000-8000-000000000002", name: folderName, parent: nil, dateAdded: nil, playlists: [
					AccountBackup.FolderPlaylist(uuid: extraPlaylist.uuid, dateAdded: nil),
				])
				let modified = AccountBackup(
					userId: backup.userId,
					favorites: AccountBackup.FavoriteLists(
						tracks: backup.favorites.tracks + [PlaylistExport.Item(.track(extraTrack)).dated(extraDate)],
						videos: backup.favorites.videos,
						albums: backup.favorites.albums,
						artists: backup.favorites.artists,
						playlists: backup.favorites.playlists,
						mixes: backup.favorites.mixes
					),
					playlists: backup.playlists + [extraPlaylist],
					folders: (backup.folders ?? []) + [folder]
				)
				#expect(await session.playlistEditing.addTrack(albumTracks[1], to: playlist.uuid, duplicate: false))
				
				let merge = try await session.restorePlan(for: modified)
				#expect(merge.tracks.add.map(\.id) == [extraFavorite])
				#expect(merge.ownPlaylists.filter { !$0.isUnchanged }.map(\.title) == [title])
				
				let plan = try await session.restorePlan(for: modified, options: .init(override: true))
				#expect(plan.tracks.remove.isEmpty)
				#expect(plan.ownPlaylists.filter { !$0.isUnchanged }.map(\.title) == [playlist.title, title])
				#expect(plan.folders.create.map(\.name) == [folderName])
				#expect(plan.folders.moves.map(\.title) == [title])
				let result = try await session.restore(plan)
				let created = try #require(result.ownPlaylists.compactMap(\.imported).first { $0.playlist.title == title }?.playlist)
				#expect(created.publicPlaylist)
				#expect(await session.playlist(playlistId: playlist.uuid)?.publicPlaylist == false)
				// The v2 listing has the visibility right away, v1 sometimes only a moment later
				#expect(await session.playlistFolders.all()?.contains { if case let .playlist(listed, _, _) = $0 { listed.uuid == created.uuid && listed.publicPlaylist } else { false } } == true)
				let folderId = try await session.playlistFolders.items().first { $0.itemType == .folder && $0.name == folderName }?.id
				do {
					#expect(result.tracks.added.map(\.id) == [extraFavorite])
					#expect(await favorites.tracks()?.first { $0.item.id == extraFavorite }?.created == extraDate)
					#expect(await session.playlistItems(playlistId: playlist.uuid)?.map(\.mediaId) == [albumTracks[0]])
					#expect(await session.playlistItems(playlistId: created.uuid)?.map(\.mediaId) == [albumTracks[0]])
					#expect(result.folders.created == [folderName])
					let placed = try await session.playlistFolders.items().first { $0.id == created.uuid }
					#expect(placed?.parent?.id == folderId)
					
					// Found again by its title and name
					let again = try await session.restorePlan(for: modified)
					#expect(again.isEmpty)
				} catch {
					_ = await session.playlistEditing.delete(playlistId: created.uuid)
					await favorites.removeTrack(trackId: extraFavorite)
					if let folderId {
						try? await session.playlistFolders.deleteFolders([folderId])
					}
					throw error
				}
				#expect(await session.playlistEditing.delete(playlistId: created.uuid))
				#expect(await favorites.removeTrack(trackId: extraFavorite))
				// Empty now, as its playlist is deleted
				let emptyFolder = try #require(folderId)
				try await session.playlistFolders.deleteFolders([emptyFolder])
			}
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
		
		/// Makes the temporary playlist public for a moment
		@Test func playlistVisibility() async throws {
			try await withTemporaryPlaylist { session, playlist in
				#expect(!playlist.publicPlaylist)
				#expect(await session.playlistEditing.setPublic(true, playlistId: playlist.uuid))
				#expect(await session.playlist(playlistId: playlist.uuid)?.publicPlaylist == true)
				#expect(await session.playlistEditing.setPublic(false, playlistId: playlist.uuid))
				#expect(await session.playlist(playlistId: playlist.uuid)?.publicPlaylist == false)
			}
		}
		
		/// Creates two nested folders with the temporary playlist in the inner one, and deletes them again
		@Test func playlistFolders() async throws {
			try await withTemporaryPlaylist { session, playlist in
				let folders = session.playlistFolders
				let suffix = Date().formatted(.iso8601)
				let outer = try #require(await folders.create(name: "TidalSwiftLib Test Outer \(suffix)"))
				var created = [outer.id]
				do {
					let inner = try #require(await folders.create(name: "TidalSwiftLib Test Inner \(suffix)", in: outer.id))
					created.insert(inner.id, at: 0)
					#expect(await folders.move(playlists: [playlist.uuid], to: inner.id))
					
					let contents = try #require(await folders.contents(of: inner.id))
					#expect(contents.count == 1)
					if case let .playlist(listed, folderId, _) = contents.first {
						#expect(listed.uuid == playlist.uuid)
						#expect(listed.title == playlist.title)
						#expect(folderId == inner.id)
					} else {
						Issue.record("Expected the playlist, got \(contents)")
					}
					#expect(await folders.contents(of: outer.id)?.contains { if case let .folder(folder) = $0 { folder.id == inner.id } else { false } } == true)
					#expect(await folders.all()?.contains { $0.folderId == outer.id } == true)
					
					// Tidal would accept this and lose both folders in a cycle
					#expect(await folders.move(folderId: outer.id, to: inner.id) == false)
					#expect(await folders.rename(folderId: outer.id, to: "TidalSwiftLib Test Renamed \(suffix)"))
					
					// Moves the inner folder, with the playlist in it, to the root
					#expect(await folders.delete(folderId: outer.id))
					created.removeLast()
					let all = try #require(await folders.all())
					#expect(!all.contains { if case let .folder(folder) = $0 { folder.id == outer.id } else { false } })
					#expect(all.contains { if case let .folder(folder) = $0 { folder.id == inner.id && folder.parentId == nil } else { false } })
					#expect(await folders.contents(of: inner.id)?.count == 1)
					#expect(await folders.delete(folderId: inner.id))
					created.removeAll()
				} catch {
					for id in created {
						_ = await folders.delete(folderId: id)
					}
					throw error
				}
				// Left over if an expectation failed
				for id in created {
					_ = await folders.delete(folderId: id)
				}
			}
		}
	}
}

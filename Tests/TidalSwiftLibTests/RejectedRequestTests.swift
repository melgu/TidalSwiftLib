//
//  RejectedRequestTests.swift
//  TidalSwiftLibTests
//

import Foundation
import Testing
@testable import TidalSwiftLib

/// Answers every request without the network and records them
nonisolated final class FakeTransport: @unchecked Sendable {
	struct Answer {
		let statusCode: Int
		let body: String
	}
	
	private let lock = NSLock()
	private var answers: [String: Answer] = [:]
	private var handler: (@Sendable (URLRequest) -> Answer?)?
	private var _requests: [URLRequest] = []
	
	/// Unanswered GETs get an empty page, POSTs and DELETEs an empty success
	init() {}
	
	var requests: [URLRequest] {
		lock.withLock { _requests }
	}
	
	/// - Parameter method: GET, POST or DELETE
	func answer(_ method: String, _ statusCode: Int, body: String = "") {
		lock.withLock { answers[method] = Answer(statusCode: statusCode, body: body) }
	}
	
	/// Answers the requests it returns an answer for, before the answers by method
	func answer(_ handler: @escaping @Sendable (URLRequest) -> Answer?) {
		lock.withLock { self.handler = handler }
	}
	
	var transport: HTTPTransport {
		{ [self] request in
			let method = request.httpMethod ?? "GET"
			let answer = lock.withLock {
				_requests.append(request)
				return handler?(request) ?? answers[method] ?? Answer(statusCode: 200, body: method == "GET" ? #"{"limit":0,"offset":0,"totalNumberOfItems":0,"items":[]}"# : "")
			}
			let response = HTTPURLResponse(url: request.url!, statusCode: answer.statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
			return (Data(answer.body.utf8), response)
		}
	}
}

@MainActor
struct RejectedRequestTests {
	nonisolated static let notFound = #"{"status":404,"subStatus":2001,"userMessage":"Track not found"}"#
	
	let fake = FakeTransport()
	let session: Session
	
	init() {
		// Without a refresh token, the session doesn't try to refresh the access token
		session = Session(config: Config(accessToken: "token", refreshToken: "", clientID: "client"), keychainService: "de.melgu.TidalSwiftLib.unit-tests")
		session.countryCode = "DE"
		session.userId = 1
		session.favorites = Favorites(session: session, userId: 1)
		session.transport = fake.transport
	}
	
	@Test func readsTidalsErrorBody() {
		let error = RequestError(statusCode: 404, body: Data(Self.notFound.utf8))
		#expect(error == RequestError(statusCode: 404, subStatus: 2001, userMessage: "Track not found"))
		#expect(error.description == "Tidal answered 404: Track not found")
		#expect(RequestError(statusCode: 500, body: Data("<html>".utf8)).userMessage == nil)
	}
	
	@Test func throwsForRejectedRequest() async {
		fake.answer("POST", 404, body: Self.notFound)
		await #expect(throws: RequestError(statusCode: 404, subStatus: 2001, userMessage: "Track not found")) {
			try await session.post(url: URL(string: "https://example.com/items")!, parameters: [:])
		}
		fake.answer("POST", 201)
		await #expect(throws: Never.self) {
			try await session.post(url: URL(string: "https://example.com/items")!, parameters: [:])
		}
	}
	
	@Test(arguments: [200, 201, 204])
	func playlistEditsSucceed(statusCode: Int) async {
		fake.answer("POST", statusCode)
		fake.answer("DELETE", statusCode)
		let editing = session.playlistEditing!
		#expect(await editing.addTracks([1, 2], to: "playlist", duplicate: false))
		#expect(await editing.removeItem(atIndex: 0, from: "playlist"))
		#expect(await editing.removeItems(atIndices: [0, 1], from: "playlist"))
		#expect(await editing.moveItem(fromIndex: 0, toIndex: 1, in: "playlist"))
		#expect(await editing.edit(playlistId: "playlist", title: "Title", description: ""))
		#expect(await editing.delete(playlistId: "playlist"))
	}
	
	@Test(arguments: [400, 404, 412, 500])
	func playlistEditsFail(statusCode: Int) async {
		fake.answer("POST", statusCode)
		fake.answer("DELETE", statusCode)
		let editing = session.playlistEditing!
		#expect(await editing.addTracks([1, 2], to: "playlist", duplicate: false) == false)
		#expect(await editing.removeItem(atIndex: 0, from: "playlist") == false)
		#expect(await editing.removeItems(atIndices: [0, 1], from: "playlist") == false)
		#expect(await editing.moveItem(fromIndex: 0, toIndex: 1, in: "playlist") == false)
		#expect(await editing.edit(playlistId: "playlist", title: "Title", description: "") == false)
		#expect(await editing.delete(playlistId: "playlist") == false)
	}
	
	/// Import tells unknown IDs, which it looks for, from other failures, which stop it
	@Test func addTellsUnknownIdsFromFailures() async {
		let editing = session.playlistEditing!
		fake.answer("POST", 404, body: Self.notFound)
		#expect(await editing.add([1], to: "playlist", duplicate: true) == .notFound)
		fake.answer("POST", 500)
		#expect(await editing.add([1], to: "playlist", duplicate: true) == .failed)
		fake.answer("POST", 200)
		#expect(await editing.add([1], to: "playlist", duplicate: true) == .added)
	}
	
	@Test func removeItemsSendsPositionsFromTheBack() async {
		let editing = session.playlistEditing!
		#expect(await editing.removeItems(atIndices: Array(0..<600) + [5], from: "playlist"))
		let deletes = fake.requests.filter { $0.httpMethod == "DELETE" }.map { $0.url!.path() }
		#expect(deletes.count == 2)
		#expect(deletes.first?.hasPrefix("/v1/playlists/playlist/items/100,101,") == true)
		#expect(deletes.last?.hasSuffix("/items/" + (0..<100).map(String.init).joined(separator: ",")) == true)
	}
	
	@Test func favoritesFail() async {
		fake.answer("POST", 404, body: Self.notFound)
		fake.answer("DELETE", 404, body: Self.notFound)
		let favorites = session.favorites!
		#expect(await favorites.addTrack(trackId: 1) == false)
		#expect(await favorites.addAlbum(albumId: 1) == false)
		#expect(await favorites.addArtist(artistId: 1) == false)
		#expect(await favorites.addVideo(videoId: 1) == false)
		#expect(await favorites.addPlaylist(playlistId: "playlist") == false)
		#expect(await favorites.removeTrack(trackId: 1) == false)
		#expect(await favorites.removeAlbum(albumId: 1) == false)
		#expect(await favorites.removeArtist(artistId: 1) == false)
		#expect(await favorites.removeVideo(videoId: 1) == false)
		#expect(await favorites.removePlaylist(playlistId: "playlist") == false)
	}
	
	@Test func favoritesSucceed() async {
		let favorites = session.favorites!
		#expect(await favorites.addTrack(trackId: 1))
		#expect(await favorites.removeTrack(trackId: 1))
	}
	
	/// Reading functions already returned nil, as Tidal's error body doesn't decode
	@Test func readingReturnsNil() async {
		fake.answer("GET", 404, body: Self.notFound)
		#expect(await session.track(trackId: 1) == nil)
		#expect(await session.playlistItems(playlistId: "playlist") == nil)
	}
}

//
//  LiveSession.swift
//  TidalSwiftLibLiveTests
//

import Foundation
import Testing
@testable import TidalSwiftLib

/// The logged-in session all live tests share.
///
/// The tests keep their own login in the Keychain, so refreshing tokens or a bug in the library can't touch the login
/// of the app or the command line tool. The first run copies the command line tool's login, which then lives on separately.
/// To copy it again, e.g. after logging in to the tool with a second login kind, delete the Keychain items of ``keychainService``.
enum LiveSession {
	static let keychainService = "de.melgu.TidalSwiftLib.tests"
	/// The command line tool's login
	static let sourceKeychainService = "de.melgu.TidalSwift.cli"
	
	private static var shared: Task<Session, Error>?
	
	static func session() async throws -> Session {
		if let shared {
			return try await shared.value
		}
		let task = Task { try await makeSession() }
		shared = task
		return try await task.value
	}
	
	private static func makeSession() async throws -> Session {
		try copyLoginIfMissing()
		let session = Session(config: nil, keychainService: keychainService)
		guard session.loadSession() else {
			throw LiveSessionError("The login in the Keychain under \(keychainService) is incomplete. Delete it to copy the command line tool's login again.")
		}
		try await session.refreshAccessTokenIfNeeded()
		return session
	}
	
	private static func copyLoginIfMissing() throws {
		guard try Keychain.load(service: keychainService, account: credentialsAccount) == nil else {
			return
		}
		guard let credentials = try Keychain.load(service: sourceKeychainService, account: credentialsAccount) else {
			throw LiveSessionError("No login to test with. Log in with `tidal login` first.")
		}
		try Keychain.save(credentials, service: keychainService, account: credentialsAccount)
		if let secondCredentials = try Keychain.load(service: sourceKeychainService, account: secondCredentialsAccount) {
			try Keychain.save(secondCredentials, service: keychainService, account: secondCredentialsAccount)
		}
	}
}

struct LiveSessionError: Error, CustomStringConvertible {
	let description: String
	
	init(_ description: String) {
		self.description = description
	}
}

/// Catalog items the tests read. Their content is checked only loosely, as Tidal may change it.
enum TestItems {
	static let artistId = 8847					// Daft Punk
	static let albumId = 20115556				// Random Access Memories
	static let albumTrackCount = 13
	static let trackId = 20115564				// Get Lucky
	/// Stereo and Dolby Atmos
	static let stereoAndDolbyAtmosTrackId = 188600501	// Matt Johnson – Blinding Lights
	/// Only Dolby Atmos
	static let dolbyAtmosTrackId = 125155092	// The Weeknd – Blinding Lights
	/// Get Lucky has no lyrics on Tidal
	static let lyricsTrackId = 20115557			// Give Life Back to Music
	/// Tidal has no similar artists for Daft Punk
	static let similarArtistId = 27343			// David Guetta
	static let videoId = 24114562				// Lose Yourself to Dance
	static let playlistId = "abd35446-6a67-4f2b-9f92-0636742c63cb"	// Daft Punk Essentials
	/// More than one page of playlist items
	static let largePlaylistId = "49af4fb6-30c9-489b-a2f2-ac858bba9a95"	// '80s: Dolby Atmos
}

/// Runs the live tests one after the other, to go easy on the API
@Suite(.serialized, .timeLimit(.minutes(1)))
struct LiveTests {}

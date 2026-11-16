//
//  PKCELoginTests.swift
//  TidalSwiftLibTests
//

import CryptoKit
import Foundation
import Testing
@testable import TidalSwiftLib

struct PKCELoginTests {
	/// A session with an empty login, so nothing is read from or written to the Keychain
	let session = Session(config: Config(accessToken: "", refreshToken: "", clientID: ""), keychainService: "TidalSwiftLibTests")
	
	private func queryItems(of url: URL) -> [String: String] {
		let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
		return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
	}
	
	private func base64URL(_ data: Data) -> String {
		data.base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
	}
	
	@Test func codeVerifierMeetsRFC7636() {
		let authorization = session.startPKCEAuthorization()
		let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
		
		// 32 random bytes in base64url without padding
		#expect(authorization.codeVerifier.count == 43)
		#expect(authorization.codeVerifier.unicodeScalars.allSatisfy(allowed.contains))
	}
	
	@Test func loginUrlCarriesS256Challenge() {
		let authorization = session.startPKCEAuthorization()
		let query = queryItems(of: authorization.loginUrl)
		let expectedChallenge = base64URL(Data(SHA256.hash(data: Data(authorization.codeVerifier.utf8))))
		
		#expect(query["code_challenge"] == expectedChallenge)
		#expect(query["code_challenge_method"] == "S256")
		#expect(query["response_type"] == "code")
		#expect(query["redirect_uri"] == PKCEAuthorization.redirectUrl.absoluteString)
		#expect(query["client_unique_key"] == authorization.clientUniqueKey)
		#expect(query["client_id"]?.isEmpty == false)
	}
	
	@Test func authorizationsDiffer() {
		let first = session.startPKCEAuthorization()
		let second = session.startPKCEAuthorization()
		
		#expect(first.codeVerifier != second.codeVerifier)
		#expect(first.clientUniqueKey != second.clientUniqueKey)
	}
	
	@Test func recognizesRedirect() {
		#expect(PKCEAuthorization.isRedirect(URL(string: PKCEAuthorization.redirectUrl.absoluteString + "?code=abc&state=na")!))
		#expect(!PKCEAuthorization.isRedirect(URL(string: "https://tidal.com/browse")!))
	}
	
	@Test(arguments: [
		"https://tidal.com/android/login/auth",
		"https://tidal.com/android/login/auth?state=na",
		"https://tidal.com/android/login/auth?code=&state=na",
	])
	func finishWithoutCodeThrows(_ redirect: String) async {
		let authorization = session.startPKCEAuthorization()
		await #expect(throws: PKCEAuthorizationError.missingCode) {
			try await session.finishPKCEAuthorization(authorization, redirectUrl: URL(string: redirect)!)
		}
	}
}

//
//  NetworkTests.swift
//  TidalSwiftLibTests
//

import Foundation
import Testing
@testable import TidalSwiftLib

struct NetworkTests {
	/// Decodes a query the way a server does, `+` included
	private func decodedQuery(_ query: String) -> [String: String] {
		var components = URLComponents()
		components.percentEncodedQuery = query.replacingOccurrences(of: "+", with: "%20")
		return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
	}
	
	@Test func encodesParameters() {
		let parameters = [
			"countryCode": "DE",
			"query": "Daft Punk & Friends",
			"title": "Ä/ö?ü=#%",
			"empty": "",
		]
		let query = Network.encodeParameters(parameters)
		
		#expect(!query.contains(" "))
		#expect(decodedQuery(query) == parameters)
	}
	
	@Test func encodesNoParameters() {
		#expect(Network.encodeParameters([:]) == "")
	}
	
	@Test func encodesPlusSign() {
		withKnownIssue("URLComponents leaves + unencoded, which servers decode as a space") {
			let parameters = ["query": "C++", "title": "Rock + Roll"]
			#expect(decodedQuery(Network.encodeParameters(parameters)) == parameters)
		}
	}
	
	#if DEBUG
	@Test func redactsFormSecrets() {
		let body = "client_id=abc&code=secret1&grant_type=authorization_code&code_verifier=secret2&refresh_token=secret3&scope=r_usr"
		let redacted = Network.redactingSecrets(body)
		
		#expect(redacted == "client_id=abc&code=<redacted>&grant_type=authorization_code&code_verifier=<redacted>&refresh_token=<redacted>&scope=r_usr")
	}
	
	@Test func redactsJSONSecrets() {
		let json = """
			{"access_token": "secret1","refresh_token":"secret2", "user": {"userId": 1}, "deviceCode":"secret3", "userCode" : "secret4", "token_type":"Bearer"}
			"""
		let redacted = Network.redactingSecrets(json)
		
		for secret in ["secret1", "secret2", "secret3", "secret4"] {
			#expect(!redacted.contains(secret))
		}
		#expect(redacted.contains("\"access_token\":\"<redacted>\""))
		#expect(redacted.contains("\"token_type\":\"Bearer\""))
		#expect(redacted.contains("\"userId\": 1"))
	}
	
	@Test func keepsKeysThatOnlyEndInSecretNames() {
		let body = "client_unique_key=abc&countryCode=DE&zipcode=12345&my_access_token_hint=1"
		
		#expect(Network.redactingSecrets(body) == body)
	}
	#endif
}

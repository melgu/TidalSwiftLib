//
//  PKCELogin.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 12.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import CryptoKit
import Foundation
import OSLog

private let logger = Logger(category: "PKCELogin")

/// A started login with the authorization code flow and PKCE, as the Android app uses it.
/// According to tidalapi, Tidal serves Hi-Res to this client, which the device flow can't log in to.
public struct PKCEAuthorization: Sendable {
	/// Opened in a browser. After the login, Tidal redirects to ``redirectUrl``, which carries the code.
	public let loginUrl: URL
	let codeVerifier: String
	let clientUniqueKey: String
	
	/// Where Tidal sends the browser after the login. It shows an error page, whose URL has to be passed to ``Session/finishPKCEAuthorization(_:redirectUrl:)``.
	public static let redirectUrl = URL(string: AuthInformation.PKCERedirectUri)!
	
	/// Whether a URL is the redirect after the login
	public static func isRedirect(_ url: URL) -> Bool {
		url.absoluteString.hasPrefix(AuthInformation.PKCERedirectUri)
	}
}

public enum PKCEAuthorizationError: LocalizedError {
	/// The URL doesn't contain a code, e.g. because the wrong page was copied
	case missingCode
	
	public var errorDescription: String? {
		switch self {
		case .missingCode:
			"The URL doesn't contain a login code"
		}
	}
}

extension Session {
	/// Creates the login URL and the secrets needed to finish the login
	public func startPKCEAuthorization() -> PKCEAuthorization {
		var randomBytes = [UInt8](repeating: 0, count: 32)
		for index in randomBytes.indices {
			randomBytes[index] = .random(in: .min ... .max)
		}
		let codeVerifier = Data(randomBytes).base64URLEncodedString()
		let codeChallenge = Data(SHA256.hash(data: Data(codeVerifier.utf8))).base64URLEncodedString()
		let clientUniqueKey = String(UInt64.random(in: .min ... .max), radix: 16)
		
		var components = URLComponents(string: AuthInformation.PKCEAuthorizeLocation)!
		components.queryItems = [
			URLQueryItem(name: "response_type", value: "code"),
			URLQueryItem(name: "redirect_uri", value: AuthInformation.PKCERedirectUri),
			URLQueryItem(name: "client_id", value: AuthInformation.PKCEClientID),
			URLQueryItem(name: "lang", value: "EN"),
			URLQueryItem(name: "appMode", value: "android"),
			URLQueryItem(name: "client_unique_key", value: clientUniqueKey),
			URLQueryItem(name: "code_challenge", value: codeChallenge),
			URLQueryItem(name: "code_challenge_method", value: "S256"),
			URLQueryItem(name: "restrict_signup", value: "true")
		]
		
		return PKCEAuthorization(loginUrl: components.url!, codeVerifier: codeVerifier, clientUniqueKey: clientUniqueKey)
	}
	
	/// Exchanges the code in the redirect URL for tokens and logs in
	public func finishPKCEAuthorization(_ authorization: PKCEAuthorization, redirectUrl: URL) async throws {
		guard let code = URLComponents(url: redirectUrl, resolvingAgainstBaseURL: false)?
			.queryItems?.first(where: { $0.name == "code" })?.value,
			  !code.isEmpty
		else {
			throw PKCEAuthorizationError.missingCode
		}
		
		let url = URL(string: "\(AuthInformation.AuthLocation)/token")!
		let parameters: [String: String] = [
			"code": code,
			"client_id": AuthInformation.PKCEClientID,
			"grant_type": "authorization_code",
			"redirect_uri": AuthInformation.PKCERedirectUri,
			"scope": AuthInformation.PKCEScope,
			"code_verifier": authorization.codeVerifier,
			"client_unique_key": authorization.clientUniqueKey
		]
		
		let response: Response
		do {
			response = try await Network.post(url: url, parameters: parameters, accessToken: nil, xTidalToken: nil)
		} catch {
			throw SessionError.network(underlying: error)
		}
		
		if let successResponse = try? JSONDecoder.custom.decode(TokenSuccessResponse.self, from: response.data) {
			try await completeLogin(successResponse, clientID: AuthInformation.PKCEClientID)
		} else if let errorResponse = try? JSONDecoder.custom.decode(TokenErrorResponse.self, from: response.data) {
			logger.error("PKCE token request failed: \(errorResponse.errorDescription, privacy: .public)")
			throw SessionError.invalidCredentials(description: errorResponse.errorDescription)
		} else {
			throw SessionError.unexpectedResponse
		}
	}
}

private extension Data {
	/// Base64 with the URL-safe alphabet and without padding, as PKCE requires
	func base64URLEncodedString() -> String {
		base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
	}
}

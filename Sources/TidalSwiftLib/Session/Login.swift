//
//  Login.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 01.08.20.
//  Copyright © 2020 Melvin Gundlach. All rights reserved.
//

import Foundation
import OSLog

private let logger = Logger(category: "Login")

extension Session {
	/// Margin before actual expiration to trigger a refresh (5 minutes)
	private static let tokenRefreshMargin: TimeInterval = 5 * 60
	
	public func login(refreshToken: String, clientID: String) async throws {
		config.refreshToken = refreshToken
		config.clientID = clientID
		try await refreshAccessToken()
		try await populateVariablesForAccessToken()
	}
	
	func setAccessToken(_ accessToken: String, refreshToken: String?, expiresIn: Int, in login: Config) {
		var token = accessToken
		if !token.hasPrefix("Bearer ") {
			token = "Bearer " + token
		}
		
		login.accessToken = token
		if let refreshToken {
			login.refreshToken = refreshToken
		}
		
		login.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(expiresIn))
	}
	
	/// Stores a new login. Without a login, or replacing one of the same kind, it becomes the main one.
	/// Otherwise it becomes the second login, which has to belong to the same account.
	func completeLogin(_ token: TokenSuccessResponse, clientID: String) async throws {
		let newLogin = Config(accessToken: "", refreshToken: "", clientID: clientID)
		setAccessToken(token.accessToken, refreshToken: token.refreshToken, expiresIn: token.expiresIn, in: newLogin)
		
		if config.isLoggedIn && config.kind != newLogin.kind {
			guard token.user.userId == userId else {
				throw SessionError.differentAccount
			}
			secondConfig = newLogin
			saveConfig()
		} else {
			config = newLogin
			try await populateVariablesForAccessToken()
			// A second login of another account can't stay
			if let secondConfig, savedSecondCredentials?.userId != userId {
				logger.notice("Removing the second login (\(String(describing: secondConfig.kind), privacy: .public)), which belongs to another account")
				removeSecondLogin()
			}
		}
	}
	
	public func populateVariablesForAccessToken() async throws {
		let url = URL(string: "https://login.tidal.com/oauth2/me")!
		let response: Response
		do {
			response = try await Network.get(url: url, parameters: sessionParameters, accessToken: config.accessToken, xTidalToken: AuthInformation.apiToken)
		} catch {
			throw SessionError.network(underlying: error)
		}
		if response.statusCode == 401 || response.statusCode == 403 {
			throw SessionError.invalidCredentials(description: nil)
		}
		guard let user = try? JSONDecoder.custom.decode(LoginUser.self, from: response.data) else {
			throw SessionError.unexpectedResponse
		}
		self.countryCode = user.countryCode
		self.userId = user.userId
		self.favorites = Favorites(session: self, userId: user.userId)
	}
	
	public enum AuthorizationState {
		case waiting
		case pending(loginUrl: URL, expiration: Date)
		case success
		case failure(Error)
	}
	
	private enum AuthorizationError: LocalizedError {
		case deviceAuthorizationFailed
		case pollingFailed
		case expiredToken
		case unknown
		
		var errorDescription: String? {
			switch self {
			case .deviceAuthorizationFailed:
				"Couldn't start the login"
			case .pollingFailed:
				"Couldn't check whether the login was approved"
			case .expiredToken:
				"The link expired before the login was approved"
			case .unknown:
				"Unknown error"
			}
		}
	}
	
	/// Runs the device authorization flow. Cancelling the consumer of the stream stops the polling.
	///
	/// When logged in with PKCE, this adds the device login as the second one.
	public func startAuthorization() -> AsyncStream<AuthorizationState> {
		AsyncStream { continuation in
			let task = Task {
				continuation.yield(.waiting)
				continuation.yield(await authorize(onPending: { continuation.yield($0) }))
				continuation.finish()
			}
			continuation.onTermination = { _ in
				task.cancel()
			}
		}
	}
	
	private func authorize(onPending: (AuthorizationState) -> Void) async -> AuthorizationState {
		let url = URL(string: "\(AuthInformation.AuthLocation)/device_authorization")!
		let parameters: [String: String] = ["client_id": AuthInformation.OAuthClientID,
											"scope": AuthInformation.scope]
		
		let response: DeviceAuthorizationResponse
		do {
			response = try await Network.post(url: url, parameters: parameters, accessToken: nil, xTidalToken: nil)
		} catch {
			return .failure(AuthorizationError.deviceAuthorizationFailed)
		}
		
		let expiration = Date().addingTimeInterval(TimeInterval(response.expiresIn))
		let loginUrlString = "https://\(response.verificationUriComplete.absoluteString)"
		let loginUrl = URL(string: loginUrlString)!
		onPending(.pending(loginUrl: loginUrl, expiration: expiration))
		
		return await pollAuthorization(deviceCode: response.deviceCode)
	}
	
	private func pollAuthorization(deviceCode: UUID) async -> AuthorizationState {
		let url = URL(string: "\(AuthInformation.AuthLocation)/token")!
		let parameters: [String: String] = [
			"client_id": AuthInformation.OAuthClientID,
			"client_secret": AuthInformation.OAuthClientSecret,
			"device_code": deviceCode.uuidString.lowercased(),
			"grant_type": "urn:ietf:params:oauth:grant-type:device_code",
			"scope": AuthInformation.scope
		]
		
		while true {
			do {
				try await Task.sleep(for: .seconds(2))
			} catch {
				return .failure(error)
			}
			
			let response: Response
			do {
				response = try await Network.post(url: url, parameters: parameters, accessToken: nil, xTidalToken: nil)
			} catch {
				return .failure(AuthorizationError.deviceAuthorizationFailed)
			}
			
			if let successResponse = try? JSONDecoder.custom.decode(TokenSuccessResponse.self, from: response.data) {
				do {
					try await completeLogin(successResponse, clientID: AuthInformation.OAuthClientID)
					return .success
				} catch {
					return .failure(error)
				}
			} else if let errorResponse = try? JSONDecoder.custom.decode(TokenErrorResponse.self, from: response.data) {
				switch errorResponse.error {
				case "authorization_pending":
					logger.debug("Auth pending")
				case "expired_token":
					logger.debug("Expired token")
					return .failure(AuthorizationError.expiredToken)
				default:
					logger.error("Polling failed")
					return .failure(AuthorizationError.pollingFailed)
				}
			} else {
				return .failure(AuthorizationError.pollingFailed)
			}
		}
	}
	
	/// Refreshes the access token of the main login. Concurrent calls share a single refresh
	/// request instead of each hitting the auth server.
	public func refreshAccessToken() async throws {
		try await refreshAccessToken(of: config)
	}
	
	func refreshAccessToken(of login: Config) async throws {
		let key = ObjectIdentifier(login)
		if let activeTokenRefresh = activeTokenRefreshes[key] {
			return try await activeTokenRefresh.value
		}
		let task = Task {
			defer { activeTokenRefreshes[key] = nil }
			try await performAccessTokenRefresh(of: login)
		}
		activeTokenRefreshes[key] = task
		return try await task.value
	}
	
	private func performAccessTokenRefresh(of login: Config) async throws {
		logger.debug("refreshAccessToken")
		guard login.isLoggedIn else {
			throw SessionError.notLoggedIn
		}
		let url = URL(string: "\(AuthInformation.AuthLocation)/token")!
		var parameters: [String: String] = [
			"client_id": login.clientID,
			"refresh_token": login.refreshToken,
			"grant_type": "refresh_token",
			"scope": AuthInformation.scope
		]
		// The built-in clients are confidential: Tidal rejects their refresh requests without the secret
		if login.clientID == AuthInformation.OAuthClientID {
			parameters["client_secret"] = AuthInformation.OAuthClientSecret
		} else if login.clientID == AuthInformation.PKCEClientID {
			parameters["client_secret"] = AuthInformation.PKCEClientSecret
			parameters["scope"] = AuthInformation.PKCEScope
		}
		
		let response: Response
		do {
			response = try await Network.post(url: url, parameters: parameters, accessToken: nil, xTidalToken: nil)
		} catch {
			throw SessionError.network(underlying: error)
		}
		// Logging out cancels the refresh, which mustn't bring the credentials back if the response arrived anyway
		try Task.checkCancellation()
		
		if let successResponse = try? JSONDecoder.custom.decode(TokenSuccessResponse.self, from: response.data) {
			setAccessToken(successResponse.accessToken, refreshToken: successResponse.refreshToken, expiresIn: successResponse.expiresIn, in: login)
			saveConfig()
			logger.debug("Access token refreshed. New expiration: \(login.tokenExpirationDate?.description ?? "unknown")")
		} else if let errorResponse = try? JSONDecoder.custom.decode(TokenErrorResponse.self, from: response.data) {
			throw SessionError.invalidCredentials(description: errorResponse.errorDescription)
		} else {
			throw SessionError.unexpectedResponse
		}
	}
	
	/// Refreshes the main login's access token if it is expired or about to expire.
	public func refreshAccessTokenIfNeeded() async throws {
		try await refreshAccessTokenIfNeeded(of: config)
	}
	
	func refreshAccessTokenIfNeeded(of login: Config) async throws {
		guard login.isLoggedIn else { return }
		guard let expirationDate = login.tokenExpirationDate else {
			// No expiration date recorded — refresh to be safe
			try await refreshAccessToken(of: login)
			return
		}
		if Date() >= expirationDate.addingTimeInterval(-Session.tokenRefreshMargin) {
			try await refreshAccessToken(of: login)
		}
	}
}

extension Session {
	/// Logs out of both logins
	public func logout() {
		for task in activeTokenRefreshes.values {
			task.cancel()
		}
		activeTokenRefreshes = [:]
		deletePersistentInformation()
		config = Config(accessToken: "", refreshToken: "", clientID: "")
		secondConfig = nil
	}
	
	/// Removes the second login, keeping the main one
	public func removeSecondLogin() {
		if let secondConfig {
			activeTokenRefreshes.removeValue(forKey: ObjectIdentifier(secondConfig))?.cancel()
		}
		secondConfig = nil
		deleteSecondCredentials()
	}
}

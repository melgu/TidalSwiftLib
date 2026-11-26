//
//  Requests.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 07.07.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation

// Authenticated requests. These refresh the access token beforehand when it is
// expired (or about to expire) and retry once if the server rejects it anyway.
// They throw a RequestError when Tidal rejects the request, so a function that
// ignores the response can't take a rejected change for a successful one.
extension Session {
	func get(url: URL, parameters: [String: String]) async throws -> Response {
		try await authenticatedRequest(method: .get, url: url, parameters: parameters)
	}
	
	/// - Parameter login: The login to use instead of the main one
	func get<Result: Decodable>(url: URL, parameters: [String: String], login: Config? = nil, decoder: JSONDecoder = .custom) async throws -> Result {
		let response = try await authenticatedRequest(method: .get, url: url, parameters: parameters, login: login)
		return try decoder.decode(Result.self, from: response.data)
	}
	
	func post(url: URL, parameters: [String: String], etag: Int? = nil) async throws -> Response {
		try await authenticatedRequest(method: .post, url: url, parameters: parameters, etag: etag)
	}
	
	func post<Result: Decodable>(url: URL, parameters: [String: String], etag: Int? = nil, decoder: JSONDecoder = .custom) async throws -> Result {
		let response = try await authenticatedRequest(method: .post, url: url, parameters: parameters, etag: etag)
		return try decoder.decode(Result.self, from: response.data)
	}
	
	func delete(url: URL, parameters: [String: String], etag: Int? = nil) async throws -> Response {
		try await authenticatedRequest(method: .delete, url: url, parameters: parameters, etag: etag)
	}
	
	/// With the parameters in the URL, as the v2 API takes them
	func put<Result: Decodable>(url: URL, parameters: [String: String], decoder: JSONDecoder = .v2) async throws -> Result {
		let response = try await authenticatedRequest(method: .put, url: url, parameters: parameters)
		return try decoder.decode(Result.self, from: response.data)
	}
	
	/// For changes that answer without a body
	func put(url: URL, parameters: [String: String]) async throws {
		_ = try await authenticatedRequest(method: .put, url: url, parameters: parameters)
	}
	
	/// Sends a JSON:API document to `openapi.tidal.com`
	func send<Document: Encodable, Result: Decodable>(_ method: Network.HttpMethod, url: URL, parameters: [String: String] = [:], document: Document, decoder: JSONDecoder = .v2) async throws -> Result {
		let response = try await authenticatedRequest(method: method, url: url, parameters: parameters, jsonBody: try JSONEncoder.v2.encode(document))
		return try decoder.decode(Result.self, from: response.data)
	}
	
	private func authenticatedRequest(method: Network.HttpMethod, url: URL, parameters: [String: String], etag: Int? = nil, jsonBody: Data? = nil, login: Config? = nil) async throws -> Response {
		let login = login ?? config
		// A failed proactive refresh isn't fatal here: the request itself
		// surfaces the definitive error (network failure or 401 below)
		try? await refreshAccessTokenIfNeeded(of: login)
		var response = try await Network.request(method: method, url: url, parameters: parameters, etag: etag, jsonBody: jsonBody, accessToken: login.accessToken, xTidalToken: AuthInformation.apiToken, transport: transport)
		if response.statusCode == 401 {
			try await refreshAccessToken(of: login)
			response = try await Network.request(method: method, url: url, parameters: parameters, etag: etag, jsonBody: jsonBody, accessToken: login.accessToken, xTidalToken: AuthInformation.apiToken, transport: transport)
		}
		guard response.isSuccess else {
			throw RequestError(statusCode: response.statusCode ?? 0, body: response.data)
		}
		return response
	}
}

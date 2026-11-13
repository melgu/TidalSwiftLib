//
//  Session.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 01.08.20.
//  Copyright © 2020 Melvin Gundlach. All rights reserved.
//

import Foundation

public class Session {
	/// The main login, which all requests use apart from streams the second login is better at
	public var config: Config
	/// A login of the other ``LoginKind`` for the same account, so both Hi-Res and Dolby Atmos are available
	var secondConfig: Config?
	/// Service name of the Keychain item holding the login
	let keychainService: String
	/// What the Keychain holds, to skip unchanged writes
	var savedCredentials: Credentials?
	var savedSecondCredentials: Credentials?
	
	var countryCode: String?
	public var userId: Int?
	
	var sessionParameters: [String: String] {
		if countryCode == nil {
			return [:]
		} else {
			return ["countryCode": countryCode!,
					"limit": "999"]
		}
		
	}
	
	public var favorites: Favorites?
	public var helpers: Helpers!
	public var playlistEditing: PlaylistEditing!
	/// Running refreshes per login, keyed by its `Config`
	var activeTokenRefreshes: [ObjectIdentifier: Task<Void, Error>] = [:]
	
	public init(config: Config?, keychainService: String = Bundle.main.bundleIdentifier ?? "TidalSwift") {
		self.keychainService = keychainService
		if let config = config {
			self.config = config
		} else {
			if let loaded = Config.load(keychainService: keychainService) {
				self.config = loaded.config
				savedCredentials = loaded.savedCredentials
				countryCode = loaded.savedCredentials?.countryCode
				userId = loaded.savedCredentials?.userId
				if let second = Config.loadSecond(keychainService: keychainService), second.credentials.userId == userId {
					secondConfig = second.config
					savedSecondCredentials = second.credentials
				}
			} else {
				self.config = Config(
					accessToken: "",
					refreshToken: "",
					clientID: ""
				)
			}
		}
		helpers = Helpers(session: self)
		playlistEditing = PlaylistEditing(session: self)
	}
}

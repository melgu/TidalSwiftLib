//
//  LoginKind.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 12.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation

/// The two ways to log in, which get different streams. A session can hold one of each for the same account.
public enum LoginKind: Sendable, CaseIterable {
	/// Device flow with TidalSwift's own client: up to FLAC 16 bit / 44.1 kHz, and Dolby Atmos
	case device
	/// Authorization code flow with PKCE as Tidal's Android app, see ``Session/startPKCEAuthorization()``:
	/// up to FLAC 24 bit / 192 kHz, but no Dolby Atmos
	case pkce
}

extension Config {
	var kind: LoginKind {
		clientID == AuthInformation.PKCEClientID ? .pkce : .device
	}
	
	var isLoggedIn: Bool {
		!refreshToken.isEmpty
	}
}

extension Session {
	/// The kinds of the logins the session holds
	public var loginKinds: Set<LoginKind> {
		Set([config, secondConfig].compactMap { $0 }.filter(\.isLoggedIn).map(\.kind))
	}
	
	func login(_ kind: LoginKind) -> Config? {
		[config, secondConfig].compactMap { $0 }.first { $0.isLoggedIn && $0.kind == kind }
	}
}

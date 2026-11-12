//
//  Config.swift
//  TidalSwiftLib
//
//  Created by Melvin Gundlach on 01.08.20.
//  Copyright © 2020 Melvin Gundlach. All rights reserved.
//

import Foundation

enum AuthInformation {
	static let OAuthClientID = "4ywnjRfroi84hz7i"
	static let OAuthClientSecret = "7cNdrLt3NIQg0CHEpMDjcbV38XlwVdstczHqf59QiI0="
	static let scope = "r_usr+w_usr"
	// Android app client from tidalapi, which logs in with PKCE in a browser instead of the device flow
	static let PKCEClientID = "6BDSRdpK9hqEBTgU"
	static let PKCEClientSecret = "xeuPmY7nbpZ9IIbLAcQ93shka1VNheUAqN6IcszjTG8="
	static let PKCEScope = "r_usr+w_usr+w_sub"
	static let PKCEAuthorizeLocation = "https://login.tidal.com/authorize"
	static let PKCERedirectUri = "https://tidal.com/android/login/auth"
	static let APILocation = "https://api.tidal.com/v1"
	static let AuthLocation = "https://auth.tidal.com/v1/oauth2"
	static let ImageLocation = "https://resources.tidal.com/images"
	static let apiToken = "_DSTon1kC8pABnTw" // Direct ALAC, 1080p Videos
}

public class Config {
	var accessToken: String
	var refreshToken: String
	var clientID: String
	var tokenExpirationDate: Date?
	
	public init(
		accessToken: String,
		refreshToken: String,
		clientID: String,
		tokenExpirationDate: Date? = nil
	) {
		self.accessToken = accessToken
		self.refreshToken = refreshToken
		self.clientID = clientID
		self.tokenExpirationDate = tokenExpirationDate
	}
}

//
//  AuthConfig.swift
//  MeasureGo
//
//  Auth0 configuration mirrored from the Unity app (AuthService.cs).
//

import Foundation

enum AuthConfig {

    // Latham production config
    static let authDomain = "https://latham-prod.us.auth0.com"
    static let clientId = "fiawErjfaqxNUwgQALuXlcZ2LkiVzKyT"
    static let audience = "https://bright.ai"
    static let connection = "username-password-managed"

    static let userInfoEndpoint = "https://latham-prod.us.auth0.com/userinfo"
    static let userMeEndpoint = "https://admin.lathammeasure.com/api/v1/users/me"

    // Must match the callback registered in the Auth0 application settings.
    static let redirectUri = "com.latham.lathamlight://latham-prod.us.auth0.com/ios/com.Latham.LathamLight/callback"
    static let callbackScheme = "com.latham.lathamlight"

    static let scopes: [String] = [
        "openid profile email",
        "pool:ma:ra:dlr",
        "pool:ma:ra:dlrreport",
        "pool:ma:ra:logreport",
        "pool:ma:ra:poolshape",
        "pool:ma:ra:rsrc",
        "pool:ma:ra:rsrcimg",
        "pool:ma:ro:dlrreport",
        "pool:ma:ra:prjimg",
        "pool:ma:ra:rsrcraw",
        "pool:ma:ro:prj",
        "pool:ma:ro:user",
        "pool:ma:ca:logreport",
        "pool:ma:da:logreport",
        "pool:ma:da:prj",
        "pool:ma:da:rsrc",
        "pool:ma:uo:prj",
        "pool:ma:do:prj",
        "pool:ma:pa:rsrc",
        "pool:ma:pa:rsrcraw",
        "pool:ma:pa:rsrcfile",
        "pool:ma:pa:scan",
        "pool:ma:pa:signup",
    ]

    static var authorizeURL: URL {
        var components = URLComponents(string: "\(authDomain)/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "audience", value: audience),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "connection", value: connection),
        ]
        return components.url!
    }

    static var logoutURL: URL {
        var components = URLComponents(string: "\(authDomain)/logout")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "returnTo", value: redirectUri),
        ]
        return components.url!
    }
}

//
//  AuthManager.swift
//  MeasureGo
//
//  Token storage + backend user lookup, mirroring Unity's AuthManager.cs.
//

import Foundation

struct UserInfoResponse: Codable {
    let id: String
    let email: String?
    let phone: String?
    let name: String?
    let dealerId: String?
    let role: String?
    let isActive: Bool?
    let signedTOS: Bool?
    let createdAt: String?
    let updatedAt: String?
}

final class AuthManager {

    static let shared = AuthManager()
    private init() {}

    private let tokenKey = "auth_token_latham"
    private let userIdKey = "user_id_latham"

    var token: String? {
        get { KeychainStorage.getString(tokenKey) }
        set {
            if let newValue { KeychainStorage.setString(newValue, forKey: tokenKey) }
            else { KeychainStorage.remove(tokenKey) }
        }
    }

    var userId: String? {
        get { KeychainStorage.getString(userIdKey) }
        set {
            if let newValue { KeychainStorage.setString(newValue, forKey: userIdKey) }
            else { KeychainStorage.remove(userIdKey) }
        }
    }

    func clearAuth() {
        token = nil
        userId = nil
    }

    /// Validates the stored token against the Latham backend and caches the user id.
    /// Returns the user info on success, nil when the token is missing/invalid.
    func fetchCurrentUser() async -> UserInfoResponse? {
        guard let token, !token.isEmpty,
              let url = URL(string: AuthConfig.userMeEndpoint) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let userInfo = try JSONDecoder().decode(UserInfoResponse.self, from: data)
            userId = userInfo.id
            return userInfo
        } catch {
            return nil
        }
    }

    /// Lightweight token validity check against the Auth0 /userinfo endpoint
    /// (same check Unity's AuthService.CheckTokenValidity performs).
    func isTokenValid() async -> Bool {
        guard let token, !token.isEmpty,
              let url = URL(string: AuthConfig.userInfoEndpoint) else { return false }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}

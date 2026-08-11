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
    private let userEmailKey = "user_email_latham"

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

    /// Signed-in user's email, cached from /users/me — used to pre-fill the
    /// feedback form.
    var userEmail: String? {
        get { KeychainStorage.getString(userEmailKey) }
        set {
            if let newValue, !newValue.isEmpty {
                KeychainStorage.setString(newValue, forKey: userEmailKey)
            } else {
                KeychainStorage.remove(userEmailKey)
            }
        }
    }

    func clearAuth() {
        token = nil
        userId = nil
        userEmail = nil
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
            userEmail = userInfo.email
            return userInfo
        } catch {
            return nil
        }
    }

    enum TokenStatus {
        case valid
        case invalid      // server explicitly rejected the token
        case unreachable  // network problem — token may still be good
    }

    /// Lightweight token validity check against the Auth0 /userinfo endpoint
    /// (same check Unity's AuthService.CheckTokenValidity performs).
    /// Distinguishes "rejected" from "couldn't reach the server" so a network
    /// hiccup doesn't log the user out.
    func checkToken() async -> TokenStatus {
        guard let token, !token.isEmpty,
              let url = URL(string: AuthConfig.userInfoEndpoint) else { return .invalid }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unreachable }
            if (200..<300).contains(http.statusCode) { return .valid }
            if http.statusCode == 401 || http.statusCode == 403 { return .invalid }
            return .unreachable
        } catch {
            return .unreachable
        }
    }
}

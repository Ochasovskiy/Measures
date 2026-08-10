//
//  AuthService.swift
//  MeasureGo
//
//  Auth0 login/logout via ASWebAuthenticationSession,
//  mirroring Unity's AuthService.cs (implicit flow, response_type=token).
//

import AuthenticationServices
import Combine
import UIKit

@MainActor
final class AuthService: NSObject, ObservableObject {

    enum AuthState: Equatable {
        case idle
        case checkingToken
        case authenticating
        case loggedIn(autologin: Bool)
        case failed(String)
    }

    @Published private(set) var state: AuthState = .idle

    private var webAuthSession: ASWebAuthenticationSession?

    /// Mirrors Unity's StartAuthentication: use the saved token if it is still
    /// valid. With no (or an expired) token we stay idle and wait for the user
    /// to tap Login — auto-opening the web session during app launch fails
    /// because the window is not active yet.
    func startAuthentication() {
        state = .checkingToken
        Task {
            if let token = AuthManager.shared.token, !token.isEmpty {
                switch await AuthManager.shared.checkToken() {
                case .valid, .unreachable:
                    // Saved token path: show "Welcome back" + Continue/Logout.
                    // Offline counts as logged in — projects are local-first.
                    state = .loggedIn(autologin: false)
                    return
                case .invalid:
                    AuthManager.shared.clearAuth()
                }
            }
            state = .idle
        }
    }

    /// Opens the Auth0 hosted login page. A successful fresh login proceeds
    /// straight into the app (Unity's autologin=true path).
    func startLoginProcess() {
        state = .authenticating

        let session = ASWebAuthenticationSession(
            url: AuthConfig.authorizeURL,
            callbackURLScheme: AuthConfig.callbackScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                self?.handleCallback(callbackURL: callbackURL, error: error)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        webAuthSession = session
        session.start()
    }

    private func handleCallback(callbackURL: URL?, error: Error?) {
        webAuthSession = nil

        if let error {
            if let authError = error as? ASWebAuthenticationSessionError,
               authError.code == .canceledLogin {
                state = .idle
            } else {
                state = .failed(error.localizedDescription)
            }
            return
        }

        guard let callbackURL,
              let accessToken = Self.extractAccessToken(from: callbackURL) else {
            state = .failed("Failed to extract access token from callback URL.")
            return
        }

        AuthManager.shared.token = accessToken
        Task {
            // Cache the backend user id like Unity's AuthManager.CheckUserId.
            _ = await AuthManager.shared.fetchCurrentUser()
            state = .loggedIn(autologin: true)
        }
    }

    /// Clears local auth and opens the Auth0 logout endpoint so the web
    /// session cookie is also invalidated.
    func logout() {
        AuthManager.shared.clearAuth()

        let session = ASWebAuthenticationSession(
            url: AuthConfig.logoutURL,
            callbackURLScheme: AuthConfig.callbackScheme
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.webAuthSession = nil
                self?.state = .idle
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        webAuthSession = session
        session.start()
    }

    /// The implicit flow returns the token in the URL fragment:
    /// scheme://...#access_token=...&expires_in=...
    static func extractAccessToken(from url: URL) -> String? {
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment
        else { return nil }

        for pair in fragment.components(separatedBy: "&") {
            let parts = pair.components(separatedBy: "=")
            if parts.count == 2, parts[0] == "access_token", !parts[1].isEmpty {
                return parts[1]
            }
        }
        return nil
    }
}

extension AuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

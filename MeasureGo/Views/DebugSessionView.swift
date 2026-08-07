//
//  DebugSessionView.swift
//  MeasureGo
//
//  TEMPORARY post-login screen: shows the stored token and the user record
//  from /users/me so the auth flow can be verified. Will be replaced by the
//  real main screen in a later step.
//

import SwiftUI

struct DebugSessionView: View {

    @ObservedObject var authService: AuthService
    let onLogout: () -> Void

    @State private var user: UserInfoResponse?
    @State private var userLoadFailed = false
    @State private var tokenRevealed = false
    @State private var copied = false

    private var token: String { AuthManager.shared.token ?? "" }

    var body: some View {
        NavigationStack {
            List {
                Section("Session") {
                    row("Status", "Logged in")
                    row("Token length", "\(token.count) chars")
                    HStack {
                        Text(tokenRevealed ? token : maskedToken)
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(tokenRevealed ? nil : 1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(tokenRevealed ? "Hide" : "Show") { tokenRevealed.toggle() }
                            .font(.caption)
                    }
                    Button(copied ? "Copied ✓" : "Copy token to clipboard") {
                        UIPasteboard.general.string = token
                        copied = true
                    }
                }

                Section("User (/users/me)") {
                    if let user {
                        row("id", user.id)
                        row("email", user.email ?? "—")
                        row("name", user.name ?? "—")
                        row("phone", user.phone ?? "—")
                        row("role", user.role ?? "—")
                        row("dealerId", user.dealerId ?? "—")
                        row("isActive", user.isActive.map(String.init) ?? "—")
                        row("signedTOS", user.signedTOS.map(String.init) ?? "—")
                    } else if userLoadFailed {
                        Text("Failed to load user info")
                            .foregroundStyle(.red)
                    } else {
                        HStack {
                            ProgressView()
                            Text("Loading…").foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Logout", role: .destructive) {
                        authService.logout()
                        onLogout()
                    }
                }
            }
            .navigationTitle("MeasureGo (debug)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            let result = await AuthManager.shared.fetchCurrentUser()
            user = result
            userLoadFailed = (result == nil)
        }
    }

    private var maskedToken: String {
        guard token.count > 12 else { return token }
        return "\(token.prefix(8))…\(token.suffix(4))"
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

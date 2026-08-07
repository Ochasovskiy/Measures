//
//  LoginView.swift
//  MeasureGo
//
//  Native remake of the Unity auth window (GuiWindowAuthView):
//  gradient background, LA Measure + Latham logos,
//  Login / Continue / Logout buttons.
//

import SwiftUI

struct LoginView: View {

    @ObservedObject var authService: AuthService
    let onContinue: () -> Void

    private static let navy = Color(red: 0, green: 0.18, blue: 0.369)

    var body: some View {
        ZStack {
            Image("BgGradient")
                .resizable()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image("LAMeasureLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)

                statusLabel
                    .padding(.top, 24)

                Spacer()

                buttons
                    .padding(.horizontal, 40)

                Image("LathamLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 180)
                    .padding(.top, 40)
                    .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch authService.state {
        case .checkingToken, .authenticating:
            ProgressView()
                .tint(.white)
        case .loggedIn:
            Text("Welcome back")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
        case .failed:
            Text("Something went wrong")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch authService.state {
        case .loggedIn(let autologin):
            if autologin {
                // Fresh web login goes straight into the app; nothing to show.
                EmptyView()
            } else {
                VStack(spacing: 16) {
                    primaryButton("Continue", action: onContinue)
                    secondaryButton("Logout") { authService.logout() }
                }
            }
        case .idle, .failed:
            primaryButton("Login") { authService.startLoginProcess() }
        case .checkingToken, .authenticating:
            EmptyView()
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Self.navy)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color(red: 0.914, green: 0.922, blue: 0.973))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Self.navy)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color(red: 0.902, green: 0.918, blue: 0.937))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

#Preview {
    LoginView(authService: AuthService(), onContinue: {})
}

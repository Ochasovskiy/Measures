//
//  RootView.swift
//  MeasureGo
//
//  App-level flow: login screen first, then the main (AR) screen —
//  the native counterpart of Unity's FsmAuth -> FsmMain transition.
//

import SwiftUI

struct RootView: View {

    @StateObject private var authService = AuthService()
    @State private var showMain = false

    var body: some View {
        ZStack {
            if showMain {
                MainView()
            } else {
                LoginView(authService: authService) {
                    showMain = true
                }
            }
        }
        .onAppear {
            authService.startAuthentication()
        }
        .onChange(of: authService.state) { _, newState in
            // Fresh web login proceeds straight into the app (Unity autologin path).
            if case .loggedIn(autologin: true) = newState {
                showMain = true
            }
        }
    }
}

#Preview {
    RootView()
}

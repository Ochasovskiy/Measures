//
//  MeasureGoApp.swift
//  MeasureGo
//
//  SwiftUI app entry point (scene-based lifecycle — the old
//  UIApplicationDelegate window setup is deprecated and will assert in a
//  future iOS).
//

import SwiftUI
import UIKit

@main
struct MeasureGoApp: App {

    /// Only supplies the supported-orientation mask; SwiftUI still owns the
    /// window and lifecycle.
    @UIApplicationDelegateAdaptor(OrientationDelegate.self) private var orientationDelegate

    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppLog.startSession()
        CrashReporter.shared.start()

        // Brand the segmented controls: selected segment navy with white text.
        let navy = UIColor(red: 0.043, green: 0.145, blue: 0.29, alpha: 1)
        UISegmentedControl.appearance().selectedSegmentTintColor = navy
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: navy], for: .normal)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                // Hand the screen back to the system and never leave the
                // torch on. The scan screen re-arms both when it reappears.
                UIApplication.shared.isIdleTimerDisabled = false
                ARScanController.forceTorchOff()
                if newPhase == .background {
                    // A normal background is not a crash.
                    CrashReporter.shared.markCleanShutdown()
                    AppLog.log("App entered background")
                }
            case .active:
                CrashReporter.shared.markSessionRunning()
            @unknown default:
                break
            }
        }
    }
}

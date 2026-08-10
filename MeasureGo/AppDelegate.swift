//
//  AppDelegate.swift
//  MeasureGo
//
//  Created by Alexander on 07.08.2026.
//

import UIKit
import SwiftUI

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        AppLog.startSession()

        // Keep the screen awake while measuring (Unity's PreventScreenDimming).
        application.isIdleTimerDisabled = true

        // Brand the segmented controls: selected segment navy with white text.
        let navy = UIColor(red: 0.043, green: 0.145, blue: 0.29, alpha: 1)
        UISegmentedControl.appearance().selectedSegmentTintColor = navy
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: navy], for: .normal)

        // Create the SwiftUI view that provides the window contents.
        let contentView = RootView()

        // Use a UIHostingController as window root view controller.
        let window = UIWindow(frame: UIScreen.main.bounds)
        // All screens are designed light-on-brand; forcing light at the
        // window level also covers sheets and full-screen covers.
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = UIHostingController(rootView: contentView)
        self.window = window
        window.makeKeyAndVisible()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Hand the screen back to the system, and never leave the torch on.
        application.isIdleTimerDisabled = false
        ARScanController.forceTorchOff()
        AppLog.log("App entered background")
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        application.isIdleTimerDisabled = true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        application.isIdleTimerDisabled = false
        ARScanController.forceTorchOff()
    }


}


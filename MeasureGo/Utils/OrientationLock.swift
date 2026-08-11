//
//  OrientationLock.swift
//  MeasureGo
//
//  Lets a single screen pin the interface orientation.
//
//  The scan screen needs this: rotating the device mid-scan tears down and
//  re-creates the AR view, which restarts the ARKit session and throws away
//  every mesh anchor collected so far — the scan silently continues with a
//  partial mesh.
//

import UIKit

enum OrientationLock {

    /// Orientations the app currently allows. Changing this asks the active
    /// scene to adopt it immediately.
    static var mask: UIInterfaceOrientationMask = .all {
        didSet {
            guard mask != oldValue else { return }
            apply()
        }
    }

    private static func apply() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            AppLog.log("Orientation update failed: \(error.localizedDescription)")
        }
    }
}

/// Supplies the orientation mask to UIKit. Deliberately minimal — the window
/// and lifecycle are owned by SwiftUI (see MeasureGoApp).
final class OrientationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

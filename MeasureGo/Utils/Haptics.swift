//
//  Haptics.swift
//  MeasureGo
//
//  Deliberately sparse haptics: confirmation for actions taken while the
//  user is looking at the scene rather than the screen (placing points,
//  torch, saving), never for ordinary navigation taps.
//
//  Safety note: the point position is captured by the raycast *before* the
//  tap feedback fires, so the vibration cannot move an already-recorded
//  point. Feedback is kept light for the same reason.
//

import UIKit

enum Haptics {

    /// Point placed, or a comparable "it worked" confirmation.
    static func placement() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Toggles and selections (torch, height lock, point type).
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

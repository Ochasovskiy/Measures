//
//  SlideToConfirm.swift
//  MeasureGo
//
//  Port of Unity's SlideToComplete: drag the knob the full width to confirm.
//  Same rules as the original — the action fires on release only if the knob
//  reached the end, and the track resets either way, so a half-hearted drag
//  cannot complete a scan by accident.
//
//  This guards the one irreversible step in the flow. A rep is holding a phone
//  over water with wet hands, and a stray tap on a Complete button ends the
//  measurement; a deliberate drag does not happen by accident.
//

import SwiftUI

struct SlideToConfirm: View {

    let title: String
    let action: () -> Void

    @State private var offset: CGFloat = 0
    @GestureState private var dragging = false

    private let height: CGFloat = 56
    private let inset: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let knob: CGFloat = height - inset * 2
            let travel: CGFloat = max(0, geometry.size.width - knob - inset * 2)
            // Explicit Double: mixing CGFloat arithmetic into .opacity leaves
            // the expression ambiguous to the type checker.
            let progress: Double = travel > 0 ? Double(offset / travel) : 0
            let labelOpacity: Double = max(0, 1 - progress * 1.4)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MainView.navy.opacity(0.85))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    // Fades out as the knob covers it, so the label never
                    // fights the filled track for legibility.
                    .opacity(labelOpacity)
                    .frame(maxWidth: .infinity)

                Capsule()
                    .fill(MainView.salmon)
                    .frame(width: knob + offset + inset * 2)

                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .overlay {
                        Image(systemName: "chevron.right")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(MainView.navy)
                    }
                    .padding(.leading, inset)
                    .offset(x: offset)
                    .gesture(
                        DragGesture()
                            .updating($dragging) { _, state, _ in state = true }
                            .onChanged { value in
                                offset = min(max(0, value.translation.width), travel)
                            }
                            .onEnded { _ in
                                let completed = offset >= travel - 1
                                withAnimation(.spring(duration: 0.25)) { offset = 0 }
                                if completed { action() }
                            }
                    )
            }
        }
        .frame(height: height)
        .accessibilityRepresentation {
            Button(title, action: action)
        }
    }
}

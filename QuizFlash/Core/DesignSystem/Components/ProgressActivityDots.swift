//
//  ProgressActivityDots.swift
//  QuizFlash
//
//  Shared indeterminate loading indicator.
//

import SwiftUI

struct ProgressActivityDots: View {
    var color: Color = ThemeManager.shared.accentColor.color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = time - (Double(index) * 0.18)
                    let pulse = max(0.25, (sin(phase * 4.0) + 1) / 2)

                    Circle()
                        .fill(color.opacity(0.35 + (pulse * 0.55)))
                        .frame(width: 6, height: 6)
                        .scaleEffect(0.78 + (pulse * 0.36))
                }
            }
        }
        .frame(height: 8)
    }
}

//
//  View+KeepsScreenAwake.swift
//  QuizFlash
//

import SwiftUI
import UIKit

private struct KeepsScreenAwakeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
    }
}

extension View {
    func keepsScreenAwake() -> some View {
        modifier(KeepsScreenAwakeModifier())
    }
}

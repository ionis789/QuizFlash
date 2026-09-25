//
//  View+DevelopmentDiagnostics.swift
//  QuizFlash
//
//  Compile-time entry point for app-wide development probes.
//

import SwiftUI

extension View {
    /// Installs global diagnostics only in the dedicated Development build.
    @ViewBuilder
    func developmentDiagnostics() -> some View {
#if QUIZFLASH_DEVELOPMENT
        windowTouchProbe()
#else
        self
#endif
    }
}

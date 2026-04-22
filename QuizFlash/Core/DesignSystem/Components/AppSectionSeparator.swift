//
//  AppSectionSeparator.swift
//  QuizFlash
//
//  Shared minimalist separator for app sections.
//

import SwiftUI

// MARK: - App Section Separator

struct AppSectionSeparator: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Capsule(style: .continuous)
            .fill(themeManager.textPrimary.opacity(0.08))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

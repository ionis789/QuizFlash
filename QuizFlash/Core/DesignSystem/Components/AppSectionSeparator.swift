//
//  AppSectionSeparator.swift
//  QuizFlash
//
//  Shared minimalist separator for app sections.
//

import SwiftUI

// MARK: - App Section Separator

struct AppSectionSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color(uiColor: .systemGray4))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

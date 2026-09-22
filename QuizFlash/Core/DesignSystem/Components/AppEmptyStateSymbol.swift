//
//  AppEmptyStateSymbol.swift
//  QuizFlash
//
//  Standard decorative symbol for empty-state surfaces.
//

import SwiftUI

struct AppEmptyStateSymbol: View {
    @Environment(ThemeManager.self) private var themeManager

    let systemName: String
    var symbolSize: CGFloat = 42
    var frameSize: CGFloat = 80

    private var symbolTint: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: themeManager.textSecondary.opacity(0.82), location: 0),
                .init(color: themeManager.textSecondary.opacity(0.78), location: 0.72),
                .init(color: themeManager.brandPrimary.opacity(0.58), location: 1),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(symbolTint)
            .frame(width: frameSize, height: frameSize)
            .accessibilityHidden(true)
    }
}

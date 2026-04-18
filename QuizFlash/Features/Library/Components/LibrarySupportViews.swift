//
//  LibrarySupportViews.swift
//  QuizFlash
//
//  Auxiliary Library views:
//  - empty state
//  - selection indicator
//  - blocking loading overlay
//

import SwiftUI

// MARK: - Empty State

/// View shown when there are no decks available in the library yet.
struct LibraryEmptyStateView: View {
    @Environment(ThemeManager.self) private var themeManager

    private var accent: Color { themeManager.accentColor.color }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(accent.opacity(0.8))
            }

            VStack(spacing: 8) {
                Text("No Decks Yet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(themeManager.textPrimary)
                Text("Tap Create to make your first deck\nand start learning.")
                    .font(.subheadline)
                    .foregroundStyle(themeManager.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 90)
        .padding(.horizontal, 40)
    }
}

// MARK: - Selection Indicator

/// Circle checkmark indicator for deck selection mode.
struct LibrarySelectionIndicator: View {
    @Environment(ThemeManager.self) private var themeManager

    let isSelected: Bool
    let onToggle: () -> Void

    private var accent: Color { themeManager.accentColor.color }

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                Circle()
                    .fill(isSelected ? accent : themeManager.textPrimary.opacity(0.08))
                    .frame(width: 24, height: 24)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .strokeBorder(themeManager.textSecondary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .animation(.circularSelectionSpring, value: isSelected)
    }
}

// MARK: - Loading Overlay

/// Semi-transparent loading overlay with spinner used for operations like import and export.
struct LibraryLoadingOverlay: View {
    @Environment(ThemeManager.self) private var themeManager

    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(themeManager.textPrimary)
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(themeManager.textPrimary)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(themeManager.textPrimary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.2), radius: 20)
        }
        .transition(.opacity)
    }
}

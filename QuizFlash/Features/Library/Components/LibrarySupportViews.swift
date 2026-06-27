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
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let onCreate: () -> Void

    private var accent: Color { themeManager.accentColor.color }

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    var body: some View {
        Button(action: onCreate) {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.1))
                        .frame(width: 80, height: 80)
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(accent.opacity(0.9))
                }

                VStack(spacing: 8) {
                    Text(localized("No Decks Yet"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(themeManager.textPrimary)
                    Text(localized("Create your first deck and start learning."))
                        .font(.subheadline)
                        .foregroundStyle(themeManager.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 90)
            .padding(.horizontal, 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    var body: some View {
        ZStack {
            Color.black.opacity(0.001).ignoresSafeArea()

            ProgressActivityDots(color: themeManager.textPrimary)
                .scaleEffect(1.45)
        }
        .transition(.opacity)
    }
}

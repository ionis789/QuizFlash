//
//  LibrarySupportViews.swift
//  QuizFlash
//
//  Auxiliary Library views:
//  - empty state
//  - selection indicator
//  - sync progress
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
                    Image(systemName: "rectangle.stack.fill")
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

// MARK: - Sync Progress

struct LibrarySyncProgressPill: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let progress: CloudSyncProgressSnapshot

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    private var title: String {
        guard progress.totalItems > 0 else {
            return AppLocalization.string("Syncing…", locale: locale)
        }

        let format = AppLocalization.string("Syncing %d/%d", locale: locale)
        return String(
            format: format,
            locale: locale,
            progress.boundedCompletedItems,
            progress.totalItems
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            if let fraction = progress.progressFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(themeManager.accentColor.color)
                    .frame(width: 48)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .tint(themeManager.accentColor.color)
            }

            Text(title)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(themeManager.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(themeManager.surfaceSecondary.opacity(0.82))
                .overlay(
                    Capsule()
                        .strokeBorder(themeManager.textPrimary.opacity(0.08), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
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

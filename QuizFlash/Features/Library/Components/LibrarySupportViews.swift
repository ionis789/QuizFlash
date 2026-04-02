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
    private var accent: Color { ThemeManager.shared.accentColor.color }

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
                Text("Tap Create to make your first deck\nand start learning.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
    let isSelected: Bool
    let onToggle: () -> Void

    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                Circle()
                    .fill(isSelected ? accent : Color.primary.opacity(0.08))
                    .frame(width: 26, height: 26)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 26, height: 26)
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Loading Overlay

/// Semi-transparent loading overlay with spinner used for operations like import and export.
struct LibraryLoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.primary)
                Text(message)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.2), radius: 20)
        }
        .transition(.opacity)
    }
}

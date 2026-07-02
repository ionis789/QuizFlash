//
//  AIGenerationSheetOptionViews.swift
//  QuizFlash
//
//  Option selectors used by the AI generation sheet.
//

import SwiftUI

struct DistributionModeButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    private var selectedForeground: Color {
        ThemeManager.shared.roleColor(.labelPrimaryForeground)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isSelected ? selectedForeground : .primary)

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? selectedForeground : .secondary)
                }

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? selectedForeground.opacity(0.72) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(UIConstants.Spacing.standard)
            .primarySelectionSurface(isSelected: isSelected, cornerRadius: 18)
        }
        .duoPressableSurfaceStyle()
    }
}

struct GenerationChoiceCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    private var selectedForeground: Color {
        ThemeManager.shared.roleColor(.labelPrimaryForeground)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? selectedForeground : .primary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? selectedForeground : .secondary)
                }

                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isSelected ? selectedForeground : .primary)

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? selectedForeground.opacity(0.72) : .secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
            .padding(UIConstants.Spacing.medium)
            .primarySelectionSurface(isSelected: isSelected, cornerRadius: 18)
        }
        .duoPressableSurfaceStyle()
    }
}

struct GenerationRowButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    private var selectedForeground: Color {
        ThemeManager.shared.roleColor(.labelPrimaryForeground)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: UIConstants.Spacing.medium) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isSelected ? selectedForeground : .primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isSelected ? selectedForeground.opacity(0.72) : .secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? selectedForeground : .secondary)
            }
            .padding(14)
            .primarySelectionSurface(isSelected: isSelected, cornerRadius: 16)
        }
        .duoPressableSurfaceStyle()
    }
}

struct ModeButton: View {
    let isSelected: Bool
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let onTap: () -> Void

    private var selectedForeground: Color {
        ThemeManager.shared.roleColor(.labelPrimaryForeground)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(isSelected ? selectedForeground : iconColor)
                    .font(.title3)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? selectedForeground : .primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(isSelected ? selectedForeground.opacity(0.72) : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? selectedForeground : .secondary)
                    .font(.title3)
            }
            .padding(14)
            .primarySelectionSurface(isSelected: isSelected, cornerRadius: 14)
        }
        .duoPressableSurfaceStyle()
    }
}

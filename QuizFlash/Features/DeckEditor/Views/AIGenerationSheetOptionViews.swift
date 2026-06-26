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

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? accent : .secondary)
                }

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(UIConstants.Spacing.standard)
            .duoControlSurface(cornerRadius: 18, tint: isSelected ? accent : nil)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent.opacity(0.42), lineWidth: 1.2)
                }
            }
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

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? accent : .primary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? accent : .secondary)
                }

                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
            .padding(UIConstants.Spacing.medium)
            .duoControlSurface(cornerRadius: 18, tint: isSelected ? accent : nil)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent.opacity(0.42), lineWidth: 1.2)
                }
            }
        }
        .duoPressableSurfaceStyle()
    }
}

struct GenerationRowButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: UIConstants.Spacing.medium) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding(14)
            .duoControlSurface(cornerRadius: 16, tint: isSelected ? Color.accentColor : nil)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.42), lineWidth: 1.2)
                }
            }
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

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.title3)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .padding(14)
            .duoControlSurface(cornerRadius: 14, tint: isSelected ? Color.accentColor : nil)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.48), lineWidth: 1.2)
                }
            }
        }
        .duoPressableSurfaceStyle()
    }
}

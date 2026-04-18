//
//  SettingsComponents.swift
//  QuizFlash
//
//  Shared cards and rows used across the Settings feature.
//

import SwiftUI

// MARK: - Settings Chrome Metrics

enum SettingsChromeMetrics {
    static let pillRevealClearance: CGFloat = 60
}

// MARK: - Settings Header Card

struct SettingsHeaderCard: View {
    @Environment(ThemeManager.self) private var themeManager

    let icon: String
    let title: String
    let subtitle: String?
    let tint: Color
    let badges: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                ZStack {
                    RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.26), tint.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 62, height: 62)

                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    Text(title)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(themeManager.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle {
                        Text(subtitle)
                            .font(.body.weight(.medium))
                            .foregroundStyle(themeManager.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !badges.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110), spacing: UIConstants.Spacing.small)],
                    alignment: .leading,
                    spacing: UIConstants.Spacing.small
                ) {
                    ForEach(badges, id: \.self) { badge in
                        SettingsBadge(title: badge)
                    }
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .settingsCardBackground(cornerRadius: UIConstants.Radius.maximum)
    }
}

// MARK: - Settings Section Card

struct SettingsSectionCard<Content: View>: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(themeManager.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
        .padding(UIConstants.Spacing.large)
        .settingsCardBackground(cornerRadius: UIConstants.Radius.large)
    }
}

// MARK: - Settings Rows

struct SettingsNavigationRow: View {
    @Environment(ThemeManager.self) private var themeManager

    let icon: String
    let tint: Color
    let title: String
    let detail: String?
    let value: String?

    var body: some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
            SettingsRowIcon(icon: icon, tint: tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(themeManager.textPrimary)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(themeManager.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if let value, !value.isEmpty {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeManager.textSecondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(themeManager.textSecondary.opacity(0.72))
        }
        .contentShape(Rectangle())
    }
}

struct SettingsToggleRow: View {
    @Environment(ThemeManager.self) private var themeManager

    let icon: String
    let tint: Color
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                SettingsRowIcon(icon: icon, tint: tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(themeManager.textPrimary)

                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(themeManager.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .tint(tint)
    }
}

struct SettingsMenuPickerRow<Option: Identifiable & Hashable>: View {
    @Environment(ThemeManager.self) private var themeManager

    let icon: String
    let tint: Color
    let title: String
    let detail: String
    @Binding var selection: Option
    let options: [Option]
    let titleForOption: (Option) -> String

    var body: some View {
        HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
            SettingsRowIcon(icon: icon, tint: tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(themeManager.textPrimary)

                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(themeManager.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: UIConstants.Spacing.standard)

            Menu {
                ForEach(options) { option in
                    Button {
                        selection = option
                    } label: {
                        if selection == option {
                            Label(titleForOption(option), systemImage: "checkmark")
                        } else {
                            Text(titleForOption(option))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(titleForOption(selection))
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(themeManager.textPrimary)
                .padding(.horizontal, UIConstants.Spacing.standard)
                .padding(.vertical, UIConstants.Spacing.small)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
}

struct SettingsSliderRow: View {
    @Environment(ThemeManager.self) private var themeManager

    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let valueSuffix: String
    let range: ClosedRange<Double>
    let step: Double
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                SettingsRowIcon(icon: icon, tint: tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(themeManager.textPrimary)

                    Text(detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(themeManager.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: UIConstants.Spacing.standard)

                Text("\(Int(value.rounded())) \(valueSuffix)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeManager.textPrimary)
                    .padding(.horizontal, UIConstants.Spacing.standard)
                    .padding(.vertical, UIConstants.Spacing.small)
                    .background(.ultraThinMaterial, in: Capsule())
                    .contentTransition(.numericText())
            }

            HStack(spacing: UIConstants.Spacing.small) {
                Text("\(Int(range.lowerBound))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeManager.textSecondary)

                Slider(value: $value, in: range, step: step)
                    .tint(tint)

                Text("\(Int(range.upperBound))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeManager.textSecondary)
            }
            .padding(.leading, 54)
        }
    }
}

struct SettingsInfoCard: View {
    @Environment(ThemeManager.self) private var themeManager

    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)

            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(themeManager.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(UIConstants.Spacing.standard)
        .settingsCardBackground(cornerRadius: UIConstants.Radius.large)
    }
}

struct SettingsCardDivider: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Rectangle()
            .fill(themeManager.roleColor(.settingsCardBorder).opacity(0.16))
            .frame(height: 1)
            .padding(.leading, 54)
    }
}

// MARK: - Small Shared Pieces

private struct SettingsBadge: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(themeManager.textPrimary)
            .padding(.horizontal, UIConstants.Spacing.standard)
            .padding(.vertical, UIConstants.Spacing.small)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct SettingsRowIcon: View {
    let icon: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                .fill(tint.opacity(0.14))
                .frame(width: 40, height: 40)

            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
        }
    }
}

private struct SettingsCardBackgroundModifier: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(themeManager.roleColor(.settingsCardFill))
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(themeManager.roleColor(.settingsCardBorder).opacity(0.18), lineWidth: 0.75)
            }
    }
}

extension View {
    func settingsCardBackground(cornerRadius: CGFloat) -> some View {
        modifier(SettingsCardBackgroundModifier(cornerRadius: cornerRadius))
    }
}

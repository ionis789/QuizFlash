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
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle {
                        Text(subtitle)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
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
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
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
                    .foregroundStyle(.primary)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if let value, !value.isEmpty {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                SettingsRowIcon(icon: icon, tint: tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(tint)
    }
}

struct SettingsMenuPickerRow<Option: Identifiable & Hashable>: View {
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
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.primary)
                .padding(.horizontal, UIConstants.Spacing.standard)
                .padding(.vertical, UIConstants.Spacing.small)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
}

struct SettingsSliderRow: View {
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
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: UIConstants.Spacing.standard)

                Text("\(Int(value.rounded())) \(valueSuffix)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, UIConstants.Spacing.standard)
                    .padding(.vertical, UIConstants.Spacing.small)
                    .background(.ultraThinMaterial, in: Capsule())
                    .contentTransition(.numericText())
            }

            HStack(spacing: UIConstants.Spacing.small) {
                Text("\(Int(range.lowerBound))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Slider(value: $value, in: range, step: step)
                    .tint(tint)

                Text("\(Int(range.upperBound))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 54)
        }
    }
}

struct SettingsInfoCard: View {
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
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(UIConstants.Spacing.standard)
        .settingsCardBackground(cornerRadius: UIConstants.Radius.large)
    }
}

struct SettingsCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 54)
    }
}

// MARK: - Small Shared Pieces

private struct SettingsBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
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
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75)
            }
    }
}

extension View {
    func settingsCardBackground(cornerRadius: CGFloat) -> some View {
        modifier(SettingsCardBackgroundModifier(cornerRadius: cornerRadius))
    }
}

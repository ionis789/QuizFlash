//
//  PlayModeSettingsRows.swift
//  QuizFlash
//
//  Shared background and row primitives for the play-mode settings screen.
//

import SwiftUI

// MARK: - Settings Background

/// Decorative background shared by play-mode settings surfaces.
struct PlayModeSettingsBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let deck: DeckModel
    let mode: DeckPlayModeDestination

    private var accentColor: Color { ThemeManager.shared.accentColor.color }
    private var deckColor: Color { Color(hex: deck.colorHex) ?? accentColor }
    private var tintColor: Color {
        mode.tintColor(deckColor: deckColor, accentColor: accentColor)
    }

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color.black
            } else {
                Color(uiColor: .systemGroupedBackground)
            }

            LinearGradient(
                colors: [
                    deckColor.opacity(colorScheme == .dark ? 0.18 : 0.14),
                    tintColor.opacity(colorScheme == .dark ? 0.10 : 0.07),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(deckColor.opacity(0.18))
                .frame(
                    width: UIConstants.Spacing.huge * 8,
                    height: UIConstants.Spacing.huge * 8
                )
                .blur(radius: UIConstants.Spacing.huge * 2.5)
                .offset(
                    x: UIConstants.Spacing.huge * 2,
                    y: -UIConstants.Spacing.huge * 2
                )

            Circle()
                .fill(accentColor.opacity(0.12))
                .frame(
                    width: UIConstants.Spacing.huge * 7,
                    height: UIConstants.Spacing.huge * 7
                )
                .blur(radius: UIConstants.Spacing.huge * 2)
                .offset(
                    x: -UIConstants.Spacing.huge * 2,
                    y: UIConstants.Spacing.huge * 4
                )
        }
    }
}

// MARK: - Settings Rows

/// Shared toggle row used inside the play-mode settings screen.
struct PlayModeSettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Toggle(isOn: $isOn) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .tint(tint)

            Text(detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Shared segmented-control row used by small enum selections.
struct PlayModeSettingsSegmentedRow<Option: Identifiable & Hashable>: View {
    let title: String
    let detail: String
    @Binding var selection: Option
    let options: [Option]
    let titleForOption: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text(detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(titleForOption(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// Shared menu row used by wider enum selections that do not fit comfortably in a segmented control.
struct PlayModeSettingsMenuRow<Option: Identifiable & Hashable>: View {
    let title: String
    let detail: String
    @Binding var selection: Option
    let options: [Option]
    let titleForOption: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: UIConstants.Spacing.standard)

                Menu {
                    Picker(title, selection: $selection) {
                        ForEach(options) { option in
                            Text(titleForOption(option)).tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(titleForOption(selection))
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, UIConstants.Spacing.standard)
                    .padding(.vertical, UIConstants.Spacing.small)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
    }
}

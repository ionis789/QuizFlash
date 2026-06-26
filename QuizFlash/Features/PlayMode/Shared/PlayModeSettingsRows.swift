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

    var body: some View {
        if colorScheme == .dark {
            Color.black
        } else {
            Color(uiColor: .systemGroupedBackground)
        }
    }
}

// MARK: - Settings Rows

/// Shared toggle row used inside the play-mode settings screen.
struct PlayModeSettingsToggleRow: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Toggle(isOn: $isOn) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
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
    @Environment(AppPreferences.self) private var appPreferences

    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    @Binding var selection: Option
    let options: [Option]
    let titleForOption: (Option, Locale) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Text(detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker(selection: $selection) {
                ForEach(options) { option in
                    Text(titleForOption(option, appPreferences.resolvedLocale)).tag(option)
                }
            } label: {
                Text(title)
            }
            .pickerStyle(.segmented)
        }
    }
}

/// Shared menu row used by wider enum selections that do not fit comfortably in a segmented control.
struct PlayModeSettingsMenuRow<Option: Identifiable & Hashable>: View {
    @Environment(AppPreferences.self) private var appPreferences

    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    @Binding var selection: Option
    let options: [Option]
    let titleForOption: (Option, Locale) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: UIConstants.Spacing.standard)

                Menu {
                    Picker(selection: $selection) {
                        ForEach(options) { option in
                            Text(titleForOption(option, appPreferences.resolvedLocale)).tag(option)
                        }
                    } label: {
                        Text(title)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(titleForOption(selection, appPreferences.resolvedLocale))
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

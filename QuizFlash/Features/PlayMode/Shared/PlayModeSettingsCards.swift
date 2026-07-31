//
//  PlayModeSettingsCards.swift
//  QuizFlash
//
//  Extracted cards for the shared play-mode settings screen.
//

import SwiftUI

// MARK: - Play Mode Settings Cards

struct PlayModeSettingsOverviewCard: View {
    @Environment(AppPreferences.self) private var appPreferences

    let mode: DeckPlayModeDestination
    let tintColor: Color
    let compatibleCardCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                ZStack {
                    RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                        .fill(tintColor.opacity(0.12))
                        .frame(
                            width: UIConstants.Size.actionButton + UIConstants.Spacing.extraLarge,
                            height: UIConstants.Size.actionButton + UIConstants.Spacing.extraLarge
                        )

                    Image(systemName: mode.systemImage)
                        .font(.system(size: UIConstants.Size.iconLarge, weight: .black))
                        .foregroundStyle(tintColor)
                        .rotationEffect(mode.systemImageRotation)
                }

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    Text("DECK-SCOPED SETTINGS")
                        .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .bold))
                        .foregroundStyle(.secondary)

                    Text(mode.localizedSettingsHeadline(locale: appPreferences.resolvedLocale))
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(mode.localizedSettingsSupportingCopy(locale: appPreferences.resolvedLocale))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: UIConstants.Spacing.small) {
                PlayModeSettingsStatusChip(
                    title: AppLocalization.string("Autosaved", locale: appPreferences.resolvedLocale),
                    icon: "checkmark.circle.fill"
                )

                Spacer(minLength: 0)

                PlayModeSettingsStatusChip(
                    title: compatibleCardCount > 0
                        ? String.localizedStringWithFormat(
                            AppLocalization.string("%d Compatible", locale: appPreferences.resolvedLocale),
                            compatibleCardCount
                        )
                        : AppLocalization.string("No Compatible Cards", locale: appPreferences.resolvedLocale),
                    icon: compatibleCardCount > 0 ? "bolt.fill" : "exclamationmark.circle"
                )
            }
        }
        .padding(UIConstants.Spacing.large)
        .flashcardStyle(cornerRadius: UIConstants.Radius.maximum, surfaceRole: .widget)
    }
}

struct PlayModeSettingsModeCard: View {
    let mode: DeckPlayModeDestination
    let tintColor: Color
    @Binding var flashcardSettings: FlashcardModeSettings
    @Binding var quizSettings: QuizModeSettings

    @ViewBuilder
    var body: some View {
        switch mode {
        case .flashcards:
            CompactFlashcardSettingsCard(
                tintColor: tintColor,
                flashcardSettings: $flashcardSettings
            )
        case .quiz:
            CompactQuizSettingsCard(
                tintColor: tintColor,
                quizSettings: $quizSettings
            )
        }
    }
}

private struct CompactFlashcardSettingsCard: View {
    let tintColor: Color
    @Binding var flashcardSettings: FlashcardModeSettings
    private var accentTint: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        VStack(spacing: UIConstants.Spacing.small) {
            CompactSettingsMenuRow(
                title: "Card Order",
                icon: "arrow.up.arrow.down",
                tint: accentTint,
                selection: $flashcardSettings.order,
                options: FlashcardSessionOrder.allCases,
                isDense: true
            ) { option, locale in
                option.localizedTitle(locale: locale)
            }

            CompactSettingsToggleRow(
                title: "Retry Wrong Cards",
                icon: "arrow.clockwise",
                isOn: $flashcardSettings.retryWrongCards,
                tint: accentTint,
                isDense: true
            )

            CompactTapAnimationRow(
                tint: accentTint,
                tapAnimationStyle: $flashcardSettings.tapAnimationStyle,
                staticSwapTextMotion: $flashcardSettings.staticSwapTextMotion
            )

            CompactSettingsButtonRow(
                title: "Content Alignment",
                icon: "text.aligncenter",
                tint: accentTint,
                selection: $flashcardSettings.contentAlignment,
                options: FlashcardContentAlignment.allCases,
                isDense: true
            ) { option, locale in
                option.localizedTitle(locale: locale)
            }

            CompactTextSizeSliderRow(
                title: "Text Size",
                icon: "textformat.size",
                tint: accentTint,
                textSize: $flashcardSettings.textSize,
                usesAppTextSize: $flashcardSettings.usesAppTextSize,
                isDense: true
            )
        }
        .padding(.horizontal, UIConstants.Spacing.medium)
    }
}

private struct CompactTapAnimationRow: View {
    @Environment(AppPreferences.self) private var appPreferences

    let tint: Color
    @Binding var tapAnimationStyle: FlashcardTapAnimationStyle
    @Binding var staticSwapTextMotion: FlashcardStaticSwapTextMotion

    private var selectedForeground: Color {
        ThemeManager.shared.roleColor(.labelPrimaryForeground)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            label(title: "Tap Animation", icon: "rectangle.2.swap")

            optionButtons(
                selection: $tapAnimationStyle,
                options: FlashcardTapAnimationStyle.allCases
            ) { option, locale in
                option.localizedTitle(locale: locale)
            }

            if tapAnimationStyle == .staticSwap {
                optionButtons(
                    selection: $staticSwapTextMotion,
                    options: FlashcardStaticSwapTextMotion.allCases
                ) { option, locale in
                    option.localizedTitle(locale: locale)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .padding(.horizontal, UIConstants.Spacing.medium)
        .padding(.top, UIConstants.Spacing.medium)
        .padding(.bottom, tapAnimationStyle == .staticSwap ? UIConstants.Spacing.standard : UIConstants.Spacing.medium)
        .frame(minHeight: tapAnimationStyle == .staticSwap ? 158 : 110, alignment: .top)
        .duoControlSurface(tint: tint)
        .animation(.easeInOut(duration: 0.16), value: tapAnimationStyle)
    }

    private func label(title: LocalizedStringResource, icon: String) -> some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            CompactSettingsIcon(systemName: icon, tint: tint)

            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private func optionButtons<Option: Identifiable & Hashable>(
        selection: Binding<Option>,
        options: [Option],
        titleForOption: @escaping (Option, Locale) -> String
    ) -> some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            ForEach(options) { option in
                let isSelected = option == selection.wrappedValue

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection.wrappedValue = option
                    }
                } label: {
                    Text(titleForOption(option, appPreferences.resolvedLocale))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isSelected ? selectedForeground : Color.primary.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .contentTransition(.identity)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .primarySelectionSurface(isSelected: isSelected, cornerRadius: 20)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 40)
    }
}

private struct CompactQuizSettingsCard: View {
    let tintColor: Color
    @Binding var quizSettings: QuizModeSettings
    private var accentTint: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        VStack(spacing: UIConstants.Spacing.small) {
            CompactSettingsToggleRow(
                title: "Shuffle Choices",
                icon: "shuffle",
                isOn: $quizSettings.shuffleChoices,
                tint: accentTint,
                isDense: true
            )

            CompactSettingsButtonRow(
                title: "Validation",
                icon: "checkmark.seal.fill",
                tint: accentTint,
                selection: $quizSettings.answerValidation,
                options: QuizAnswerValidationMode.allCases,
                isDense: true
            ) { option, locale in
                option.localizedTitle(locale: locale)
            }

            CompactSettingsToggleRow(
                title: "Retry Wrong Quiz",
                icon: "arrow.clockwise",
                isOn: $quizSettings.retryIncorrectQuestions,
                tint: accentTint,
                isDense: true
            )

            CompactTextSizeSliderRow(
                title: "Text Size",
                icon: "textformat.size",
                tint: accentTint,
                textSize: $quizSettings.textSize,
                usesAppTextSize: $quizSettings.usesAppTextSize,
                isDense: true
            )
        }
        .padding(.horizontal, UIConstants.Spacing.medium)
    }
}

private struct CompactTextSizeSliderRow: View {
    @Environment(AppPreferences.self) private var appPreferences

    let title: LocalizedStringResource
    let icon: String
    let tint: Color
    @Binding var textSize: FlashcardTextSize
    @Binding var usesAppTextSize: Bool
    @State private var isExpanded = false
    var isDense = false

    private var resolvedTextSize: FlashcardTextSize {
        usesAppTextSize ? appPreferences.defaultTextSize : textSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? UIConstants.Spacing.medium : 0) {
            HStack(spacing: UIConstants.Spacing.small) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: UIConstants.Spacing.medium) {
                        CompactSettingsIcon(systemName: icon, tint: tint)

                        Text(title)
                            .font(.system(size: isDense ? 17 : 18, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: UIConstants.Spacing.small)
                    }
                    .contentShape(Rectangle())
                }
                .noPressEffectButtonStyle()

                Button {
                    withAnimation(.selectionToolbarSpring) {
                        usesAppTextSize = true
                    }
                } label: {
                    Text(AppLocalization.string("Default", locale: appPreferences.resolvedLocale))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(usesAppTextSize ? .primary : .secondary)
                        .padding(.horizontal, UIConstants.Spacing.medium)
                        .frame(height: 34)
                        .background(
                            usesAppTextSize ? tint.opacity(0.16) : Color.primary.opacity(0.06),
                            in: Capsule(style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(usesAppTextSize ? .isSelected : [])
            }

            if isExpanded {
                TextSizeScalePicker(
                    textSize: resolvedTextSize,
                    previewText: AppLocalization.string("Comfortable reading", locale: appPreferences.resolvedLocale),
                    onChange: { newValue in
                        textSize = newValue
                        usesAppTextSize = false
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .padding(isDense ? UIConstants.Spacing.medium : UIConstants.Spacing.standard)
        .frame(minHeight: isExpanded ? (isDense ? 178 : 194) : (isDense ? 70 : 78))
        .duoControlSurface(tint: tint)
        .animation(.easeInOut(duration: 0.16), value: isExpanded)
    }
}

private struct CompactSettingsMenuRow<Option: Identifiable & Hashable>: View {
    @Environment(AppPreferences.self) private var appPreferences

    let title: LocalizedStringResource
    let icon: String
    let tint: Color
    @Binding var selection: Option
    let options: [Option]
    var isDense = false
    let titleForOption: (Option, Locale) -> String

    var body: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            CompactSettingsIcon(systemName: icon, tint: tint)

            Text(title)
                .font(.system(size: isDense ? 17 : 18, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: UIConstants.Spacing.small)

            Menu {
                Picker(selection: $selection) {
                    ForEach(options) { option in
                        Text(titleForOption(option, appPreferences.resolvedLocale))
                            .tag(option)
                    }
                } label: {
                    Text(title)
                }
            } label: {
                HStack(spacing: UIConstants.Spacing.tiny) {
                    Text(titleForOption(selection, appPreferences.resolvedLocale))
                        .font(.system(size: isDense ? 14 : 15, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .black))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, isDense ? UIConstants.Spacing.medium : UIConstants.Spacing.standard)
                .frame(height: isDense ? 38 : 44)
                .background(Color.primary.opacity(0.075), in: Capsule())
            }
            .noPressEffectButtonStyle()
        }
        .padding(.horizontal, UIConstants.Spacing.standard)
        .padding(.vertical, isDense ? UIConstants.Spacing.small : UIConstants.Spacing.medium)
        .frame(minHeight: isDense ? 58 : 68)
        .duoControlSurface(tint: tint)
    }
}

private struct CompactSettingsToggleRow: View {
    let title: LocalizedStringResource
    let icon: String
    @Binding var isOn: Bool
    let tint: Color
    var isDense = false

    var body: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            CompactSettingsIcon(systemName: icon, tint: tint)

            Text(title)
                .font(.system(size: isDense ? 17 : 18, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: UIConstants.Spacing.small)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(tint)
                .scaleEffect(isDense ? 0.86 : 0.92)
        }
        .padding(.horizontal, UIConstants.Spacing.standard)
        .padding(.vertical, isDense ? UIConstants.Spacing.small : UIConstants.Spacing.medium)
        .frame(minHeight: isDense ? 58 : 68)
        .duoControlSurface(tint: tint)
    }
}

private struct CompactSettingsButtonRow<Option: Identifiable & Hashable>: View {
    @Environment(AppPreferences.self) private var appPreferences

    let title: LocalizedStringResource
    let icon: String
    let tint: Color
    @Binding var selection: Option
    let options: [Option]
    var isDense = false
    let titleForOption: (Option, Locale) -> String

    private var selectedForeground: Color {
        ThemeManager.shared.roleColor(.labelPrimaryForeground)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isDense ? UIConstants.Spacing.small : UIConstants.Spacing.standard) {
            label
            HStack(spacing: UIConstants.Spacing.medium) {
                ForEach(options) { option in
                    validationButton(for: option)
                }
            }
        }
        .padding(isDense ? UIConstants.Spacing.medium : UIConstants.Spacing.standard)
        .frame(minHeight: isDense ? 106 : 124)
        .duoControlSurface(tint: tint)
    }

    private var label: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            CompactSettingsIcon(systemName: icon, tint: tint)

            Text(title)
                .font(.system(size: isDense ? 17 : 18, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private func validationButton(for option: Option) -> some View {
        let isSelected = option == selection

        return Button {
            selection = option
        } label: {
            Text(titleForOption(option, appPreferences.resolvedLocale))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isSelected ? selectedForeground : Color.primary.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(height: isDense ? 40 : 48)
                .primarySelectionSurface(isSelected: isSelected, cornerRadius: (isDense ? 40 : 48) / 2)
        }
        .noPressEffectButtonStyle()
    }
}

private struct CompactSettingsIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .black))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous))
    }
}

struct PlayModeSettingsReadinessCard: View {
    let readinessCopy: String
    let summaryLines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            Text("Current Summary")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            Text(readinessCopy)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                ForEach(summaryLines, id: \.self) { line in
                    Text("• \(line)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .flashcardStyle(cornerRadius: UIConstants.Radius.large, surfaceRole: .widget)
    }
}

private struct PlayModeSettingsSectionCard<Content: View>: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .padding(UIConstants.Spacing.large)
        .flashcardStyle(cornerRadius: UIConstants.Radius.large, surfaceRole: .widget)
    }
}

private struct PlayModeSettingsStatusChip: View {
    let title: String
    let icon: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .duoMetricPill()
    }
}

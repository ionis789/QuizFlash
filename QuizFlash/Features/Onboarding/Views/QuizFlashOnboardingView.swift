//
//  QuizFlashOnboardingView.swift
//  QuizFlash
//
//  Created by Ion Socol on 03.07.2026.
//

import SwiftUI

// MARK: - QuizFlash Onboarding View

struct QuizFlashOnboardingView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let presentation: OnboardingPresentation
    let onComplete: @MainActor @Sendable (OnboardingPresentation) -> Void
    let onClose: @MainActor @Sendable (OnboardingPresentation) -> Void

    @State private var currentStep: QuizFlashOnboardingStep = .welcome
    @State private var cardsTarget = AppPreferences.defaultDailyCardsGoal

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    private var steps: [QuizFlashOnboardingStep] {
        QuizFlashOnboardingStep.allCases
    }

    private var stepIndex: Int {
        steps.firstIndex(of: currentStep) ?? 0
    }

    var body: some View {
        ZStack(alignment: .top) {
            themeManager.screenBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                progressHeader

                TabView(selection: $currentStep) {
                    ForEach(steps) { step in
                        onboardingPage(for: step)
                            .tag(step)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(animation, value: currentStep)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footerControls
            }
            .frame(maxWidth: maxContentWidth)
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)

            if presentation.allowsClose {
                closeButton
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: syncStateFromPreferences)
    }

    // MARK: - Chrome

    private var progressHeader: some View {
        HStack(spacing: 7) {
            ForEach(steps.indices, id: \.self) { index in
                Capsule()
                    .fill(index <= stepIndex ? themeManager.accentColor.color : themeManager.textPrimary.opacity(0.16))
                    .frame(maxWidth: .infinity)
                    .frame(height: 5)
            }
        }
        .padding(.top, UIConstants.Spacing.standard)
    }

    private var footerControls: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            Button {
                withAnimation(animation) {
                    moveBackward()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
            }
            .tint(themeManager.textPrimary)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .opacity(stepIndex == 0 ? 0 : 1)
            .allowsHitTesting(stepIndex > 0)

            Button {
                if stepIndex == steps.count - 1 {
                    applyCurrentStep()
                    onComplete(presentation)
                    return
                }

                withAnimation(animation) {
                    applyCurrentStep()
                    moveForward()
                }
            } label: {
                Text(AppLocalization.string(stepIndex == steps.count - 1 ? "Get started" : "Continue", locale: locale))
                    .font(.headline.weight(.bold))
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .tint(themeManager.accentColor.color)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .padding(.top, UIConstants.Spacing.standard)
    }

    private var closeButton: some View {
        Button {
            onClose(presentation)
        } label: {
            Image(systemName: "xmark")
                .font(.headline.weight(.bold))
                .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
        }
        .tint(themeManager.textPrimary)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, UIConstants.Spacing.standard)
        .padding(.top, UIConstants.Spacing.standard)
    }

    // MARK: - Pages

    @ViewBuilder
    private func onboardingPage(for step: QuizFlashOnboardingStep) -> some View {
        VStack(spacing: UIConstants.Spacing.extraLarge) {
            pageTitle(step)

            switch step {
            case .welcome:
                welcomeContent
            case .zoneStyle:
                zoneStyleContent
            case .cardsTarget:
                cardsTargetContent
            case .textSize:
                textSizeContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pageTitle(_ step: QuizFlashOnboardingStep) -> some View {
        VStack(spacing: UIConstants.Spacing.medium) {
            Text(AppLocalization.string(step.titleKey, locale: locale))
                .font(.system(size: titleSize, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(themeManager.textPrimary)
                .minimumScaleFactor(0.76)
                .lineLimit(3)

            Text(AppLocalization.string(step.subtitleKey, locale: locale))
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(themeManager.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560)
        }
        .padding(.top, UIConstants.Spacing.extraLarge)
    }

    private var welcomeContent: some View {
        VStack(spacing: UIConstants.Spacing.standard) {
            featureLine("Onboarding feature: Library", valueKey: "Keep decks organized.")
            featureLine("Onboarding feature: Editor", valueKey: "Create and edit cards fast.")
            featureLine("Onboarding feature: Play", valueKey: "Review every day with a clear target.")
        }
        .frame(maxWidth: 560)
    }

    private func featureLine(_ titleKey: String, valueKey: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: UIConstants.Spacing.medium) {
            Circle()
                .fill(themeManager.accentColor.color)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.string(titleKey, locale: locale))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(themeManager.textPrimary)

                Text(AppLocalization.string(valueKey, locale: locale))
                    .font(.body.weight(.medium))
                    .foregroundStyle(themeManager.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, UIConstants.Spacing.medium)
    }

    private var zoneStyleContent: some View {
        VStack(spacing: UIConstants.Spacing.standard) {
            ForEach(AppZoneSurfaceStyle.allCases) { style in
                zoneStyleOption(style)
            }
        }
        .frame(maxWidth: 620)
    }

    private func zoneStyleOption(_ style: AppZoneSurfaceStyle) -> some View {
        Button {
            withAnimation(animation) {
                appPreferences.zoneSurfaceStyle = style
            }
        } label: {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                HStack(spacing: UIConstants.Spacing.small) {
                    Text(style.localizedTitle(locale: locale))
                        .font(.title2.weight(.black))
                        .foregroundStyle(themeManager.textPrimary)

                    Spacer(minLength: UIConstants.Spacing.standard)

                    Image(systemName: appPreferences.zoneSurfaceStyle == style ? "checkmark.circle.fill" : "circle")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(appPreferences.zoneSurfaceStyle == style ? themeManager.accentColor.color : themeManager.textSecondary)
                }

                ZoneStylePreview(style: style)
            }
            .padding(UIConstants.Spacing.large)
            .background(optionFill(isSelected: appPreferences.zoneSurfaceStyle == style), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(optionStroke(isSelected: appPreferences.zoneSurfaceStyle == style), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    private var cardsTargetContent: some View {
        VStack(spacing: UIConstants.Spacing.extraLarge) {
            VStack(spacing: UIConstants.Spacing.small) {
                Text(String(format: AppLocalization.string("%d cards per day", locale: locale), cardsTarget))
                    .font(.system(size: targetNumberSize, weight: .black, design: .rounded))
                    .foregroundStyle(themeManager.textPrimary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)

                Text(AppLocalization.string("This becomes your daily productivity target.", locale: locale))
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(themeManager.textSecondary)
            }

            HStack(spacing: UIConstants.Spacing.standard) {
                targetButton(systemName: "minus") {
                    updateCardsTarget(cardsTarget - AppPreferences.dailyCardsGoalStep)
                }

                Slider(
                    value: targetSliderValue,
                    in: Double(AppPreferences.dailyCardsGoalRange.lowerBound)...Double(AppPreferences.dailyCardsGoalRange.upperBound),
                    step: Double(AppPreferences.dailyCardsGoalStep)
                )
                .tint(themeManager.accentColor.color)
                .accessibilityLabel(AppLocalization.string("Cards Target", locale: locale))
                .onChange(of: cardsTarget) { _, newValue in
                    appPreferences.dailyCardsGoal = newValue
                }

                targetButton(systemName: "plus") {
                    updateCardsTarget(cardsTarget + AppPreferences.dailyCardsGoalStep)
                }
            }
        }
        .frame(maxWidth: 580)
        .onAppear {
            appPreferences.dailyCardsGoal = cardsTarget
        }
    }

    private var targetSliderValue: Binding<Double> {
        Binding(
            get: { Double(cardsTarget) },
            set: { updateCardsTarget(Int($0)) }
        )
    }

    private func targetButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.black))
                .frame(width: 46, height: 46)
        }
        .tint(themeManager.textPrimary)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
    }

    private var textSizeContent: some View {
        VStack(spacing: UIConstants.Spacing.large) {
            TextSizePreview(textSize: appPreferences.defaultTextSize)

            HStack(spacing: UIConstants.Spacing.small) {
                ForEach([FlashcardTextSize(step: 1), .normal, .large]) { size in
                    Button {
                        withAnimation(animation) {
                            appPreferences.defaultTextSize = size
                        }
                    } label: {
                        Text(size.localizedTitle(locale: locale))
                            .font(.callout.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .tint(appPreferences.defaultTextSize == size ? themeManager.accentColor.color : themeManager.textPrimary)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
            }

            HStack(spacing: UIConstants.Spacing.standard) {
                Text(AppLocalization.string("Text Size", locale: locale))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(themeManager.textSecondary)

                Slider(
                    value: textSizeSliderValue,
                    in: Double(FlashcardTextSize.minimumStep)...Double(FlashcardTextSize.maximumStep),
                    step: 1
                )
                .tint(themeManager.accentColor.color)

                Text("\(appPreferences.defaultTextSize.step)")
                    .font(.headline.weight(.black).monospacedDigit())
                    .foregroundStyle(themeManager.textPrimary)
                    .frame(width: 30)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: 620)
    }

    private var textSizeSliderValue: Binding<Double> {
        Binding(
            get: { Double(appPreferences.defaultTextSize.step) },
            set: { appPreferences.defaultTextSize = FlashcardTextSize(step: Int($0)) }
        )
    }

    // MARK: - Actions

    private func moveForward() {
        let nextIndex = min(stepIndex + 1, steps.count - 1)
        currentStep = steps[nextIndex]
    }

    private func moveBackward() {
        let previousIndex = max(stepIndex - 1, 0)
        currentStep = steps[previousIndex]
    }

    private func applyCurrentStep() {
        if currentStep == .cardsTarget {
            appPreferences.dailyCardsGoal = cardsTarget
        }
    }

    private func syncStateFromPreferences() {
        cardsTarget = appPreferences.dailyCardsGoal ?? AppPreferences.defaultDailyCardsGoal
        appPreferences.dailyCardsGoal = cardsTarget
    }

    private func updateCardsTarget(_ value: Int) {
        let clamped = min(
            max(value, AppPreferences.dailyCardsGoalRange.lowerBound),
            AppPreferences.dailyCardsGoalRange.upperBound
        )
        let step = AppPreferences.dailyCardsGoalStep
        cardsTarget = max(step, (clamped / step) * step)
        appPreferences.dailyCardsGoal = cardsTarget
    }

    // MARK: - Styling

    private func optionFill(isSelected: Bool) -> Color {
        isSelected ? themeManager.accentColor.color.opacity(0.16) : themeManager.textPrimary.opacity(0.06)
    }

    private func optionStroke(isSelected: Bool) -> Color {
        isSelected ? themeManager.accentColor.color.opacity(0.72) : themeManager.textPrimary.opacity(0.10)
    }

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.20) : .spring(duration: 0.38, bounce: 0.12)
    }

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular || UIConstants.isPad
    }

    private var maxContentWidth: CGFloat {
        isPadLayout ? 760 : .infinity
    }

    private var horizontalPadding: CGFloat {
        isPadLayout ? UIConstants.Spacing.extraLarge : UIConstants.Spacing.standard
    }

    private var topPadding: CGFloat {
        isPadLayout ? UIConstants.Spacing.large : UIConstants.Spacing.medium
    }

    private var bottomPadding: CGFloat {
        isPadLayout ? UIConstants.Spacing.extraLarge : UIConstants.Spacing.standard
    }

    private var titleSize: CGFloat {
        isPadLayout ? 58 : 42
    }

    private var targetNumberSize: CGFloat {
        isPadLayout ? 72 : 48
    }
}

// MARK: - Step

private enum QuizFlashOnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case zoneStyle
    case cardsTarget
    case textSize

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .welcome:
            return "Set up QuizFlash"
        case .zoneStyle:
            return "Choose your zone style"
        case .cardsTarget:
            return "Set your daily target"
        case .textSize:
            return "Pick your card text size"
        }
    }

    var subtitleKey: String {
        switch self {
        case .welcome:
            return "A few defaults make the editor, game, and Home screen feel right from the start."
        case .zoneStyle:
            return "This is how zones will look inside cards."
        case .cardsTarget:
            return "Choose how many cards you want to finish each day."
        case .textSize:
            return "This preview uses the same scale as the editor and play mode."
        }
    }
}

// MARK: - Previews

private struct ZoneStylePreview: View {
    @Environment(ThemeManager.self) private var themeManager

    let style: AppZoneSurfaceStyle

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack(spacing: UIConstants.Spacing.small) {
                previewZone(width: 94)
                previewZone(width: 54)
            }

            previewZone(width: 168)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(UIConstants.Spacing.medium)
        .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func previewZone(width: CGFloat) -> some View {
        let radius: CGFloat = style == .rounded ? 14 : 4
        let fillOpacity: Double = style == .rounded ? 0.18 : 0.04
        let strokeOpacity: Double = style == .rounded ? 0.46 : 0.16

        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(themeManager.accentColor.color.opacity(fillOpacity))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(themeManager.accentColor.color.opacity(strokeOpacity), lineWidth: style == .rounded ? 1.4 : 0.8)
            }
            .frame(width: width, height: 42)
    }
}

private struct TextSizePreview: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppPreferences.self) private var appPreferences

    let textSize: FlashcardTextSize

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text(AppLocalization.string("Editor preview", locale: appPreferences.resolvedLocale))
                .font(.caption.weight(.bold))
                .foregroundStyle(themeManager.textSecondary)
                .textCase(.uppercase)

            Text(AppLocalization.string("What is active recall?", locale: appPreferences.resolvedLocale))
                .font(.system(size: previewFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.70)

            Text(AppLocalization.string("Answer from memory before checking the card.", locale: appPreferences.resolvedLocale))
                .font(.system(size: max(17, previewFontSize * 0.62), weight: .medium, design: .rounded))
                .foregroundStyle(themeManager.textSecondary)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .leading)
        .padding(UIConstants.Spacing.large)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(themeManager.textPrimary.opacity(0.10), lineWidth: 1)
        }
    }

    private var previewFontSize: CGFloat {
        22 * CGFloat(textSize.playModeScale)
    }
}

#Preview {
    QuizFlashOnboardingView(
        presentation: .preview(UUID()),
        onComplete: { _ in },
        onClose: { _ in }
    )
    .environment(AppPreferences.shared)
    .environment(ThemeManager.shared)
}

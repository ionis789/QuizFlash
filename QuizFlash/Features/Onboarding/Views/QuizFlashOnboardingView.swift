//
//  QuizFlashOnboardingView.swift
//  QuizFlash
//
//  Created by Ion Socol on 03.07.2026.
//

import SwiftUI
import UIKit

// MARK: - QuizFlash Onboarding View

struct QuizFlashOnboardingView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let presentation: OnboardingPresentation
    let onComplete: @MainActor @Sendable (OnboardingPresentation) -> Void
    let onClose: @MainActor @Sendable (OnboardingPresentation) -> Void

    @State private var currentIndex = 0
    @State private var cardsTarget = AppPreferences.defaultDailyCardsGoal

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    private var items: [QuizFlashOnboardingItem] {
        QuizFlashOnboardingItem.defaultItems
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            themeManager.screenBackground
                .ignoresSafeArea()

            onboardingDisplayView
                .compositingGroup()
                .scaleEffect(
                    items[currentIndex].zoomScale,
                    anchor: items[currentIndex].zoomAnchor
                )
                .frame(maxWidth: maxDisplayWidth)
                .padding(.top, topContentPadding)
                .padding(.horizontal, horizontalContentPadding)
                .padding(.bottom, bottomControlsHeight + displayBottomSpacing)

            bottomControls

            if presentation.allowsClose {
                closeButton
            }

            backButton
        }
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
        .onAppear(perform: syncStateFromPreferences)
    }

    // MARK: - Content

    private var onboardingDisplayView: some View {
        let frameMetrics = deviceFrameMetrics
        let shape = RoundedRectangle(cornerRadius: frameMetrics.cornerRadius, style: .continuous)

        return GeometryReader { proxy in
            let size = proxy.size

            Rectangle()
                .fill(.black)

            HStack(spacing: UIConstants.Spacing.medium) {
                ForEach(items.indices, id: \.self) { index in
                    onboardingPage(for: items[index])
                        .frame(width: size.width, height: size.height)
                }
            }
            .offset(x: -CGFloat(currentIndex) * (size.width + UIConstants.Spacing.medium))
        }
        .clipShape(shape)
        .overlay {
            ZStack {
                shape
                    .stroke(.white.opacity(frameMetrics.highlightOpacity), lineWidth: frameMetrics.highlightLineWidth)

                shape
                    .stroke(.black, lineWidth: frameMetrics.outerLineWidth)

                shape
                    .stroke(.black, lineWidth: frameMetrics.innerLineWidth)
                    .padding(frameMetrics.innerPadding)
            }
            .padding(frameMetrics.overlayPadding)
        }
        .aspectRatio(0.75, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func onboardingPage(for item: QuizFlashOnboardingItem) -> some View {
        switch item.kind {
        case .welcome:
            WelcomeOnboardingPage()
        case .zoneStyle:
            ZoneStyleOnboardingPage(selectedStyle: zoneSurfaceStyleBinding)
        case .cardsTarget:
            CardsTargetOnboardingPage(cardsTarget: $cardsTarget)
        case .textSize:
            TextSizeOnboardingPage(textSize: defaultTextSizeBinding)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: UIConstants.Spacing.medium) {
            textContent
            indicatorView
            continueButton
        }
        .padding(.top, UIConstants.Spacing.large)
        .padding(.horizontal, UIConstants.Spacing.standard)
        .frame(maxWidth: bottomControlsMaxWidth)
        .frame(height: bottomControlsHeight)
        .padding(.bottom, bottomControlsBottomPadding)
    }

    private var textContent: some View {
        GeometryReader { proxy in
            let size = proxy.size

            HStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    let isActive = currentIndex == index

                    VStack(spacing: UIConstants.Spacing.small) {
                        Text(AppLocalization.string(item.titleKey, locale: locale))
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .foregroundStyle(.white)

                        Text(AppLocalization.string(item.subtitleKey, locale: locale))
                            .font(.callout.weight(.medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.80))
                    }
                    .frame(width: size.width)
                    .compositingGroup()
                    .blur(radius: isActive ? 0 : 28)
                    .opacity(isActive ? 1 : 0)
                }
            }
            .offset(x: -CGFloat(currentIndex) * size.width)
        }
    }

    private var indicatorView: some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                let isActive = currentIndex == index

                Capsule()
                    .fill(.white.opacity(isActive ? 1 : 0.38))
                    .frame(width: isActive ? 25 : 6, height: 6)
            }
        }
        .padding(.bottom, UIConstants.Spacing.tiny)
    }

    private var continueButton: some View {
        Button {
            applyCurrentStep()

            if currentIndex == items.count - 1 {
                onComplete(presentation)
                return
            }

            withAnimation(animation) {
                currentIndex = min(currentIndex + 1, items.count - 1)
            }
        } label: {
            Text(AppLocalization.string(currentIndex == items.count - 1 ? "Get started" : "Continue", locale: locale))
                .fontWeight(.medium)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .tint(themeManager.accentColor.color)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .padding(.horizontal, UIConstants.Spacing.huge)
    }

    private var backButton: some View {
        Button {
            withAnimation(animation) {
                currentIndex = max(currentIndex - 1, 0)
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.title3)
                .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
        }
        .tint(.white)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .opacity(currentIndex == 0 ? 0 : 1)
        .allowsHitTesting(currentIndex > 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, UIConstants.Spacing.standard)
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
        .tint(.white)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, UIConstants.Spacing.standard)
        .padding(.top, UIConstants.Spacing.standard)
    }

    // MARK: - Actions

    private func syncStateFromPreferences() {
        cardsTarget = appPreferences.dailyCardsGoal ?? AppPreferences.defaultDailyCardsGoal
        appPreferences.dailyCardsGoal = cardsTarget
    }

    private func applyCurrentStep() {
        guard items[currentIndex].kind == .cardsTarget else { return }
        appPreferences.dailyCardsGoal = cardsTarget
    }

    // MARK: - Bindings

    private var zoneSurfaceStyleBinding: Binding<AppZoneSurfaceStyle> {
        Binding(
            get: { appPreferences.zoneSurfaceStyle },
            set: { appPreferences.zoneSurfaceStyle = $0 }
        )
    }

    private var defaultTextSizeBinding: Binding<FlashcardTextSize> {
        Binding(
            get: { appPreferences.defaultTextSize },
            set: { appPreferences.defaultTextSize = $0 }
        )
    }

    // MARK: - Metrics

    private var isPadLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular
    }

    private var maxDisplayWidth: CGFloat? {
        isPadLayout ? 920 : nil
    }

    private var topContentPadding: CGFloat {
        isPadLayout ? 48 : 35
    }

    private var horizontalContentPadding: CGFloat {
        isPadLayout ? 70 : 30
    }

    private var displayBottomSpacing: CGFloat {
        isPadLayout ? 70 : 10
    }

    private var bottomControlsHeight: CGFloat {
        isPadLayout ? 230 : 210
    }

    private var bottomControlsMaxWidth: CGFloat? {
        isPadLayout ? 560 : nil
    }

    private var bottomControlsBottomPadding: CGFloat {
        isPadLayout ? 28 : 0
    }

    private var deviceFrameMetrics: QuizFlashOnboardingDeviceFrameMetrics {
        QuizFlashOnboardingDeviceFrameMetrics(
            cornerRadius: isPadLayout ? 44 : 34,
            highlightLineWidth: 4,
            outerLineWidth: 5,
            innerLineWidth: 4,
            innerPadding: 5,
            overlayPadding: -6,
            highlightOpacity: 0.85
        )
    }

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.22) : .interpolatingSpring(duration: 0.65, bounce: 0, initialVelocity: 0)
    }
}

// MARK: - Item

private struct QuizFlashOnboardingItem: Identifiable, Hashable {
    let id: Int
    let titleKey: String
    let subtitleKey: String
    let kind: QuizFlashOnboardingPageKind
    var zoomScale: CGFloat = 1
    var zoomAnchor: UnitPoint = .center

    static let defaultItems: [QuizFlashOnboardingItem] = [
        .init(
            id: 0,
            titleKey: "Set up QuizFlash",
            subtitleKey: "A few defaults make the editor, game, and Home screen feel right from the start.",
            kind: .welcome
        ),
        .init(
            id: 1,
            titleKey: "Choose your zone style",
            subtitleKey: "This is how zones will look inside cards.",
            kind: .zoneStyle
        ),
        .init(
            id: 2,
            titleKey: "Set your daily target",
            subtitleKey: "Choose how many cards you want to finish each day.",
            kind: .cardsTarget
        ),
        .init(
            id: 3,
            titleKey: "Pick your card text size",
            subtitleKey: "This preview uses the same scale as the editor and play mode.",
            kind: .textSize
        )
    ]
}

private enum QuizFlashOnboardingPageKind: Hashable {
    case welcome
    case zoneStyle
    case cardsTarget
    case textSize
}

// MARK: - Pages

private struct WelcomeOnboardingPage: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            Text(AppLocalization.string("Set up QuizFlash", locale: appPreferences.resolvedLocale))
                .font(.system(size: 48, weight: .black, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                featureLine("Onboarding feature: Library", valueKey: "Keep decks organized.")
                featureLine("Onboarding feature: Editor", valueKey: "Create and edit cards fast.")
                featureLine("Onboarding feature: Play", valueKey: "Review every day with a clear target.")
            }
        }
        .padding(.horizontal, UIConstants.Spacing.extraLarge)
        .padding(.vertical, UIConstants.Spacing.huge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func featureLine(_ titleKey: String, valueKey: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(AppLocalization.string(titleKey, locale: appPreferences.resolvedLocale))
                .font(.title3.weight(.black))
                .foregroundStyle(themeManager.textPrimary)

            Text(AppLocalization.string(valueKey, locale: appPreferences.resolvedLocale))
                .font(.body.weight(.medium))
                .foregroundStyle(themeManager.textSecondary)
        }
    }
}

private struct ZoneStyleOnboardingPage: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    @Binding var selectedStyle: AppZoneSurfaceStyle

    var body: some View {
        VStack(spacing: UIConstants.Spacing.standard) {
            ForEach(AppZoneSurfaceStyle.allCases) { style in
                Button {
                    selectedStyle = style
                } label: {
                    VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                        HStack(spacing: UIConstants.Spacing.small) {
                            Text(style.localizedTitle(locale: appPreferences.resolvedLocale))
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundStyle(themeManager.textPrimary)

                            Spacer(minLength: UIConstants.Spacing.standard)

                            Image(systemName: selectedStyle == style ? "checkmark.circle.fill" : "circle")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(selectedStyle == style ? themeManager.accentColor.color : themeManager.textSecondary)
                        }

                        ZoneStylePreview(style: style)
                    }
                    .padding(UIConstants.Spacing.large)
                    .background(
                        selectedStyle == style
                            ? themeManager.accentColor.color.opacity(0.16)
                            : themeManager.textPrimary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                selectedStyle == style
                                    ? themeManager.accentColor.color.opacity(0.72)
                                    : themeManager.textPrimary.opacity(0.10),
                                lineWidth: 1.4
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, UIConstants.Spacing.extraLarge)
        .padding(.vertical, UIConstants.Spacing.huge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CardsTargetOnboardingPage: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    @Binding var cardsTarget: Int

    private var tickUpperBound: Int {
        AppPreferences.dailyCardsGoalRange.upperBound / AppPreferences.dailyCardsGoalStep
    }

    private var tickSelection: Int {
        min(
            max(cardsTarget / AppPreferences.dailyCardsGoalStep, 1),
            tickUpperBound
        )
    }

    var body: some View {
        VStack(spacing: UIConstants.Spacing.extraLarge) {
            VStack(spacing: UIConstants.Spacing.small) {
                Text(String(
                    format: AppLocalization.string("%d cards per day", locale: appPreferences.resolvedLocale),
                    locale: appPreferences.resolvedLocale,
                    cardsTarget
                ))
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(themeManager.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .contentTransition(.numericText())

                Text(AppLocalization.string("This becomes your daily productivity target.", locale: appPreferences.resolvedLocale))
                    .font(.headline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(themeManager.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TickValuePicker(
                value: tickSelection,
                range: 1 ... tickUpperBound,
                onChange: setTickSelection,
                isCompact: true
            ) { value in
                "\(value * AppPreferences.dailyCardsGoalStep)"
            }
        }
        .padding(.horizontal, UIConstants.Spacing.extraLarge)
        .padding(.vertical, UIConstants.Spacing.huge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setTickSelection(_ selection: Int) {
        cardsTarget = min(selection, tickUpperBound) * AppPreferences.dailyCardsGoalStep
        appPreferences.dailyCardsGoal = cardsTarget
    }
}

private struct TextSizeOnboardingPage: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    @Binding var textSize: FlashcardTextSize

    var body: some View {
        VStack(spacing: UIConstants.Spacing.large) {
            TextSizePreview(textSize: textSize)

            TickValuePicker(
                value: textSize.step,
                range: FlashcardTextSize.minimumStep ... FlashcardTextSize.maximumStep,
                onChange: { newValue in
                    textSize = FlashcardTextSize(step: newValue)
                },
                isCompact: true
            ) { value in
                "\(value)"
            }
            .padding(.horizontal, UIConstants.Spacing.small)

            Text(textSize.localizedTitle(locale: appPreferences.resolvedLocale))
                .font(.title3.weight(.black))
                .foregroundStyle(themeManager.accentColor.color)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, UIConstants.Spacing.extraLarge)
        .padding(.vertical, UIConstants.Spacing.huge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .padding(UIConstants.Spacing.large)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(themeManager.textPrimary.opacity(0.10), lineWidth: 1)
        }
    }

    private var previewFontSize: CGFloat {
        22 * CGFloat(textSize.playModeScale)
    }
}

// MARK: - Metrics

private struct QuizFlashOnboardingDeviceFrameMetrics {
    let cornerRadius: CGFloat
    let highlightLineWidth: CGFloat
    let outerLineWidth: CGFloat
    let innerLineWidth: CGFloat
    let innerPadding: CGFloat
    let overlayPadding: CGFloat
    let highlightOpacity: CGFloat
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

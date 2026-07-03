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
                        .scaleEffect(pageScale(for: index))
                        .opacity(pageOpacity(for: index))
                        .frame(width: size.width, height: size.height)
                }
            }
            .offset(x: -CGFloat(currentIndex) * (size.width + UIConstants.Spacing.medium))
            .animation(animation, value: currentIndex)
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
        case .latexSupport:
            LatexSupportOnboardingPage()
        case .cardsTarget:
            CardsTargetOnboardingPage(cardsTarget: $cardsTarget)
        case .textSize:
            TextSizeOnboardingPage(textSize: defaultTextSizeBinding)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: UIConstants.Spacing.medium) {
            if items[currentIndex].kind == .welcome {
                Spacer(minLength: 0)
            } else {
                textContent
            }
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

    private func pageScale(for index: Int) -> CGFloat {
        index == currentIndex ? 1 : 0.88
    }

    private func pageOpacity(for index: Int) -> Double {
        index == currentIndex ? 1 : 0.74
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
            titleKey: "Welcome to QuizFlash",
            subtitleKey: "Set your defaults in a few quick steps.",
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
            titleKey: "Full LaTeX support",
            subtitleKey: "Generate or request cards with LaTeX symbols without friction.",
            kind: .latexSupport
        ),
        .init(
            id: 3,
            titleKey: "Set your daily target",
            subtitleKey: "Choose how many cards you want to finish each day.",
            kind: .cardsTarget
        ),
        .init(
            id: 4,
            titleKey: "Pick your card text size",
            subtitleKey: "This preview uses the same scale as the editor and play mode.",
            kind: .textSize
        )
    ]
}

private enum QuizFlashOnboardingPageKind: Hashable {
    case welcome
    case zoneStyle
    case latexSupport
    case cardsTarget
    case textSize
}

// MARK: - Pages

private struct WelcomeOnboardingPage: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(spacing: UIConstants.Spacing.huge) {
            Text(AppLocalization.string("Welcome to QuizFlash", locale: appPreferences.resolvedLocale))
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.58)

            WelcomeCardForms()
        }
        .padding(.horizontal, UIConstants.Spacing.extraLarge)
        .padding(.vertical, UIConstants.Spacing.huge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct WelcomeCardForms: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ThemeManager.self) private var themeManager

    @State private var phase: WelcomeCardDemoPhase = .resting

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, 520)
            let height = max(proxy.size.height, 340)
            let cardWidth = min(width * 0.45, 240)
            let cardHeight = cardWidth * 1.42
            let quizWidth = min(width * 0.72, 360)
            let quizHeight = min(height * 0.72, 292)

            ZStack {
                if phase.showsTapRipple && !reduceMotion {
                    tapRipple(size: cardWidth * 0.32)
                        .offset(x: cardWidth * 0.13, y: cardHeight * 0.06)
                }

                demoCard(width: cardWidth, height: cardHeight)
                    .rotation3DEffect(.degrees(phase.cardFlipDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                    .scaleEffect(phase.cardScale)
                    .rotationEffect(.degrees(phase.cardTiltDegrees))
                    .offset(x: phase.cardOffsetX(cardWidth: cardWidth, containerWidth: width), y: phase.cardOffsetY)
                    .opacity(phase.cardOpacity)
                    .shadow(color: themeManager.accentColor.color.opacity(0.20), radius: 26, y: 14)

                quizDemo(width: quizWidth, height: quizHeight)
                    .scaleEffect(phase.quizScale)
                    .offset(y: phase.quizOffsetY)
                    .opacity(phase.quizOpacity)

                if phase.showsHand && !reduceMotion {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(themeManager.textPrimary.opacity(0.92))
                        .shadow(color: .black.opacity(0.34), radius: 12, y: 8)
                        .scaleEffect(phase.handScale)
                        .rotationEffect(.degrees(phase.handRotationDegrees))
                        .offset(
                            phase.handOffset(
                                cardWidth: cardWidth,
                                cardHeight: cardHeight,
                                quizWidth: quizWidth,
                                quizHeight: quizHeight
                            )
                        )
                        .accessibilityHidden(true)
                }
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .task(id: reduceMotion) {
            guard !reduceMotion else {
                phase = .resting
                return
            }

            await runDemoLoop()
        }
    }

    @MainActor
    private func runDemoLoop() async {
        phase = .resting

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(650))
            await animate(to: .tapApproach, duration: 0.70)
            try? await Task.sleep(for: .milliseconds(220))
            await animate(to: .tapPress, duration: 0.18)
            try? await Task.sleep(for: .milliseconds(180))
            await animate(to: .flipped, duration: 0.62)
            try? await Task.sleep(for: .milliseconds(680))
            await animate(to: .swipeReady, duration: 0.42)
            try? await Task.sleep(for: .milliseconds(180))
            await animate(to: .swiping, duration: 0.86)
            try? await Task.sleep(for: .milliseconds(180))
            await animate(to: .quizAppearing, duration: 0.56)
            try? await Task.sleep(for: .milliseconds(420))
            await animate(to: .quizWrongApproach, duration: 0.48)
            try? await Task.sleep(for: .milliseconds(160))
            await animate(to: .quizWrongPress, duration: 0.14)
            try? await Task.sleep(for: .milliseconds(120))
            await animate(to: .quizWrongResult, duration: 0.34)
            try? await Task.sleep(for: .milliseconds(640))
            await animate(to: .quizCorrectApproach, duration: 0.50)
            try? await Task.sleep(for: .milliseconds(160))
            await animate(to: .quizCorrectPress, duration: 0.14)
            try? await Task.sleep(for: .milliseconds(120))
            await animate(to: .quizCorrectResult, duration: 0.38)
            try? await Task.sleep(for: .milliseconds(850))

            await animate(to: .quizLeaving, duration: 0.32)
            try? await Task.sleep(for: .milliseconds(210))

            withTransaction(Transaction(animation: nil)) {
                phase = .cardReturnHidden
            }
            await animate(to: .resting, duration: 0.48)
        }
    }

    @MainActor
    private func animate(to newPhase: WelcomeCardDemoPhase, duration: TimeInterval) async {
        guard !Task.isCancelled else { return }

        withAnimation(.smooth(duration: duration, extraBounce: 0.03)) {
            phase = newPhase
        }
    }

    private func demoCard(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            cardFace(width: width, height: height, isBack: false)
                .opacity(phase.showsBackFace ? 0 : 1)

            cardFace(width: width, height: height, isBack: true)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                .opacity(phase.showsBackFace ? 1 : 0)
        }
        .frame(width: width, height: height)
    }

    private func cardFace(width: CGFloat, height: CGFloat, isBack: Bool) -> some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(themeManager.accentColor.color.opacity(isBack ? 0.20 : 0.16))
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(themeManager.accentColor.color.opacity(isBack ? 0.62 : 0.48), lineWidth: 1.4)
            }
            .overlay {
                if isBack {
                    VStack(spacing: 16) {
                        cardLine(width: width * 0.52, height: 15, opacity: 0.50)
                        cardLine(width: width * 0.66, height: 12, opacity: 0.34)
                        cardLine(width: width * 0.48, height: 12, opacity: 0.28)
                        Spacer(minLength: 0)
                        cardPill(width: width * 0.36)
                    }
                    .padding(.top, 44)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                } else {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack(spacing: 10) {
                            cardLine(width: width * 0.46, height: 15, opacity: 0.52)
                            cardLine(width: width * 0.22, height: 15, opacity: 0.34)
                        }

                        cardLine(width: width * 0.72, height: 12, opacity: 0.42)
                        cardLine(width: width * 0.56, height: 12, opacity: 0.30)
                        cardLine(width: width * 0.38, height: 12, opacity: 0.22)

                        Spacer(minLength: 0)

                        HStack(spacing: 9) {
                            cardPill(width: width * 0.24)
                            cardPill(width: width * 0.18)
                            cardPill(width: width * 0.26)
                        }
                    }
                    .padding(24)
                }
            }
    }

    private func tapRipple(size: CGFloat) -> some View {
        Circle()
            .strokeBorder(themeManager.accentColor.color.opacity(0.55), lineWidth: 2)
            .frame(width: size, height: size)
            .scaleEffect(phase == .tapPress ? 1.18 : 0.72)
            .opacity(phase == .tapPress ? 0.55 : 0)
    }

    private func quizDemo(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                cardLine(width: width * 0.62, height: 13, opacity: 0.52)
                cardLine(width: width * 0.78, height: 11, opacity: 0.38)
                cardLine(width: width * 0.45, height: 11, opacity: 0.26)
            }
            .padding(.bottom, 3)

            VStack(spacing: 10) {
                quizAnswerRow(width: width, index: 0, state: phase.answerState(for: 0))
                quizAnswerRow(width: width, index: 1, state: phase.answerState(for: 1))
                quizAnswerRow(width: width, index: 2, state: phase.answerState(for: 2))
            }
        }
        .frame(width: width, height: height, alignment: .center)
    }

    private func quizAnswerRow(width: CGFloat, index: Int, state: WelcomeQuizAnswerState) -> some View {
        let isWrong = state == .wrong
        let isCorrect = state == .correct
        let color: Color = if isWrong {
            .red
        } else if isCorrect {
            .green
        } else {
            themeManager.accentColor.color
        }

        return HStack(spacing: 10) {
            Circle()
                .fill(color.opacity(isWrong || isCorrect ? 0.95 : 0.28))
                .frame(width: 15, height: 15)
                .overlay {
                    if isWrong {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(.white)
                    } else if isCorrect {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(.white)
                    }
                }

            VStack(alignment: .leading, spacing: 7) {
                cardLine(width: width * (index == 1 ? 0.43 : 0.52), height: 9, opacity: state == .neutral ? 0.34 : 0.54)
                cardLine(width: width * (index == 2 ? 0.38 : 0.47), height: 8, opacity: state == .neutral ? 0.22 : 0.34)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(
            color.opacity(isWrong || isCorrect ? 0.16 : 0.055),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(color.opacity(isWrong || isCorrect ? 0.70 : 0.18), lineWidth: isWrong || isCorrect ? 1.5 : 1)
        }
        .scaleEffect(phase.pressedAnswerIndex == index ? 0.965 : (isCorrect ? 1.025 : 1), anchor: .center)
        .offset(x: isWrong ? phase.wrongAnswerOffset : 0)
    }

    private func cardLine(width: CGFloat, height: CGFloat, opacity: Double) -> some View {
        Capsule()
            .fill(themeManager.textPrimary.opacity(opacity))
            .frame(width: width, height: height)
    }

    private func cardPill(width: CGFloat) -> some View {
        Capsule()
            .fill(themeManager.accentColor.color.opacity(0.34))
            .frame(width: width, height: 18)
    }
}

private enum WelcomeCardDemoPhase: Equatable {
    case resting
    case tapApproach
    case tapPress
    case flipped
    case swipeReady
    case swiping
    case quizAppearing
    case quizWrongApproach
    case quizWrongPress
    case quizWrongResult
    case quizCorrectApproach
    case quizCorrectPress
    case quizCorrectResult
    case quizLeaving
    case cardReturnHidden

    var showsHand: Bool {
        switch self {
        case .tapApproach,
             .tapPress,
             .flipped,
             .swipeReady,
             .swiping,
             .quizWrongApproach,
             .quizWrongPress,
             .quizWrongResult,
             .quizCorrectApproach,
             .quizCorrectPress,
             .quizCorrectResult:
            true
        case .resting, .quizAppearing, .quizLeaving, .cardReturnHidden:
            false
        }
    }

    var showsTapRipple: Bool {
        self == .tapPress
    }

    var showsBackFace: Bool {
        switch self {
        case .flipped, .swipeReady, .swiping:
            true
        case .resting,
             .tapApproach,
             .tapPress,
             .quizAppearing,
             .quizWrongApproach,
             .quizWrongPress,
             .quizWrongResult,
             .quizCorrectApproach,
             .quizCorrectPress,
             .quizCorrectResult,
             .quizLeaving,
             .cardReturnHidden:
            false
        }
    }

    var cardFlipDegrees: Double {
        showsBackFace ? 180 : 0
    }

    var cardScale: CGFloat {
        switch self {
        case .tapPress:
            0.975
        case .swiping:
            0.92
        case .cardReturnHidden:
            0.94
        case .resting,
             .tapApproach,
             .flipped,
             .swipeReady,
             .quizAppearing,
             .quizWrongApproach,
             .quizWrongPress,
             .quizWrongResult,
             .quizCorrectApproach,
             .quizCorrectPress,
             .quizCorrectResult,
             .quizLeaving:
            1
        }
    }

    var cardTiltDegrees: Double {
        self == .swiping ? 8 : 0
    }

    var cardOpacity: Double {
        switch self {
        case .quizAppearing,
             .quizWrongApproach,
             .quizWrongPress,
             .quizWrongResult,
             .quizCorrectApproach,
             .quizCorrectPress,
             .quizCorrectResult,
             .quizLeaving,
             .cardReturnHidden:
            0
        case .resting, .tapApproach, .tapPress, .flipped, .swipeReady, .swiping:
            1
        }
    }

    var cardOffsetY: CGFloat {
        self == .cardReturnHidden ? 12 : 0
    }

    var quizOpacity: Double {
        switch self {
        case .quizAppearing,
             .quizWrongApproach,
             .quizWrongPress,
             .quizWrongResult,
             .quizCorrectApproach,
             .quizCorrectPress,
             .quizCorrectResult:
            1
        case .quizLeaving:
            0
        case .resting, .tapApproach, .tapPress, .flipped, .swipeReady, .swiping, .cardReturnHidden:
            0
        }
    }

    var quizScale: CGFloat {
        switch self {
        case .quizAppearing:
            1
        case .quizWrongPress, .quizCorrectPress:
            0.992
        case .quizLeaving:
            0.965
        case .quizWrongApproach,
             .quizWrongResult,
             .quizCorrectApproach,
             .quizCorrectResult:
            1
        case .resting, .tapApproach, .tapPress, .flipped, .swipeReady, .swiping, .cardReturnHidden:
            0.94
        }
    }

    var quizOffsetY: CGFloat {
        switch self {
        case .quizLeaving:
            -18
        case .resting, .tapApproach, .tapPress, .flipped, .swipeReady, .swiping, .cardReturnHidden:
            20
        case .quizAppearing,
             .quizWrongApproach,
             .quizWrongPress,
             .quizWrongResult,
             .quizCorrectApproach,
             .quizCorrectPress,
             .quizCorrectResult:
            0
        }
    }

    var handScale: CGFloat {
        switch self {
        case .tapPress, .quizWrongPress, .quizCorrectPress:
            0.88
        case .swiping:
            0.96
        case .resting,
             .tapApproach,
             .flipped,
             .swipeReady,
             .quizAppearing,
             .quizWrongApproach,
             .quizWrongResult,
             .quizCorrectApproach,
             .quizCorrectResult,
             .quizLeaving,
             .cardReturnHidden:
            1
        }
    }

    var handRotationDegrees: Double {
        switch self {
        case .swiping:
            -10
        case .quizWrongApproach,
             .quizWrongPress,
             .quizWrongResult,
             .quizCorrectApproach,
             .quizCorrectPress,
             .quizCorrectResult:
            -14
        case .resting, .tapApproach, .tapPress, .flipped, .swipeReady, .quizAppearing, .quizLeaving, .cardReturnHidden:
            -18
        }
    }

    var pressedAnswerIndex: Int? {
        switch self {
        case .quizWrongPress:
            0
        case .quizCorrectPress:
            1
        case .resting,
             .tapApproach,
             .tapPress,
             .flipped,
             .swipeReady,
             .swiping,
             .quizAppearing,
             .quizWrongApproach,
             .quizWrongResult,
             .quizCorrectApproach,
             .quizCorrectResult,
             .quizLeaving,
             .cardReturnHidden:
            nil
        }
    }

    var wrongAnswerOffset: CGFloat {
        switch self {
        case .quizWrongResult:
            7
        case .resting,
             .tapApproach,
             .tapPress,
             .flipped,
             .swipeReady,
             .swiping,
             .quizAppearing,
             .quizWrongApproach,
             .quizWrongPress,
             .quizCorrectApproach,
             .quizCorrectPress,
             .quizCorrectResult,
             .quizLeaving,
             .cardReturnHidden:
            0
        }
    }

    func answerState(for index: Int) -> WelcomeQuizAnswerState {
        switch self {
        case .quizWrongResult, .quizCorrectApproach, .quizCorrectPress, .quizCorrectResult:
            if index == 0 {
                return .wrong
            }
            if index == 1, self == .quizCorrectResult {
                return .correct
            }
            return .neutral
        case .resting,
             .tapApproach,
             .tapPress,
             .flipped,
             .swipeReady,
             .swiping,
             .quizAppearing,
             .quizWrongApproach,
             .quizWrongPress,
             .quizLeaving,
             .cardReturnHidden:
            return .neutral
        }
    }

    func cardOffsetX(cardWidth: CGFloat, containerWidth: CGFloat) -> CGFloat {
        switch self {
        case .swiping:
            (containerWidth * 0.5) + (cardWidth * 0.72)
        case .quizAppearing,
             .quizWrongApproach,
             .quizWrongPress,
             .quizWrongResult,
             .quizCorrectApproach,
             .quizCorrectPress,
             .quizCorrectResult,
             .quizLeaving:
            (containerWidth * 0.5) + (cardWidth * 0.86)
        case .resting, .tapApproach, .tapPress, .flipped, .swipeReady, .cardReturnHidden:
            0
        }
    }

    func handOffset(cardWidth: CGFloat, cardHeight: CGFloat, quizWidth: CGFloat, quizHeight: CGFloat) -> CGSize {
        switch self {
        case .tapApproach:
            CGSize(width: cardWidth * 0.44, height: cardHeight * 0.34)
        case .tapPress:
            CGSize(width: cardWidth * 0.20, height: cardHeight * 0.10)
        case .flipped:
            CGSize(width: cardWidth * 0.28, height: cardHeight * 0.20)
        case .swipeReady:
            CGSize(width: cardWidth * 0.08, height: cardHeight * 0.18)
        case .swiping:
            CGSize(width: cardWidth * 1.55, height: cardHeight * 0.05)
        case .quizWrongApproach:
            CGSize(width: quizWidth * 0.40, height: quizHeight * 0.12)
        case .quizWrongPress, .quizWrongResult:
            CGSize(width: quizWidth * 0.08, height: -quizHeight * 0.03)
        case .quizCorrectApproach:
            CGSize(width: quizWidth * 0.40, height: quizHeight * 0.34)
        case .quizCorrectPress, .quizCorrectResult:
            CGSize(width: quizWidth * 0.08, height: quizHeight * 0.18)
        case .resting, .quizAppearing, .quizLeaving, .cardReturnHidden:
            CGSize(width: cardWidth * 0.58, height: cardHeight * 0.42)
        }
    }
}

private enum WelcomeQuizAnswerState {
    case neutral
    case wrong
    case correct
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

                        OnboardingGameCardPreview(
                            style: style,
                            textSize: appPreferences.defaultTextSize,
                            sample: .zoneStyle
                        )
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

private struct LatexSupportOnboardingPage: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            Text(AppLocalization.string("Full LaTeX support", locale: appPreferences.resolvedLocale))
                .font(.system(size: 46, weight: .black, design: .rounded))
                .foregroundStyle(themeManager.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.68)

            Text(AppLocalization.string("Generate or request cards with LaTeX symbols without friction.", locale: appPreferences.resolvedLocale))
                .font(.title3.weight(.medium))
                .foregroundStyle(themeManager.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            OnboardingGameCardPreview(
                style: appPreferences.zoneSurfaceStyle,
                textSize: appPreferences.defaultTextSize,
                sample: .latex
            )
        }
        .padding(.horizontal, UIConstants.Spacing.extraLarge)
        .padding(.vertical, UIConstants.Spacing.huge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
            OnboardingGameCardPreview(
                style: appPreferences.zoneSurfaceStyle,
                textSize: textSize,
                sample: .textSize
            )

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

// MARK: - Real Card Preview

private struct OnboardingGameCardPreview: View {
    @Environment(AppPreferences.self) private var appPreferences

    let style: AppZoneSurfaceStyle
    let textSize: FlashcardTextSize
    let sample: OnboardingGameCardSample

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - 28, 1)

            QuizPlaybackZoneContent(
                zone: sample.zone(locale: appPreferences.resolvedLocale),
                fontScale: CGFloat(textSize.playModeScale),
                availableWidth: contentWidth,
                centersLeafBlocks: true,
                showsZoneSurfaces: style.showsZoneSurfaces,
                zoneHighlightStrokeStyle: StrokeStyle(lineWidth: style == .rounded ? 1.6 : 1.0),
                showsLayoutDebug: false
            )
            .frame(width: contentWidth, alignment: .center)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, minHeight: sample.minimumHeight)
        .background(
            Color(red: 0.068, green: 0.068, blue: 0.068),
            in: RoundedRectangle(cornerRadius: 34, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }
}

private enum OnboardingGameCardSample {
    case zoneStyle
    case textSize
    case latex

    var minimumHeight: CGFloat {
        switch self {
        case .zoneStyle:
            return 128
        case .textSize:
            return 220
        case .latex:
            return 240
        }
    }

    func zone(locale: Locale) -> ZoneModel {
        switch self {
        case .zoneStyle:
            return containerZone(
                id: Self.zoneStyleRootID,
                children: [
                    textZone(
                        id: Self.zoneStyleTitleID,
                        AppLocalization.string("Derivative practice", locale: locale),
                        style: .title,
                        isBold: true
                    ),
                    textZone(
                        id: Self.zoneStyleBodyID,
                        AppLocalization.string("If $f(x)=x^2$, what is $f'(x)$?", locale: locale)
                    ),
                ]
            )
        case .textSize:
            return containerZone(
                id: Self.textSizeRootID,
                children: [
                    textZone(
                        id: Self.textSizeTitleID,
                        AppLocalization.string("What is active recall?", locale: locale),
                        style: .title,
                        isBold: true
                    ),
                    textZone(
                        id: Self.textSizeBodyID,
                        AppLocalization.string("Answer from memory before checking the card.", locale: locale)
                    ),
                ]
            )
        case .latex:
            return containerZone(
                id: Self.latexRootID,
                children: [
                    textZone(
                        id: Self.latexTitleID,
                        AppLocalization.string("Math stays readable in play mode.", locale: locale),
                        style: .title,
                        isBold: true
                    ),
                    textZone(
                        id: Self.latexFormulaID,
                        AppLocalization.string("LaTeX preview formula", locale: locale)
                    ),
                ]
            )
        }
    }

    private func containerZone(id: UUID, children: [ZoneModel]) -> ZoneModel {
        ZoneModel(
            id: id,
            children: children,
            direction: .vertical
        )
    }

    private func textZone(
        id: UUID,
        _ text: String,
        style: TextBlockStyle = .body,
        isBold: Bool = false
    ) -> ZoneModel {
        ZoneModel(
            id: id,
            contentType: .text,
            text: text,
            textStyle: style,
            sizeMode: .fillWidth,
            blockAlignment: .center,
            textColor: .primary,
            isBold: isBold
        )
    }

    private static let zoneStyleRootID = UUID(uuidString: "ACFB2293-3371-42D6-9A5E-64C515D2F761")!
    private static let zoneStyleTitleID = UUID(uuidString: "D58D1922-2D4F-455F-98E3-371D42E7A101")!
    private static let zoneStyleBodyID = UUID(uuidString: "3AF9CFA0-BD2F-4497-97F4-B60E1FBA8D23")!
    private static let textSizeRootID = UUID(uuidString: "6CF2C69E-269B-4C78-B389-47FE1359F4F5")!
    private static let textSizeTitleID = UUID(uuidString: "C55C9D29-E07F-43E8-BBC5-9EE833B84923")!
    private static let textSizeBodyID = UUID(uuidString: "78C6CE96-9A92-49B1-BE68-7F84AB7D5301")!
    private static let latexRootID = UUID(uuidString: "5180A001-E38E-48D6-9F1E-F26971E3BA67")!
    private static let latexTitleID = UUID(uuidString: "1D540706-56B5-43CF-A54C-64397A08AC3A")!
    private static let latexFormulaID = UUID(uuidString: "7D4AA0BA-9BA3-4335-BE2F-EAD820E87E5C")!
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

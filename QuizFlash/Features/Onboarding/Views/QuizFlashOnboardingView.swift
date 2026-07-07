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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let presentation: OnboardingPresentation
    let onComplete: @MainActor @Sendable (OnboardingPresentation) -> Void
    let onClose: @MainActor @Sendable (OnboardingPresentation) -> Void

    @State private var currentIndex = 0
    @State private var cardsTarget = AppPreferences.defaultDailyCardsGoal
    @State private var welcomeDemoIsActive = true
    @State private var welcomeDemoStopTask: Task<Void, Never>?
    @State private var introContentIsPresented = false
    @State private var introContentAnimationTask: Task<Void, Never>?

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    private var items: [QuizFlashOnboardingItem] {
        QuizFlashOnboardingItem.defaultItems
    }

    var body: some View {
        if presentation.isIntro {
            introBody
        } else {
            setupBody
        }
    }

    private var setupBody: some View {
        GeometryReader { proxy in
            let metrics = QuizFlashOnboardingLayoutMetrics(containerSize: proxy.size)

            ZStack(alignment: .bottom) {
                themeManager.screenBackground
                    .ignoresSafeArea()

                onboardingDisplayView(metrics: metrics)
                    .compositingGroup()
                    .scaleEffect(
                        items[currentIndex].zoomScale,
                        anchor: items[currentIndex].zoomAnchor
                    )
                    .padding(.top, metrics.topContentPadding)
                    .padding(.horizontal, metrics.horizontalContentPadding)
                    .padding(.bottom, metrics.bottomControlsHeight + metrics.displayBottomSpacing)

                bottomControls(metrics: metrics)

                backButton(metrics: metrics)
            }
        }
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
        .onAppear(perform: syncStateFromPreferences)
        .onDisappear {
            welcomeDemoStopTask?.cancel()
        }
    }

    private var introBody: some View {
        GeometryReader { proxy in
            let metrics = QuizFlashOnboardingLayoutMetrics(containerSize: proxy.size)

            ZStack {
                themeManager.screenBackground
                    .ignoresSafeArea()

                IntroWelcomePage(
                    buttonHorizontalPadding: metrics.continueButtonHorizontalPadding,
                    onStart: {
                        withAnimation(introExitAnimation) {
                            onComplete(presentation)
                        }
                    }
                )
                .scaleEffect(introContentScale, anchor: .center)
            }
        }
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
        .onAppear(perform: startIntroContentAnimation)
        .onDisappear {
            introContentAnimationTask?.cancel()
            introContentAnimationTask = nil
            introContentIsPresented = false
            welcomeDemoStopTask?.cancel()
        }
    }

    // MARK: - Content

    private func onboardingDisplayView(metrics: QuizFlashOnboardingLayoutMetrics) -> some View {
        let frameMetrics = metrics.deviceFrameMetrics
        let shape = RoundedRectangle(cornerRadius: frameMetrics.cornerRadius, style: .continuous)

        return GeometryReader { proxy in
            let size = proxy.size

            Rectangle()
                .fill(.black)

            HStack(spacing: UIConstants.Spacing.medium) {
                ForEach(items.indices, id: \.self) { index in
                    onboardingPage(for: items[index], isActive: index == currentIndex)
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
    private func onboardingPage(for item: QuizFlashOnboardingItem, isActive: Bool) -> some View {
        switch item.kind {
        case .welcome:
            WelcomeOnboardingPage(isActive: isActive || welcomeDemoIsActive)
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

    private func bottomControls(metrics: QuizFlashOnboardingLayoutMetrics) -> some View {
        VStack(spacing: UIConstants.Spacing.medium) {
            if items[currentIndex].kind == .welcome {
                Spacer(minLength: 0)
            } else {
                textContent
            }
            indicatorView
            continueButton(horizontalPadding: metrics.continueButtonHorizontalPadding)
        }
        .padding(.top, UIConstants.Spacing.large)
        .padding(.horizontal, UIConstants.Spacing.standard)
        .frame(width: metrics.bottomControlsWidth)
        .frame(height: metrics.bottomControlsHeight)
        .padding(.bottom, metrics.bottomControlsBottomPadding)
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

    private func continueButton(horizontalPadding: CGFloat) -> some View {
        Button {
            applyCurrentStep()

            if currentIndex == items.count - 1 {
                onComplete(presentation)
                return
            }

            move(to: currentIndex + 1)
        } label: {
            Text(AppLocalization.string(currentIndex == items.count - 1 ? "Get started" : "Continue", locale: locale))
                .fontWeight(.medium)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .quizFlashButtonStyle(.primary, shape: .capsule, size: UIConstants.Size.buttonHeight)
        .padding(.horizontal, horizontalPadding)
    }

    private func backButton(metrics: QuizFlashOnboardingLayoutMetrics) -> some View {
        Button {
            move(to: currentIndex - 1)
        } label: {
            Image(systemName: "chevron.left")
        }
        .quizFlashButtonStyle(.surface, shape: .circle, size: UIConstants.Size.actionButton)
        .opacity(currentIndex == 0 ? 0 : 1)
        .allowsHitTesting(currentIndex > 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, metrics.chromeHorizontalPadding)
        .padding(.top, metrics.chromeTopPadding)
    }

    // MARK: - Actions

    private func syncStateFromPreferences() {
        cardsTarget = appPreferences.dailyCardsGoal ?? AppPreferences.defaultDailyCardsGoal
        appPreferences.dailyCardsGoal = cardsTarget
        welcomeDemoIsActive = currentIndex == 0
    }

    private func applyCurrentStep() {
        guard items[currentIndex].kind == .cardsTarget else { return }
        appPreferences.dailyCardsGoal = cardsTarget
    }

    private func move(to proposedIndex: Int) {
        let nextIndex = min(max(proposedIndex, 0), items.count - 1)
        guard nextIndex != currentIndex else { return }

        updateWelcomeDemoActivity(from: currentIndex, to: nextIndex)

        withAnimation(animation) {
            currentIndex = nextIndex
        }
    }

    private func updateWelcomeDemoActivity(from oldIndex: Int, to newIndex: Int) {
        welcomeDemoStopTask?.cancel()

        if newIndex == 0 {
            welcomeDemoIsActive = true
            return
        }

        guard oldIndex == 0 else { return }

        welcomeDemoIsActive = true
        welcomeDemoStopTask = Task { @MainActor in
            let transitionDelay: Duration = reduceMotion ? .milliseconds(260) : .milliseconds(720)
            try? await Task.sleep(for: transitionDelay)

            guard !Task.isCancelled, currentIndex != 0 else { return }
            welcomeDemoIsActive = false
        }
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

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.22) : .interpolatingSpring(duration: 0.65, bounce: 0, initialVelocity: 0)
    }

    private var introExitAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.22) : .easeInOut(duration: 0.42)
    }

    private var introContentScale: CGFloat {
        introContentIsPresented || reduceMotion ? 1 : 0.965
    }

    private func startIntroContentAnimation() {
        introContentAnimationTask?.cancel()
        introContentIsPresented = false

        introContentAnimationTask = Task { @MainActor in
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(90))
            }

            guard !Task.isCancelled else { return }

            let presentationAnimation: Animation = reduceMotion
                ? .easeInOut(duration: 0.01)
                : .spring(response: 0.52, dampingFraction: 0.90)

            withAnimation(presentationAnimation) {
                introContentIsPresented = true
            }
        }
    }

    private func pageScale(for index: Int) -> CGFloat {
        index == currentIndex ? 1 : 0.88
    }

    private func pageOpacity(for index: Int) -> Double {
        index == currentIndex ? 1 : 0.74
    }
}

// MARK: - Layout Metrics

private struct QuizFlashOnboardingLayoutMetrics {
    let containerSize: CGSize

    private var width: CGFloat {
        max(containerSize.width, 1)
    }

    private var height: CGFloat {
        max(containerSize.height, 1)
    }

    private var aspectRatio: CGFloat {
        width / height
    }

    private var diagonalScale: CGFloat {
        sqrt(width * height)
    }

    var topContentPadding: CGFloat {
        height * 0.018
    }

    var horizontalContentPadding: CGFloat {
        width * 0.020
    }

    var displayBottomSpacing: CGFloat {
        height * 0.018
    }

    var bottomControlsHeight: CGFloat {
        height * (0.20 - (aspectRatio * 0.070))
    }

    var bottomControlsWidth: CGFloat {
        width * (0.90 - (aspectRatio * 0.18))
    }

    var bottomControlsBottomPadding: CGFloat {
        height * 0.052
    }

    var introButtonBottomPadding: CGFloat {
        height * 0.090
    }

    var introButtonReservedHeight: CGFloat {
        height * 0.135
    }

    var continueButtonHorizontalPadding: CGFloat {
        width * 0.022
    }

    var chromeHorizontalPadding: CGFloat {
        width * 0.038
    }

    var chromeTopPadding: CGFloat {
        height * 0.046
    }

    var deviceFrameMetrics: QuizFlashOnboardingDeviceFrameMetrics {
        QuizFlashOnboardingDeviceFrameMetrics(
            cornerRadius: diagonalScale * 0.035,
            highlightLineWidth: width * 0.0036,
            outerLineWidth: width * 0.0045,
            innerLineWidth: width * 0.0036,
            innerPadding: width * 0.0045,
            overlayPadding: -(width * 0.0054),
            highlightOpacity: 0.85
        )
    }
}

private struct WelcomeOnboardingLayoutMetrics {
    let containerSize: CGSize
    let titleLineCount: Int

    private var width: CGFloat {
        max(containerSize.width, 1)
    }

    private var height: CGFloat {
        max(containerSize.height, 1)
    }

    var horizontalPadding: CGFloat {
        width * 0.055
    }

    var topBreathingRoom: CGFloat {
        height * 0.105
    }

    var titleBlockHeight: CGFloat {
        let lineHeights = (0..<titleLineCount).reduce(CGFloat.zero) { partialHeight, index in
            partialHeight + (titleSize(for: index) * 1.04)
        }
        let spacingHeight = titleLineSpacing * CGFloat(max(titleLineCount - 1, 0))

        return (lineHeights + spacingHeight) * 1.08
    }

    var titleLineSpacing: CGFloat {
        height * 0.004
    }

    func titleSize(for index: Int) -> CGFloat {
        index == 0 ? baseTitleSize * 0.64 : baseTitleSize * 1.04
    }

    var demoHeight: CGFloat {
        height * 0.47
    }

    var titleDemoGap: CGFloat {
        availableVerticalRemainder * 0.58
    }

    private var baseTitleSize: CGFloat {
        sqrt(width * height) * 0.078
    }

    private var availableVerticalRemainder: CGFloat {
        max(height - topBreathingRoom - titleBlockHeight - demoHeight, 0)
    }
}

private struct IntroWelcomeLayoutMetrics {
    let containerSize: CGSize
    let titleLineCount: Int

    private var width: CGFloat {
        max(containerSize.width, 1)
    }

    private var height: CGFloat {
        max(containerSize.height, 1)
    }

    var horizontalPadding: CGFloat {
        width * 0.055
    }

    var topBreathingRoom: CGFloat {
        height * 0.205
    }

    var titleLineSpacing: CGFloat {
        height * 0.004
    }

    var titleBlockHeight: CGFloat {
        let lineHeights = (0..<titleLineCount).reduce(CGFloat.zero) { partialHeight, index in
            partialHeight + (titleSize(for: index) * 1.04)
        }
        let spacingHeight = titleLineSpacing * CGFloat(max(titleLineCount - 1, 0))

        return (lineHeights + spacingHeight) * 1.08
    }

    func titleSize(for index: Int) -> CGFloat {
        index == 0 ? baseTitleSize * 0.64 : baseTitleSize * 1.04
    }

    var titleDemoGap: CGFloat {
        height * 0.085
    }

    var demoHeight: CGFloat {
        height * 0.305
    }

    var demoButtonGap: CGFloat {
        height * 0.052
    }

    var buttonWidth: CGFloat {
        width * 0.70
    }

    private var baseTitleSize: CGFloat {
        sqrt(width * height) * 0.078
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
            titleKey: "Choose your zone style",
            subtitleKey: "This is how zones will look inside cards.",
            kind: .zoneStyle
        ),
        .init(
            id: 1,
            titleKey: "Full LaTeX support",
            subtitleKey: "Generate or request cards with LaTeX symbols without friction.",
            kind: .latexSupport
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
    case latexSupport
    case cardsTarget
    case textSize
}

// MARK: - Pages

private struct IntroWelcomePage: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let buttonHorizontalPadding: CGFloat
    let onStart: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let titleLines = welcomeTitleLines(locale: appPreferences.resolvedLocale)
            let metrics = IntroWelcomeLayoutMetrics(containerSize: size, titleLineCount: titleLines.count)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                    .frame(height: metrics.topBreathingRoom)

                VStack(spacing: metrics.titleLineSpacing) {
                    ForEach(titleLines.indices, id: \.self) { index in
                        Text(titleLines[index])
                            .font(.system(
                                size: metrics.titleSize(for: index),
                                weight: .black,
                                design: .rounded
                            ))
                            .foregroundStyle(titleForegroundStyle(for: index, total: titleLines.count))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .shadow(
                                color: themeManager.accentColor.color.opacity(index == titleLines.count - 1 ? 0.20 : 0.10),
                                radius: 18,
                                y: 8
                            )
                    }
                }
                .multilineTextAlignment(.center)
                .frame(height: metrics.titleBlockHeight, alignment: .center)

                Spacer(minLength: 0)
                    .frame(height: metrics.titleDemoGap)

                WelcomeCardForms(height: metrics.demoHeight, isActive: true)

                Spacer(minLength: 0)
                    .frame(height: metrics.demoButtonGap)

                Button {
                    onStart()
                } label: {
                    Text(AppLocalization.string("Start", locale: appPreferences.resolvedLocale))
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .quizFlashButtonStyle(.primary, shape: .capsule, size: UIConstants.Size.buttonHeight)
                .padding(.horizontal, buttonHorizontalPadding)
                .frame(width: metrics.buttonWidth)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(width: size.width, height: size.height, alignment: .center)
        }
    }

    private func welcomeTitleLines(locale: Locale) -> [String] {
        let title = AppLocalization.string("Welcome to QuizFlash", locale: locale)

        if let range = title.range(of: "QuizFlash", options: .caseInsensitive) {
            let firstLine = String(title[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " to", with: " To", options: .caseInsensitive)

            return [firstLine, "QuizFlash"]
        }

        return [title]
    }

    private func titleForegroundStyle(for index: Int, total: Int) -> AnyShapeStyle {
        guard total > 1, index == total - 1 else {
            return AnyShapeStyle(themeManager.textPrimary)
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    themeManager.textPrimary,
                    themeManager.accentColor.color.opacity(0.96)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

private struct WelcomeOnboardingPage: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            let titleLines = welcomeTitleLines(locale: appPreferences.resolvedLocale)
            let metrics = WelcomeOnboardingLayoutMetrics(
                containerSize: proxy.size,
                titleLineCount: titleLines.count
            )

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                    .frame(height: metrics.topBreathingRoom)

                VStack(spacing: metrics.titleLineSpacing) {
                    ForEach(titleLines.indices, id: \.self) { index in
                        Text(titleLines[index])
                            .font(.system(size: metrics.titleSize(for: index), weight: .black, design: .rounded))
                            .foregroundStyle(titleForegroundStyle(for: index, total: titleLines.count))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .shadow(color: themeManager.accentColor.color.opacity(index == titleLines.count - 1 ? 0.20 : 0.10), radius: 18, y: 8)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(height: metrics.titleBlockHeight, alignment: .center)

                Spacer(minLength: 0)
                    .frame(height: metrics.titleDemoGap)

                WelcomeCardForms(height: metrics.demoHeight, isActive: isActive)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func welcomeTitleLines(locale: Locale) -> [String] {
        let title = AppLocalization.string("Welcome to QuizFlash", locale: locale)

        if let range = title.range(of: "QuizFlash", options: .caseInsensitive) {
            let firstLine = String(title[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " to", with: " To", options: .caseInsensitive)

            return [firstLine, "QuizFlash"]
        }

        return [title]
    }

    private func titleForegroundStyle(for index: Int, total: Int) -> AnyShapeStyle {
        guard total > 1, index == total - 1 else {
            return AnyShapeStyle(themeManager.textPrimary)
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    themeManager.textPrimary,
                    themeManager.accentColor.color.opacity(0.96)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

private struct WelcomeCardForms: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ThemeManager.self) private var themeManager

    let height: CGFloat
    let isActive: Bool

    @State private var phase: WelcomeCardDemoPhase = .resting

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let contentScale = sqrt(width / 520)
            let cardWidth = min(width * 0.64, height * 0.68)
            let cardHeight = cardWidth * 1.42
            let quizWidth = width * 0.90
            let quizHeight = height * 0.86
            let handIconSize = 44 * contentScale
            let fingerTipToSymbolCenterOffset = CGSize(
                width: handIconSize * 0.34,
                height: handIconSize * 0.38
            )

            ZStack {
                if let flashcardTapOffset = phase.flashcardTapRippleOffset(cardWidth: cardWidth, cardHeight: cardHeight),
                   !reduceMotion {
                    tapRipple(
                        size: cardWidth * 0.32,
                        color: themeManager.accentColor.color,
                        scale: phase.tapRippleScale,
                        opacity: phase.tapRippleOpacity
                    )
                    .offset(flashcardTapOffset)
                }

                demoCard(width: cardWidth, height: cardHeight)
                    .rotation3DEffect(.degrees(phase.cardFlipDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                    .scaleEffect(phase.cardScale)
                    .rotationEffect(.degrees(phase.cardTiltDegrees))
                    .offset(x: phase.cardOffsetX(cardWidth: cardWidth, containerWidth: width), y: phase.cardOffsetY)
                    .opacity(phase.cardOpacity)
                    .shadow(color: themeManager.accentColor.color.opacity(0.20), radius: 26, y: 14)

                quizDemo(width: quizWidth, height: quizHeight, contentScale: contentScale)
                    .scaleEffect(phase.quizScale)
                    .offset(y: phase.quizOffsetY)
                    .opacity(phase.quizOpacity)

                if let quizTapOffset = phase.quizTapRippleOffset(quizWidth: quizWidth, quizHeight: quizHeight),
                   !reduceMotion {
                    tapRipple(
                        size: quizWidth * 0.16,
                        color: phase.quizTapRippleColor(accent: themeManager.accentColor.color),
                        scale: phase.tapRippleScale,
                        opacity: phase.tapRippleOpacity
                    )
                    .offset(quizTapOffset)
                }

                if phase.showsHand && !reduceMotion {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 44 * contentScale, weight: .semibold))
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
                                quizHeight: quizHeight,
                                fingerTipToSymbolCenterOffset: fingerTipToSymbolCenterOffset
                            )
                        )
                        .accessibilityHidden(true)
                }
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .task(id: animationTaskID) {
            guard isActive, !reduceMotion else {
                withTransaction(Transaction(animation: nil)) {
                    phase = .resting
                }
                return
            }

            await runDemoLoop()
        }
    }

    @MainActor
    private func runDemoLoop() async {
        phase = .resting

        do {
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(650))
                await animate(to: .tapApproach, duration: 0.70)
                try await Task.sleep(for: .milliseconds(220))
                await animate(to: .tapPress, duration: 0.18)
                try await Task.sleep(for: .milliseconds(180))
                await animate(to: .flipped, duration: 0.62)
                try await Task.sleep(for: .milliseconds(680))
                await animate(to: .swipeReady, duration: 0.42)
                try await Task.sleep(for: .milliseconds(180))
                await animate(to: .swiping, duration: 0.86)
                try await Task.sleep(for: .milliseconds(180))
                await animate(to: .quizAppearing, duration: 0.56)
                try await Task.sleep(for: .milliseconds(420))
                await animate(to: .quizWrongApproach, duration: 0.48)
                try await Task.sleep(for: .milliseconds(160))
                await animate(to: .quizWrongPress, duration: 0.14)
                try await Task.sleep(for: .milliseconds(120))
                await animate(to: .quizWrongResult, duration: 0.34)
                try await Task.sleep(for: .milliseconds(640))
                await animate(to: .quizCorrectApproach, duration: 0.50)
                try await Task.sleep(for: .milliseconds(160))
                await animate(to: .quizCorrectPress, duration: 0.14)
                try await Task.sleep(for: .milliseconds(120))
                await animate(to: .quizCorrectResult, duration: 0.38)
                try await Task.sleep(for: .milliseconds(850))

                await animate(to: .quizLeaving, duration: 0.32)
                try await Task.sleep(for: .milliseconds(210))

                withTransaction(Transaction(animation: nil)) {
                    phase = .cardReturnHidden
                }
                await animate(to: .resting, duration: 0.48)
            }
        } catch {
            withTransaction(Transaction(animation: nil)) {
                phase = .resting
            }
        }
    }

    @MainActor
    private func animate(to newPhase: WelcomeCardDemoPhase, duration: TimeInterval) async {
        guard !Task.isCancelled else { return }

        withAnimation(.smooth(duration: duration, extraBounce: 0.03)) {
            phase = newPhase
        }
    }

    private var animationTaskID: String {
        "\(isActive)-\(reduceMotion)"
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

    private func tapRipple(size: CGFloat, color: Color, scale: CGFloat, opacity: Double) -> some View {
        Circle()
            .strokeBorder(color.opacity(0.62), lineWidth: 2)
            .background {
                Circle()
                    .fill(color.opacity(0.10))
            }
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .opacity(opacity)
            .blur(radius: opacity > 0 ? 0 : 1.5)
    }

    private func quizDemo(width: CGFloat, height: CGFloat, contentScale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16 * contentScale) {
            VStack(alignment: .leading, spacing: 10 * contentScale) {
                cardLine(width: width * 0.62, height: 13 * contentScale, opacity: 0.52)
                cardLine(width: width * 0.78, height: 11 * contentScale, opacity: 0.38)
                cardLine(width: width * 0.45, height: 11 * contentScale, opacity: 0.26)
            }
            .padding(.bottom, 3 * contentScale)

            VStack(spacing: 10 * contentScale) {
                quizAnswerRow(width: width, index: 0, state: phase.answerState(for: 0), contentScale: contentScale)
                quizAnswerRow(width: width, index: 1, state: phase.answerState(for: 1), contentScale: contentScale)
                quizAnswerRow(width: width, index: 2, state: phase.answerState(for: 2), contentScale: contentScale)
            }
        }
        .frame(width: width, height: height, alignment: .center)
    }

    private func quizAnswerRow(width: CGFloat, index: Int, state: WelcomeQuizAnswerState, contentScale: CGFloat) -> some View {
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
                .frame(width: 15 * contentScale, height: 15 * contentScale)
                .overlay {
                    if isWrong {
                        Image(systemName: "xmark")
                            .font(.system(size: 8 * contentScale, weight: .black))
                            .foregroundStyle(.white)
                    } else if isCorrect {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8 * contentScale, weight: .black))
                            .foregroundStyle(.white)
                    }
                }

            VStack(alignment: .leading, spacing: 7 * contentScale) {
                cardLine(width: width * (index == 1 ? 0.43 : 0.52), height: 9 * contentScale, opacity: state == .neutral ? 0.34 : 0.54)
                cardLine(width: width * (index == 2 ? 0.38 : 0.47), height: 8 * contentScale, opacity: state == .neutral ? 0.22 : 0.34)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14 * contentScale)
        .frame(height: 52 * contentScale)
        .background(
            color.opacity(isWrong || isCorrect ? 0.16 : 0.055),
            in: RoundedRectangle(cornerRadius: 17 * contentScale, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17 * contentScale, style: .continuous)
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

    var tapRippleScale: CGFloat {
        switch self {
        case .tapPress, .quizWrongPress, .quizCorrectPress:
            0.96
        case .flipped, .quizWrongResult, .quizCorrectResult:
            1.30
        case .tapApproach, .quizWrongApproach, .quizCorrectApproach:
            0.68
        case .resting,
             .swipeReady,
             .swiping,
             .quizAppearing,
             .quizLeaving,
             .cardReturnHidden:
            0.68
        }
    }

    var tapRippleOpacity: Double {
        switch self {
        case .tapPress, .quizWrongPress, .quizCorrectPress:
            0.58
        case .tapApproach, .flipped, .quizWrongApproach, .quizCorrectApproach, .quizWrongResult, .quizCorrectResult:
            0
        case .resting,
             .swipeReady,
             .swiping,
             .quizAppearing,
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

    func quizTapRippleColor(accent: Color) -> Color {
        switch self {
        case .quizWrongApproach, .quizWrongPress, .quizWrongResult:
            .red
        case .quizCorrectApproach, .quizCorrectPress, .quizCorrectResult:
            .green
        case .resting,
             .tapApproach,
             .tapPress,
             .flipped,
             .swipeReady,
             .swiping,
             .quizAppearing,
             .quizLeaving,
             .cardReturnHidden:
            accent
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

    func handOffset(
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        quizWidth: CGFloat,
        quizHeight: CGFloat,
        fingerTipToSymbolCenterOffset: CGSize
    ) -> CGSize {
        let offset = switch self {
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

        guard usesFingerTipTarget else { return offset }

        return CGSize(
            width: offset.width + fingerTipToSymbolCenterOffset.width,
            height: offset.height + fingerTipToSymbolCenterOffset.height
        )
    }

    private var usesFingerTipTarget: Bool {
        switch self {
        case .tapApproach,
             .tapPress,
             .flipped,
             .quizWrongApproach,
             .quizWrongPress,
             .quizWrongResult,
             .quizCorrectApproach,
             .quizCorrectPress,
             .quizCorrectResult:
            true
        case .resting, .swipeReady, .swiping, .quizAppearing, .quizLeaving, .cardReturnHidden:
            false
        }
    }

    func flashcardTapRippleOffset(cardWidth: CGFloat, cardHeight: CGFloat) -> CGSize? {
        switch self {
        case .tapApproach, .tapPress, .flipped:
            CGSize(width: cardWidth * 0.20, height: cardHeight * 0.10)
        case .resting,
             .swipeReady,
             .swiping,
             .quizAppearing,
             .quizWrongApproach,
             .quizWrongPress,
             .quizWrongResult,
             .quizCorrectApproach,
             .quizCorrectPress,
             .quizCorrectResult,
             .quizLeaving,
             .cardReturnHidden:
            nil
        }
    }

    func quizTapRippleOffset(quizWidth: CGFloat, quizHeight: CGFloat) -> CGSize? {
        switch self {
        case .quizWrongApproach, .quizWrongPress, .quizWrongResult:
            CGSize(width: quizWidth * 0.08, height: -quizHeight * 0.03)
        case .quizCorrectApproach, .quizCorrectPress, .quizCorrectResult:
            CGSize(width: quizWidth * 0.08, height: quizHeight * 0.18)
        case .resting,
             .tapApproach,
             .tapPress,
             .flipped,
             .swipeReady,
             .swiping,
             .quizAppearing,
             .quizLeaving,
             .cardReturnHidden:
            nil
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

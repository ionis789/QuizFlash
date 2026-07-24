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

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    private var items: [QuizFlashOnboardingItem] {
        QuizFlashOnboardingItem.defaultItems
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = QuizFlashOnboardingLayoutMetrics(
                containerSize: proxy.size,
                safeTopInset: resolvedSafeAreaTop(from: proxy.safeAreaInsets.top)
            )

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
                    .padding(
                        .bottom,
                        metrics.bottomControlsHeight
                            + metrics.displayBottomSpacing
                            - (items[currentIndex].kind == .practiceFlow ? metrics.practiceFlowDisplayExtension : 0)
                    )

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
        case .practiceFlow:
            PracticeFlowOnboardingPage(isActive: isActive)
        case .latexSupport:
            LatexSupportOnboardingPage(isActive: isActive)
        case .cardsTarget:
            CardsTargetOnboardingPage(cardsTarget: $cardsTarget)
        }
    }

    private func bottomControls(metrics: QuizFlashOnboardingLayoutMetrics) -> some View {
        VStack(spacing: UIConstants.Spacing.medium) {
            textContent
                .frame(height: metrics.descriptionHeight)

            continueButton(horizontalPadding: metrics.continueButtonHorizontalPadding)
                .padding(.top, UIConstants.Spacing.small)
            indicatorView
        }
        .padding(.horizontal, UIConstants.Spacing.standard)
        .frame(width: metrics.bottomControlsWidth)
        .frame(height: metrics.bottomControlsHeight, alignment: .bottom)
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
                            .fixedSize(horizontal: false, vertical: true)
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
        ChromeSoftCircleSymbolButton(
            systemName: "chevron.compact.left",
            accessibilityLabel: AppLocalization.string("Back", locale: locale),
            action: { move(to: currentIndex - 1) }
        )
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

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.22) : .interpolatingSpring(duration: 0.65, bounce: 0, initialVelocity: 0)
    }

    private func pageScale(for index: Int) -> CGFloat {
        index == currentIndex ? 1 : 0.88
    }

    private func pageOpacity(for index: Int) -> Double {
        index == currentIndex ? 1 : 0.74
    }

    private func resolvedSafeAreaTop(from proxySafeAreaTop: CGFloat) -> CGFloat {
        if proxySafeAreaTop > 0 {
            return proxySafeAreaTop
        }

        let activeWindowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })

        return activeWindowScene?.windows.first(where: \.isKeyWindow)?.safeAreaInsets.top ?? 0
    }
}

// MARK: - Layout Metrics

private struct QuizFlashOnboardingLayoutMetrics {
    let containerSize: CGSize
    let safeTopInset: CGFloat

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

    var practiceFlowDisplayExtension: CGFloat {
        min(max(height * 0.032, 24), 32)
    }

    var bottomControlsHeight: CGFloat {
        max(height * (0.250 - (aspectRatio * 0.035)), 200)
    }

    var descriptionHeight: CGFloat {
        min(max(height * 0.090, 72), 82)
    }

    var bottomControlsWidth: CGFloat {
        min(width * 0.96, 680)
    }

    var bottomControlsBottomPadding: CGFloat {
        height * 0.052
    }

    var continueButtonHorizontalPadding: CGFloat {
        width * 0.022
    }

    var chromeHorizontalPadding: CGFloat {
        UIConstants.Layout.compactScreenEdgeInset
    }

    var chromeTopPadding: CGFloat {
        safeTopInset + UIConstants.Layout.deckNavigationTopPadding
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

    var contentVerticalOffset: CGFloat {
        min(max(height * 0.034, 22), 36)
    }

    private var baseTitleSize: CGFloat {
        sqrt(width * height) * 0.078
    }

    private var availableVerticalRemainder: CGFloat {
        max(height - topBreathingRoom - titleBlockHeight - demoHeight, 0)
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
            titleKey: "Study smarter",
            subtitleKey: "Practice today. Remember tomorrow.",
            kind: .welcome
        ),
        .init(
            id: 1,
            titleKey: "Create cards with AI",
            subtitleKey: "Turn your material into cards ready to study.",
            kind: .practiceFlow
        ),
        .init(
            id: 2,
            titleKey: "LaTeX support",
            subtitleKey: "Tap the flashcard to flip it.",
            kind: .latexSupport
        ),
        .init(
            id: 3,
            titleKey: "Build a daily habit",
            subtitleKey: "Choose a pace that feels easy to keep.",
            kind: .cardsTarget
        )
    ]
}

private enum QuizFlashOnboardingPageKind: Hashable {
    case welcome
    case practiceFlow
    case latexSupport
    case cardsTarget
}

// MARK: - Pages

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
            .offset(y: metrics.contentVerticalOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func welcomeTitleLines(locale: Locale) -> [String] {
        let title = AppLocalization.string("Learn easy with QuizFlash", locale: locale)

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

/// Shows source material passing through QuizFlash AI and becoming study cards.
private struct PracticeFlowOnboardingPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let isActive: Bool

    @State private var sourceIsVisible = false
    @State private var inputConnectorProgress: CGFloat = 0
    @State private var processorIsVisible = false
    @State private var processorTraceProgress: CGFloat = 0
    @State private var outputConnectorProgress: CGFloat = 0
    @State private var deliveredCardCount = 0
    @State private var activeCardIndex: Int?
    @State private var activeCardProgress: CGFloat = 0
    @State private var hasCompletedSequence = false

    private static let generatedCardCount = 7

    var body: some View {
        GeometryReader { proxy in
            let metrics = AIFlowLayoutMetrics(containerSize: proxy.size)

            ZStack {
                sourceMaterial(
                    width: metrics.sourceWidth,
                    height: metrics.sourceHeight,
                    scale: metrics.contentScale
                )
                    .position(x: metrics.centerX, y: metrics.sourceY)
                    .scaleRevealMotion(
                        isVisible: sourceIsVisible,
                        reduceMotion: reduceMotion,
                        hiddenOpacity: 0.001
                    )

                flowConnector(
                    height: metrics.inputConnectorHeight,
                    progress: inputConnectorProgress,
                    scale: metrics.contentScale
                )
                    .position(x: metrics.centerX, y: metrics.inputConnectorY)

                aiProcessor(
                    width: metrics.processorWidth,
                    height: metrics.processorHeight,
                    scale: metrics.contentScale
                )
                    .position(x: metrics.centerX, y: metrics.processorY)
                    .scaleRevealMotion(
                        isVisible: processorIsVisible,
                        reduceMotion: reduceMotion,
                        hiddenOpacity: 0.001
                    )

                flowConnector(
                    height: metrics.outputConnectorHeight,
                    progress: outputConnectorProgress,
                    scale: metrics.contentScale
                )
                    .position(x: metrics.centerX, y: metrics.outputConnectorY)

                generatedCards(metrics: metrics)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: animationTaskID) {
            guard isActive else { return }

            guard !reduceMotion else {
                showCompletedResult()
                return
            }

            await runGenerationSequence()
        }
    }

    private func sourceMaterial(width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        HStack(spacing: UIConstants.Spacing.medium * scale) {
            ZStack {
                RoundedRectangle(cornerRadius: 15 * scale, style: .continuous)
                    .fill(themeManager.accentColor.color.opacity(0.16))

                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 25 * scale, weight: .semibold))
                    .foregroundStyle(themeManager.accentColor.color)
            }
            .frame(width: 54 * scale, height: 62 * scale)

            VStack(alignment: .leading, spacing: 10 * scale) {
                Text(AppLocalization.string("Your notes", locale: appPreferences.resolvedLocale))
                    .font(.system(size: 17 * scale, weight: .bold))
                    .foregroundStyle(themeManager.textPrimary)

                sourcePreview(scale: scale)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, UIConstants.Spacing.medium * scale)
        .frame(width: width, height: height)
        .background(
            themeManager.textPrimary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
                .strokeBorder(themeManager.textPrimary.opacity(0.10), lineWidth: max(scale, 1))
        }
        .shadow(
            color: themeManager.accentColor.color.opacity(0.08),
            radius: 14 * scale,
            y: 8 * scale
        )
    }

    private func sourcePreview(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7 * scale) {
            HStack(spacing: 6 * scale) {
                Capsule()
                    .fill(themeManager.textPrimary.opacity(0.30))
                    .frame(width: 82 * scale, height: 7 * scale)

                Capsule()
                    .fill(themeManager.accentColor.color.opacity(0.48))
                    .frame(width: 38 * scale, height: 7 * scale)
            }

            HStack(spacing: 6 * scale) {
                Capsule()
                    .fill(themeManager.textPrimary.opacity(0.18))
                    .frame(width: 54 * scale, height: 7 * scale)

                Capsule()
                    .fill(themeManager.textPrimary.opacity(0.14))
                    .frame(width: 30 * scale, height: 7 * scale)

                Capsule()
                    .fill(themeManager.textPrimary.opacity(0.22))
                    .frame(width: 46 * scale, height: 7 * scale)
            }
        }
    }

    private func aiProcessor(width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        HStack(spacing: 10 * scale) {
            Image(systemName: "sparkles")
                .font(.system(size: 22 * scale, weight: .bold))
                .foregroundStyle(themeManager.accentColor.color)

            Text("AI")
                .font(.system(size: 20 * scale, weight: .bold))
                .foregroundStyle(themeManager.textPrimary)
        }
        .frame(width: width, height: height)
        .background(
            themeManager.textPrimary.opacity(0.075),
            in: RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
                .strokeBorder(themeManager.textPrimary.opacity(0.08), lineWidth: max(scale, 1))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
                .trim(from: 0, to: processorTraceProgress)
                .stroke(
                    LinearGradient(
                        colors: [
                            themeManager.accentColor.color.opacity(0.28),
                            themeManager.accentColor.color,
                            themeManager.accentColor.color.opacity(0.50)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.7 * scale, lineCap: .round, lineJoin: .round)
                )
                .padding(scale)
        }
        .shadow(
            color: themeManager.accentColor.color.opacity(0.18 * processorTraceProgress),
            radius: 22 * scale
        )
    }

    private func flowConnector(height: CGFloat, progress: CGFloat, scale: CGFloat) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        themeManager.accentColor.color.opacity(0.30),
                        themeManager.accentColor.color.opacity(0.92),
                        themeManager.accentColor.color.opacity(0.24)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 3 * scale, height: height)
            .scaleEffect(x: 1, y: progress, anchor: .top)
            .opacity(Double(min(progress * 4, 1)))
        .frame(width: 16 * scale, height: height)
    }

    private func generatedCards(metrics: AIFlowLayoutMetrics) -> some View {
        ForEach(0..<Self.generatedCardCount, id: \.self) { index in
            let progress = cardProgress(for: index)
            let motion = metrics.cardMotion(for: index, progress: progress)

            generatedCard(index: index, scale: metrics.contentScale)
                .frame(width: metrics.cardWidth, height: metrics.cardHeight)
                .scaleRevealMotion(
                    isVisible: cardIsVisible(index),
                    reduceMotion: reduceMotion,
                    hiddenOpacity: 0.001
                )
                .position(motion.position)
                .scaleEffect(x: motion.scaleX, y: motion.scaleY)
                .rotationEffect(.degrees(motion.rotation))
                .opacity(cardOpacity(for: index, progress: progress))
                .shadow(
                    color: index == activeCardIndex
                        ? themeManager.accentColor.color.opacity(0.22)
                        : .black.opacity(0.18),
                    radius: index == activeCardIndex ? 18 : 10,
                    y: index == activeCardIndex ? 10 : 7
                )
                .zIndex(Double(index + 1))
        }
    }

    private func cardProgress(for index: Int) -> CGFloat {
        if index < deliveredCardCount { return 1 }
        if activeCardIndex == index { return activeCardProgress }
        return 0
    }

    private func cardIsVisible(_ index: Int) -> Bool {
        index < deliveredCardCount || activeCardIndex == index
    }

    private func cardOpacity(for index: Int, progress: CGFloat) -> Double {
        if index < deliveredCardCount { return 1 }
        guard activeCardIndex == index else { return 0 }
        return Double(min(progress * 5, 1))
    }

    private func generatedCard(index: Int, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7 * scale) {
            HStack {
                ZStack {
                    Circle()
                        .fill(themeManager.accentColor.color.opacity(0.20))

                    Image(systemName: index.isMultiple(of: 2) ? "rectangle.on.rectangle" : "checklist")
                        .font(.system(size: 9 * scale, weight: .bold))
                        .foregroundStyle(themeManager.accentColor.color)
                }
                .frame(width: 20 * scale, height: 20 * scale)

                Spacer(minLength: 0)

                Circle()
                    .fill(themeManager.accentColor.color.opacity(0.52))
                    .frame(width: 5 * scale, height: 5 * scale)
            }

            Capsule()
                .fill(themeManager.textPrimary.opacity(0.24))
                .frame(height: 6 * scale)

            Capsule()
                .fill(themeManager.textPrimary.opacity(0.12))
                .frame(width: 38 * scale, height: 6 * scale)
        }
        .padding(9 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            themeManager.surfacePrimary,
            in: RoundedRectangle(cornerRadius: 15 * scale, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15 * scale, style: .continuous)
                .strokeBorder(themeManager.accentColor.color.opacity(0.22), lineWidth: max(scale, 1))
        }
    }

    @MainActor
    private func runGenerationSequence() async {
        guard !hasCompletedSequence else {
            showCompletedResult()
            return
        }

        showInitialState()

        do {
            try await Task.sleep(for: .milliseconds(60))
            withAnimation(ScaleRevealMotion.animation(reduceMotion: false)) {
                sourceIsVisible = true
            }
            try await Task.sleep(for: .milliseconds(380))

            try await animate(duration: 0.30, animation: .easeInOut(duration: 0.30)) {
                inputConnectorProgress = 1
            }

            withAnimation(ScaleRevealMotion.animation(reduceMotion: false)) {
                processorIsVisible = true
            }
            try await Task.sleep(for: .milliseconds(100))

            try await animate(duration: 0.42, animation: .easeInOut(duration: 0.42)) {
                processorTraceProgress = 1
            }

            try await animate(duration: 0.30, animation: .easeInOut(duration: 0.30)) {
                outputConnectorProgress = 1
            }

            for index in 0..<Self.generatedCardCount {
                try await deliverCard(at: index)
            }

            hasCompletedSequence = true
        } catch {
            guard !Task.isCancelled else { return }
            showInitialState()
        }
    }

    @MainActor
    private func deliverCard(at index: Int) async throws {
        try Task.checkCancellation()

        let velocity = 1.22 + (Double(index) * 0.13)
        let releaseDuration = 0.07 / velocity
        let fallDuration = 0.19 / velocity
        let settleDuration = 0.11 / velocity

        withTransaction(Transaction(animation: nil)) {
            activeCardIndex = index
            activeCardProgress = 0
        }

        try await Task.sleep(for: .milliseconds(12))

        try await animate(
            duration: releaseDuration,
            animation: .easeOut(duration: releaseDuration)
        ) {
            activeCardProgress = 0.18
        }

        try await animate(
            duration: fallDuration,
            animation: .linear(duration: fallDuration)
        ) {
            activeCardProgress = 1.065
        }

        try await animate(
            duration: settleDuration,
            animation: .spring(response: settleDuration, dampingFraction: 0.66)
        ) {
            activeCardProgress = 1
        }

        withTransaction(Transaction(animation: nil)) {
            deliveredCardCount = index + 1
            activeCardIndex = nil
            activeCardProgress = 0
        }

        try await Task.sleep(for: .milliseconds(10))
    }

    @MainActor
    private func animate(
        duration: TimeInterval,
        animation: Animation,
        updates: () -> Void
    ) async throws {
        try Task.checkCancellation()

        withAnimation(animation, updates)

        try await Task.sleep(for: .seconds(duration))
    }

    @MainActor
    private func showInitialState() {
        withTransaction(Transaction(animation: nil)) {
            sourceIsVisible = false
            inputConnectorProgress = 0
            processorIsVisible = false
            processorTraceProgress = 0
            outputConnectorProgress = 0
            deliveredCardCount = 0
            activeCardIndex = nil
            activeCardProgress = 0
        }
    }

    @MainActor
    private func showCompletedResult() {
        withTransaction(Transaction(animation: nil)) {
            sourceIsVisible = true
            inputConnectorProgress = 1
            processorIsVisible = true
            processorTraceProgress = 1
            outputConnectorProgress = 1
            deliveredCardCount = Self.generatedCardCount
            activeCardIndex = nil
            activeCardProgress = 0
            hasCompletedSequence = true
        }
    }

    private var animationTaskID: String {
        "\(isActive)-\(reduceMotion)"
    }
}

private struct AIFlowLayoutMetrics {
    let containerSize: CGSize

    var contentScale: CGFloat {
        min(max(containerSize.width / 390, 0.86), 1.50)
    }

    private var diagramHeight: CGFloat {
        min(
            max(containerSize.height * 0.76, 430 * contentScale),
            570 * contentScale
        )
    }

    private var topInset: CGFloat {
        max((containerSize.height - diagramHeight) / 2, 18)
    }

    var centerX: CGFloat { containerSize.width / 2 }
    var sourceWidth: CGFloat { min(containerSize.width * 0.84, 330 * contentScale) }
    var sourceHeight: CGFloat {
        min(
            max(diagramHeight * 0.19, 96 * contentScale),
            108 * contentScale
        )
    }
    var processorWidth: CGFloat { min(containerSize.width * 0.48, 188 * contentScale) }
    var processorHeight: CGFloat { 68 * contentScale }
    var cardHeight: CGFloat { 76 * contentScale }
    var cardWidth: CGFloat {
        min(
            max((containerSize.width - (28 * contentScale)) / 3, 88 * contentScale),
            108 * contentScale
        )
    }

    var sourceY: CGFloat { topInset + (sourceHeight / 2) }
    var processorY: CGFloat { topInset + (diagramHeight * 0.48) }
    var cardsY: CGFloat {
        topInset + diagramHeight - cardRowOffset - (cardHeight / 2) + cardsVerticalShift
    }

    var inputConnectorHeight: CGFloat {
        max(
            processorY - (processorHeight / 2) - sourceY - (sourceHeight / 2) - (14 * contentScale),
            28 * contentScale
        )
    }

    var inputConnectorY: CGFloat {
        sourceY + (sourceHeight / 2) + (7 * contentScale) + (inputConnectorHeight / 2)
    }

    var outputConnectorHeight: CGFloat {
        max(
            cardsTopY - processorY - (processorHeight / 2) - (14 * contentScale),
            28 * contentScale
        )
    }

    var outputConnectorY: CGFloat {
        processorY + (processorHeight / 2) + (7 * contentScale) + (outputConnectorHeight / 2)
    }

    func cardMotion(for index: Int, progress: CGFloat) -> AIFlowCardMotion {
        let travelProgress = min(max(progress, 0), 1)
        let finalOffset = cardOffset(for: index)
        let finalRotation = cardRotation(for: index)
        let launchDirection: CGFloat = if finalOffset.width == 0 {
            index.isMultiple(of: 2) ? -1 : 1
        } else {
            finalOffset.width < 0 ? -1 : 1
        }
        let releaseThreshold: CGFloat = 0.18

        let start = CGPoint(
            x: centerX,
            y: processorY + (processorHeight / 2) - (6 * contentScale)
        )
        let release = CGPoint(
            x: centerX,
            y: outputConnectorY + (outputConnectorHeight / 2) + (4 * contentScale)
        )
        let end = CGPoint(
            x: centerX + finalOffset.width,
            y: cardsY + finalOffset.height
        )
        let position: CGPoint

        if travelProgress <= releaseThreshold {
            let releaseProgress = travelProgress / releaseThreshold
            position = CGPoint(
                x: centerX,
                y: start.y + ((release.y - start.y) * releaseProgress)
            )
        } else {
            let fallProgress = (travelProgress - releaseThreshold) / (1 - releaseThreshold)
            let horizontalProgress = fallProgress * fallProgress * (3 - (2 * fallProgress))
            let gravityProgress = fallProgress * fallProgress
            let lateralArc = launchDirection
                * ((14 * contentScale) + (CGFloat(index * 2) * contentScale))
                * CGFloat(sin(.pi * Double(fallProgress)))

            position = CGPoint(
                x: release.x + ((end.x - release.x) * horizontalProgress) + lateralArc,
                y: release.y + ((end.y - release.y) * gravityProgress)
            )
        }

        let impactProgress = min(max((progress - 1) / 0.065, 0), 1)
        let launchRotation = finalRotation + Double(launchDirection * 18)
        let baseScale = 0.56 + (0.44 * travelProgress)
        let velocityStretch = CGFloat(sin(.pi * Double(travelProgress))) * 0.035

        return AIFlowCardMotion(
            position: CGPoint(
                x: position.x,
                y: position.y + (impactProgress * 7 * contentScale)
            ),
            scaleX: baseScale - velocityStretch + (impactProgress * 0.045),
            scaleY: baseScale + velocityStretch - (impactProgress * 0.055),
            rotation: launchRotation + ((finalRotation - launchRotation) * Double(travelProgress))
        )
    }

    private var cardColumnOffset: CGFloat {
        min(
            cardWidth + (8 * contentScale),
            ((containerSize.width - cardWidth) / 2) - (10 * contentScale)
        )
    }

    private var cardRowOffset: CGFloat {
        (cardHeight / 2) + (5 * contentScale)
    }

    private var cardsTopY: CGFloat {
        cardsY - cardRowOffset - (cardHeight / 2)
    }

    private var cardsVerticalShift: CGFloat {
        min(
            max(topInset - (22 * contentScale), 0),
            54 * contentScale
        )
    }

    private var lowerCardOuterOffset: CGFloat {
        min(
            cardWidth * 1.18,
            ((containerSize.width - cardWidth) / 2) - (4 * contentScale)
        )
    }

    private var lowerCardInnerOffset: CGFloat {
        lowerCardOuterOffset / 3
    }

    private func cardOffset(for index: Int) -> CGSize {
        switch index {
        case 0: CGSize(width: -cardColumnOffset, height: -cardRowOffset + (3 * contentScale))
        case 1: CGSize(width: 0, height: -cardRowOffset - (5 * contentScale))
        case 2: CGSize(width: cardColumnOffset, height: -cardRowOffset + (2 * contentScale))
        case 3: CGSize(width: -lowerCardOuterOffset, height: cardRowOffset + (2 * contentScale))
        case 4: CGSize(width: -lowerCardInnerOffset, height: cardRowOffset - (2 * contentScale))
        case 5: CGSize(width: lowerCardInnerOffset, height: cardRowOffset + contentScale)
        default: CGSize(width: lowerCardOuterOffset, height: cardRowOffset + (4 * contentScale))
        }
    }

    private func cardRotation(for index: Int) -> Double {
        switch index {
        case 0: -6
        case 1: -1
        case 2: 6
        case 3: -4
        case 4: 2
        case 5: -2
        default: 4
        }
    }
}

private struct AIFlowCardMotion {
    let position: CGPoint
    let scaleX: CGFloat
    let scaleY: CGFloat
    let rotation: Double
}

/// Demonstrates the same flippable KaTeX-backed flashcard used in Play Mode.
private struct LatexSupportOnboardingPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppPreferences.self) private var appPreferences

    let isActive: Bool

    @State private var isFlipped = false

    var body: some View {
        GeometryReader { proxy in
            let metrics = LatexSupportOnboardingLayoutMetrics(containerSize: proxy.size)
            let frontZone = Self.formulaZone(
                id: Self.frontZoneID,
                text: "\(AppLocalization.string("What is the value of this integral?", locale: appPreferences.resolvedLocale))\n\n$$\\int_0^\\infty e^{-x^2}\\,dx$$"
            )
            let backZone = Self.formulaZone(
                id: Self.backZoneID,
                text: "\(AppLocalization.string("The Gaussian integral equals:", locale: appPreferences.resolvedLocale))\n\n$$\\frac{\\sqrt{\\pi}}{2}$$"
            )

            ZStack {
                FlipCard(
                    frontZone: frontZone,
                    backZone: backZone,
                    isFlipped: $isFlipped,
                    preloadsHiddenFace: true,
                    tapAnimationStyle: .flip3D,
                    contentAlignment: .center,
                    textSize: FlashcardTextSize(step: 1)
                )

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: flipCard)
            }
            .frame(width: metrics.cardWidth, height: metrics.cardHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleRevealMotion(
                isVisible: isActive,
                reduceMotion: reduceMotion,
                hiddenOpacity: 0.001
            )
            .allowsHitTesting(isActive)
            .accessibilityLabel(
                AppLocalization.string("Tap the flashcard to flip it.", locale: appPreferences.resolvedLocale)
            )
            .accessibilityAddTraits(.isButton)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isActive) { _, newValue in
            guard !newValue else { return }
            withTransaction(Transaction(animation: nil)) {
                isFlipped = false
            }
        }
    }

    private func flipCard() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.58)

        if reduceMotion {
            isFlipped.toggle()
        } else {
            withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 0.85)) {
                isFlipped.toggle()
            }
        }
    }

    private static let frontZoneID = UUID(uuidString: "49131036-5B53-43B4-B25E-DC343C0AB4A9")!
    private static let backZoneID = UUID(uuidString: "AE80CD1B-B8F2-43DB-8685-773CD0F6D18A")!

    private static func formulaZone(id: UUID, text: String) -> ZoneModel {
        var zone = ZoneModel()
        zone.id = id
        zone.contentType = .text
        zone.text = text
        zone.textStyle = .body
        zone.sizeMode = .fillWidth
        zone.blockAlignment = .center
        zone.verticalAlignment = .center
        return zone
    }
}

private struct LatexSupportOnboardingLayoutMetrics {
    let containerSize: CGSize

    private var width: CGFloat {
        max(containerSize.width, 1)
    }

    private var height: CGFloat {
        max(containerSize.height, 1)
    }

    var contentScale: CGFloat {
        min(max(width / 390, 0.88), 1.35)
    }

    var cardWidth: CGFloat {
        min(
            width * 0.94,
            height * 0.93 * 0.72,
            380 * contentScale
        )
    }

    var cardHeight: CGFloat {
        cardWidth / 0.72
    }
}

/// Lets the user choose the only onboarding preference with immediate study value.
private struct CardsTargetOnboardingPage: View {
    @Environment(AppPreferences.self) private var appPreferences

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

    private var pickerSelection: Binding<Int> {
        Binding {
            tickSelection - 1
        } set: { newSelection in
            setTickSelection(newSelection + 1)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = CardsTargetOnboardingLayoutMetrics(containerSize: proxy.size)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: metrics.valueLabelSpacing) {
                    Text("\(cardsTarget)")
                        .font(.system(size: metrics.valueFontSize, weight: .heavy).monospacedDigit())
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .statusTextMotion(trigger: cardsTarget)

                    Text(AppLocalization.string("cards per day", locale: appPreferences.resolvedLocale))
                        .font(.system(size: metrics.labelFontSize, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.86))
                }
                .frame(height: metrics.valueBlockHeight)

                Circle()
                    .fill(Color.primary.opacity(0.20))
                    .frame(width: metrics.markerSize, height: metrics.markerSize)
                    .padding(.top, metrics.markerTopSpacing)

                TickPicker(
                    count: tickUpperBound - 1,
                    config: metrics.pickerConfig,
                    selection: pickerSelection,
                    highlightedRange: nil
                )
                .padding(.top, metrics.pickerTopSpacing)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: metrics.contentMaxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: metrics.contentVerticalOffset)
            .padding(.horizontal, metrics.horizontalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setTickSelection(_ selection: Int) {
        cardsTarget = min(selection, tickUpperBound) * AppPreferences.dailyCardsGoalStep
        appPreferences.dailyCardsGoal = cardsTarget
    }
}

private struct CardsTargetOnboardingLayoutMetrics {
    let containerSize: CGSize

    private var width: CGFloat {
        max(containerSize.width, 1)
    }

    private var height: CGFloat {
        max(containerSize.height, 1)
    }

    private var contentScale: CGFloat {
        min(max(width / 390, 0.90), 1.28)
    }

    var contentMaxWidth: CGFloat {
        min(width, 560)
    }

    var horizontalPadding: CGFloat {
        max(width * 0.075, UIConstants.Spacing.large)
    }

    var contentVerticalOffset: CGFloat {
        min(max(height * 0.070, 38), 68)
    }

    var valueFontSize: CGFloat {
        54 * contentScale
    }

    var labelFontSize: CGFloat {
        20 * contentScale
    }

    var valueLabelSpacing: CGFloat {
        2 * contentScale
    }

    var valueBlockHeight: CGFloat {
        82 * contentScale
    }

    var markerSize: CGFloat {
        7 * contentScale
    }

    var markerTopSpacing: CGFloat {
        16 * contentScale
    }

    var pickerTopSpacing: CGFloat {
        10 * contentScale
    }

    var pickerConfig: TickPickerConfig {
        let accent = ThemeManager.shared.accentColor.color

        return TickPickerConfig(
            tickWidth: 3 * contentScale,
            tickHeight: 30 * contentScale,
            tickHPadding: 8 * contentScale,
            inActiveHeightProgress: 0.48,
            interactionHeight: 66 * contentScale,
            tickAreaTopPadding: 4 * contentScale,
            activeTint: accent.opacity(0.98),
            inActiveTint: accent.opacity(0.72),
            alignment: .bottom
        )
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
    .environment(DevelopmentPreferences.shared)
}

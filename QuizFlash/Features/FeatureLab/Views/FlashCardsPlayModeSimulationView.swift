//
//  FlashCardsPlayModeSimulationView.swift
//  QuizFlash
//
//  Dedicated Labs sandbox for iterating on flashcards swipe motion and chrome.
//

import Lottie
import Observation
import SwiftUI

private enum FlashCardsSwipeArrowPhase {
    case idle
    case tracking
    case commit
    case exit
}

private struct FlashCardsSwipeArrowPresentation: Equatable {
    var phase: FlashCardsSwipeArrowPhase = .idle
    var direction: SwipeDirection?
    var displayProgress: CGFloat = 0
    var commitStartProgress: CGFloat = 0
    var dismissFlightProgress: CGFloat = 0
    var displacementX: CGFloat = 0
    var commitToken = 0
    var fastSwipeDetected = false

    static let idle = FlashCardsSwipeArrowPresentation()
}

private enum FlashCardsSwipeArrowAnimationResource {
    static let name = "swipe_arrow"

    static let animation: LottieAnimation? = {
        if let animation = LottieAnimation.named(
            name,
            bundle: .main,
            subdirectory: "Features/FeatureLab/Resources/Lottie"
        ) {
            return animation
        }

        if let animation = LottieAnimation.named(name, bundle: .main) {
            return animation
        }

        guard let url = resolvedURL(in: .main) else { return nil }
        return LottieAnimation.filepath(url.path)
    }()

    private static func resolvedURL(in bundle: Bundle) -> URL? {
        let exactName = "\(name).json"

        let directCandidates: [URL?] = [
            bundle.url(forResource: name, withExtension: "json"),
            bundle.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "Features/FeatureLab/Resources/Lottie"
            ),
            bundle.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "FeatureLab/Resources/Lottie"
            )
        ]

        if let exactMatch = directCandidates.compactMap(\.self).first {
            return exactMatch
        }

        guard let resourceURL = bundle.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: resourceURL,
                includingPropertiesForKeys: nil
              )
        else {
            return nil
        }

        for case let candidateURL as URL in enumerator {
            if candidateURL.lastPathComponent == exactName {
                return candidateURL
            }
        }

        return nil
    }
}

struct FlashCardsPlayModeSimulationView: View {
    private struct BufferedCardEntry: Identifiable {
        let displayTurn: Int
        let bufferIndex: Int
        let card: PlayableCard

        var id: String { "\(displayTurn)-\(bufferIndex)-\(card.cardNumber)" }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let runtime = FeatureLabFixtures.shared

    @State private var swipeCount = 0
    @State private var leftSwipeCount = 0
    @State private var rightSwipeCount = 0
    @State private var isFlipped = false
    @State private var showsDeveloperPanel = false
    @State private var developerSwipeDebugState = FlashCardsPlayModeSimulationDebugState()
    @State private var liveSwipeFeedbackSnapshot = SwipeProgressSnapshot.idle
    @State private var swipeFeedbackLiveDirection: SwipeDirection?
    @State private var swipeFeedbackLiveProgress: CGFloat = 0
    @State private var swipeFeedbackLiveDisplacementX: CGFloat = 0
    @State private var swipeFeedbackThresholdLocked = false
    @State private var swipeFeedbackDisplayDirection: SwipeDirection?
    @State private var swipeFeedbackDisplayProgress: CGFloat = 0
    @State private var swipeFeedbackDisplayDisplacementX: CGFloat = 0
    @State private var swipeFeedbackCommitStartProgress: CGFloat = 0
    @State private var swipeFeedbackCommitToken = 0
    @State private var swipeFeedbackFastSwipeDetected = false
    @State private var swipeFeedbackDismissFlightProgress: CGFloat = 0
    @State private var swipeFeedbackIsLatched = false
    @State private var swipeFeedbackHideTask: Task<Void, Never>?
    @State private var swipeFeedbackLiveHideTask: Task<Void, Never>?

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var chromeButtonSize: CGFloat { UIConstants.Size.capsuleHeight }
    private var playSurfaceHorizontalPadding: CGFloat { 8 }
    private var preloadBufferDepth: Int { 1 }
    private var promotedCardScale: CGFloat { 0.952 }
    private var promotedCardSpring: Animation { .spring(response: 0.36, dampingFraction: 0.84) }
    private var accentColor: Color { ThemeManager.shared.accentColor.color }

    private var simulationCards: [PlayableCard] {
        runtime.flashCardsPlayModeSimulationCards
    }

    private var currentPlayableCard: PlayableCard? {
        guard !simulationCards.isEmpty else { return nil }
        return simulationCards[swipeCount % simulationCards.count]
    }

    private var reviewedProgressFraction: CGFloat {
        guard !simulationCards.isEmpty else { return 0 }
        let cycleProgress = swipeCount % simulationCards.count
        return CGFloat(cycleProgress) / CGFloat(simulationCards.count)
    }

    private var currentLoopNumber: Int {
        guard !simulationCards.isEmpty else { return 1 }
        return (swipeCount / simulationCards.count) + 1
    }

    var body: some View {
        GeometryReader { proxy in
            let safeBottomInset = proxy.safeAreaInsets.bottom

            ZStack(alignment: .top) {
                CardPreviewModeBackground()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    playModeHeader
                        .padding(.bottom, isCompact ? 16 : 24)

                    cardArea
                        .padding(.horizontal, playSurfaceHorizontalPadding)
                        .padding(.bottom, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                simulationDeveloperToolsOverlay(safeBottomInset: safeBottomInset)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .hideTabBarOnPush()
        .swipeBack { dismiss() }
        .onDisappear {
            showsDeveloperPanel = false
            developerSwipeDebugState.showsLiveSwipeOverlay = false
            resetSwipeFeedbackPresentation()
            developerSwipeDebugState.reset()
        }
        .onChange(of: swipeCount) { _, _ in
            liveSwipeFeedbackSnapshot = .idle
            resetLiveSwipeFeedback()
            developerSwipeDebugState.reset()
        }
    }

    private var playModeHeader: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            VStack(spacing: 8) {
                Text(runtime.flashCardsPlayModeSimulationDeckTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                simulationProgressChrome
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(height: chromeButtonSize)

            Button(action: toggleDeveloperPanel) {
                Image(systemName: showsDeveloperPanel ? "slider.horizontal.3.circle.fill" : "slider.horizontal.3")
                    .font(.system(size: 18, weight: .bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(showsDeveloperPanel ? accentColor : .primary)
                    .frame(width: chromeButtonSize, height: chromeButtonSize)
            }
            .buttonStyle(.plain)

            Button(action: dismiss.callAsFunction) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                    .frame(width: chromeButtonSize, height: chromeButtonSize)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, UIConstants.Layout.deckNavigationTopPadding)
        .padding(.horizontal, playSurfaceHorizontalPadding)
    }

    private var simulationProgressChrome: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))

                Capsule()
                    .fill(simulationProgressGradient)
                    .frame(width: proxy.size.width * reviewedProgressFraction)
                    .animation(.selectionToolbarSpring, value: swipeCount)
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .frame(maxWidth: .infinity)
    }

    private var simulationProgressGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.red.opacity(0.88),
                Color.orange,
                Color.yellow,
                Color.green.opacity(0.96)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var cardArea: some View {
        ZStack {
            if !simulationCards.isEmpty {
                ForEach(bufferedCardEntries) { entry in
                    let isCurrentCard = entry.displayTurn == swipeCount
                    let flipBinding = isCurrentCard ? $isFlipped : .constant(false)

                    GameplayCard(
                        card: entry.card,
                        onSwipe: { direction in
                            handleSwipe(direction)
                        },
                        isInteractionEnabled: isCurrentCard,
                        tapAnimationStyle: developerSwipeDebugState.tapAnimationStyle,
                        staticSwapTextMotion: developerSwipeDebugState.staticSwapTextMotion,
                        contentAlignment: developerSwipeDebugState.contentAlignment,
                        textSize: developerSwipeDebugState.textSize,
                        onSwipeProgress: resolvedSwipeProgressHandler(isCurrentCard: isCurrentCard),
                        swipeGestureTuning: resolvedSwipeGestureTuning,
                        isFlipped: flipBinding
                    )
                    .opacity(isCurrentCard ? 1 : 0.001)
                    .scaleEffect(isCurrentCard ? 1 : promotedCardScale)
                    .allowsHitTesting(isCurrentCard)
                    .accessibilityHidden(!isCurrentCard)
                    .zIndex(isCurrentCard ? 10 : Double(preloadBufferDepth - entry.bufferIndex))
                    .animation(promotedCardSpring, value: isCurrentCard)
                    .transition(.asymmetric(
                        insertion: .identity,
                        removal: .opacity
                    ))
                }

                swipeDirectionFeedbackOverlay
                    .zIndex(50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.20, dampingFraction: 0.86), value: swipeCount)
    }

    private var bufferedCardEntries: [BufferedCardEntry] {
        guard !simulationCards.isEmpty else { return [] }

        return (0...preloadBufferDepth).map { offset in
            let displayTurn = swipeCount + offset
            let card = simulationCards[displayTurn % simulationCards.count]
            return BufferedCardEntry(
                displayTurn: displayTurn,
                bufferIndex: offset,
                card: card
            )
        }
    }

    @ViewBuilder
    private var swipeDirectionFeedbackOverlay: some View {
        SwipeArrowAnimatedObjectView(
            presentation: swipeArrowFeedbackPresentation,
            isCompact: isCompact,
            tuning: swipeArrowFeedbackTuning
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var swipeArrowFeedbackPresentation: SwipeArrowAnimatedObjectPresentation {
        if let direction = swipeFeedbackDisplayDirection {
            return SwipeArrowAnimatedObjectPresentation(
                phase: swipeFeedbackDismissFlightProgress > 0.001 ? .exit : .commit,
                direction: direction,
                displayProgress: swipeFeedbackDisplayProgress,
                commitStartProgress: swipeFeedbackCommitStartProgress,
                dismissFlightProgress: swipeFeedbackDismissFlightProgress,
                displacementX: swipeFeedbackDisplayDisplacementX,
                commitToken: swipeFeedbackCommitToken,
                fastSwipeDetected: swipeFeedbackFastSwipeDetected
            )
        }

        if let direction = swipeFeedbackLiveDirection,
           swipeFeedbackLiveProgress > 0.001 {
            return SwipeArrowAnimatedObjectPresentation(
                phase: .tracking,
                direction: direction,
                displayProgress: swipeFeedbackLiveProgress,
                displacementX: swipeFeedbackLiveDisplacementX,
                commitToken: swipeFeedbackCommitToken
            )
        }

        return .idle
    }

    private var swipeArrowFeedbackTuning: SwipeArrowAnimatedObjectTuning {
        SwipeArrowAnimatedObjectTuning(
            deadZone: developerSwipeDebugState.displayDeadZone,
            displayCurve: developerSwipeDebugState.displayCurve,
            baseWidth: developerSwipeDebugState.arrowBaseWidth,
            commitEndProgress: 1,
            commitDuration: 0.62,
            fastCommitDuration: 0.46,
            minimumCommitSpeed: 1
        )
    }

    private func resolvedSwipeFeedbackProgress(for direction: SwipeDirection) -> CGFloat {
        let liveProgress = swipeFeedbackLiveDirection == direction ? swipeFeedbackLiveProgress : 0
        let latchedProgress = swipeFeedbackDisplayDirection == direction ? swipeFeedbackDisplayProgress : 0
        return max(liveProgress, latchedProgress)
    }

    private func resolvedSwipeFeedbackVisualProgress(from rawProgress: CGFloat) -> CGFloat {
        let clampedProgress = min(max(rawProgress, 0), 1)
        let deadZone = developerSwipeDebugState.displayDeadZone
        guard clampedProgress > deadZone else { return 0 }

        let normalized = (clampedProgress - deadZone) / max(1 - deadZone, 0.001)
        return pow(min(max(normalized, 0), 1), developerSwipeDebugState.displayCurve)
    }

    private func simulationDeveloperToolsOverlay(safeBottomInset: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if developerSwipeDebugState.showsLiveSwipeOverlay {
                FlashCardsPlayModeSimulationSwipeHUD(
                    snapshot: liveSwipeFeedbackSnapshot,
                    liveDirection: swipeFeedbackLiveDirection,
                    liveProgress: swipeFeedbackLiveProgress,
                    latchedDirection: swipeFeedbackDisplayDirection,
                    latchedProgress: swipeFeedbackDisplayProgress,
                    leftShownProgress: resolvedSwipeFeedbackProgress(for: .left),
                    rightShownProgress: resolvedSwipeFeedbackProgress(for: .right),
                    isLatched: swipeFeedbackIsLatched,
                    onClose: closeDeveloperSwipeOverlay
                )
                .padding(.horizontal, UIConstants.Layout.compactScreenEdgeInset)
                .padding(.bottom, safeBottomInset + 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            VStack(alignment: .trailing, spacing: UIConstants.Spacing.medium) {
                if showsDeveloperPanel {
                    FlashCardsPlayModeSimulationControlPanel(
                        state: developerSwipeDebugState,
                        swipeCount: swipeCount,
                        currentLoopNumber: currentLoopNumber,
                        leftSwipeCount: leftSwipeCount,
                        rightSwipeCount: rightSwipeCount,
                        onReset: resetSimulation,
                        onClose: closeDeveloperPanel
                    )
                    .frame(maxWidth: 320)
                    .transition(
                        AnyTransition.move(edge: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.96, anchor: .bottomTrailing))
                    )
                }
            }
            .padding(.horizontal, UIConstants.Layout.compactScreenEdgeInset)
            .padding(.bottom, safeBottomInset + 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.circularProgressSpring, value: showsDeveloperPanel)
        .animation(.circularProgressSpring, value: developerSwipeDebugState.showsLiveSwipeOverlay)
    }

    private func toggleDeveloperPanel() {
        withAnimation(.circularProgressSpring) {
            showsDeveloperPanel.toggle()
        }
    }

    private func closeDeveloperPanel() {
        withAnimation(.circularProgressSpring) {
            showsDeveloperPanel = false
        }
    }

    private func closeDeveloperSwipeOverlay() {
        withAnimation(.circularProgressSpring) {
            developerSwipeDebugState.showsLiveSwipeOverlay = false
        }
    }

    private func handleSwipe(_ direction: SwipeDirection) {
        switch direction {
        case .left:
            leftSwipeCount += 1
        case .right:
            rightSwipeCount += 1
        }

        isFlipped = false
        swipeCount += 1
    }

    private func cycleCurrentCard() {
        resetSwipeFeedbackPresentation()
        isFlipped = false
        swipeCount += 1
    }

    private func resetSimulation() {
        swipeCount = 0
        leftSwipeCount = 0
        rightSwipeCount = 0
        isFlipped = false
        developerSwipeDebugState.reset()
        resetSwipeFeedbackPresentation()
    }

    private func resolvedSwipeProgressHandler(isCurrentCard: Bool) -> ((SwipeProgressSnapshot) -> Void)? {
        guard isCurrentCard else { return nil }

        return { snapshot in
            liveSwipeFeedbackSnapshot = snapshot
            updateLiveSwipeFeedback(with: snapshot)
            updateSwipeFeedbackPresentation(with: snapshot)
            developerSwipeDebugState.update(with: snapshot)
        }
    }

    private var resolvedSwipeGestureTuning: SwipeGestureTuning {
        SwipeGestureTuning(
            flickSensitivity: developerSwipeDebugState.flickSensitivity,
            dismissDistanceThreshold: developerSwipeDebugState.dismissDistanceThreshold,
            usesDirectTiltTracking: true,
            dismissMotionStyle: .linear,
            dismissAnimationSpeed: developerSwipeDebugState.dismissAnimationSpeed
        )
    }

    private func updateSwipeFeedbackPresentation(with snapshot: SwipeProgressSnapshot) {
        switch snapshot.phase {
        case .idle:
            if !swipeFeedbackIsLatched {
                softenLiveSwipeFeedbackOut()
            }
        case .dragging:
            break
        case .cancelled:
            if !swipeFeedbackIsLatched {
                softenLiveSwipeFeedbackOut()
            }
        case .committed:
            if let direction = snapshot.committedDirection,
               !swipeFeedbackIsLatched {
                latchSwipeFeedback(with: snapshot, for: direction)
            }
        }
    }

    private func updateLiveSwipeFeedback(with snapshot: SwipeProgressSnapshot) {
        guard snapshot.phase == .dragging else { return }

        swipeFeedbackLiveHideTask?.cancel()
        swipeFeedbackLiveHideTask = nil

        if swipeFeedbackIsLatched,
           abs(snapshot.displacementX) > 6 {
            interruptLatchedSwipeFeedbackForNewDrag()
        }

        let rawDistanceProgress = min(max(snapshot.distanceProgress, 0), 1)
        let progress = pow(rawDistanceProgress, 0.9)
        let showThreshold: CGFloat = 0.08
        let resetThreshold: CGFloat = 0.035
        let reversalSwitchThreshold: CGFloat = 0.16
        let thresholdLockThreshold: CGFloat = 0.995
        let thresholdUnlockThreshold: CGFloat = 0.90

        guard let direction = snapshot.direction else {
            if swipeFeedbackLiveProgress <= resetThreshold || progress <= resetThreshold {
                resetLiveSwipeFeedback()
            } else {
                collapseLiveSwipeFeedback()
            }
            return
        }

        if swipeFeedbackThresholdLocked,
           swipeFeedbackLiveDirection == direction,
           rawDistanceProgress >= thresholdUnlockThreshold {
            swipeFeedbackLiveProgress = 1
            swipeFeedbackLiveDisplacementX = snapshot.displacementX
            return
        }

        if swipeFeedbackThresholdLocked,
           swipeFeedbackLiveDirection == direction {
            releaseThresholdLockedLiveSwipeFeedback(
                to: progress,
                displacementX: snapshot.displacementX
            )
            return
        }

        if swipeFeedbackThresholdLocked {
            swipeFeedbackThresholdLocked = false
        }

        guard let currentDirection = swipeFeedbackLiveDirection else {
            if progress >= showThreshold {
                swipeFeedbackLiveDirection = direction
                swipeFeedbackLiveProgress = rawDistanceProgress >= thresholdLockThreshold ? 1 : progress
                swipeFeedbackLiveDisplacementX = snapshot.displacementX
                swipeFeedbackThresholdLocked = rawDistanceProgress >= thresholdLockThreshold
            } else {
                resetLiveSwipeFeedback()
            }
            return
        }

        if currentDirection == direction {
            if progress <= resetThreshold {
                resetLiveSwipeFeedback()
            } else if rawDistanceProgress >= thresholdLockThreshold {
                swipeFeedbackLiveProgress = 1
                swipeFeedbackLiveDisplacementX = snapshot.displacementX
                swipeFeedbackThresholdLocked = true
            } else {
                swipeFeedbackLiveProgress = progress
                swipeFeedbackLiveDisplacementX = snapshot.displacementX
            }
            return
        }

        if progress < reversalSwitchThreshold {
            collapseLiveSwipeFeedback()
            if progress <= resetThreshold {
                swipeFeedbackLiveDirection = nil
            }
            return
        }

        if swipeFeedbackLiveProgress > resetThreshold {
            collapseLiveSwipeFeedback()
            return
        }

        swipeFeedbackLiveDirection = direction
        swipeFeedbackLiveProgress = progress
        swipeFeedbackLiveDisplacementX = snapshot.displacementX
    }

    private func latchSwipeFeedback(with snapshot: SwipeProgressSnapshot, for direction: SwipeDirection) {
        swipeFeedbackHideTask?.cancel()
        swipeFeedbackLiveHideTask?.cancel()
        resetSwipeFeedbackDismissFlight()
        swipeFeedbackIsLatched = true
        swipeFeedbackDisplayDirection = direction
        let initialProgress = max(
            resolvedSwipeFeedbackProgress(for: direction),
            snapshot.fastSwipeDetected ? 0.48 : 0.38
        )
        swipeFeedbackCommitStartProgress = initialProgress
        swipeFeedbackDisplayProgress = initialProgress
        swipeFeedbackDisplayDisplacementX = snapshot.displacementX
        swipeFeedbackFastSwipeDetected = snapshot.fastSwipeDetected
        swipeFeedbackCommitToken += 1
        resetLiveSwipeFeedback()
        swipeFeedbackDismissFlightProgress = 0

        withAnimation(resolvedSwipeFeedbackCommitAnimation(for: snapshot)) {
            swipeFeedbackDisplayProgress = 1
        }

        scheduleSwipeFeedbackDismissFlight(for: snapshot)
    }

    private func resolvedSwipeFeedbackCommitAnimation(for snapshot: SwipeProgressSnapshot) -> Animation {
        .spring(
            response: snapshot.fastSwipeDetected ? 0.24 : 0.29,
            dampingFraction: snapshot.fastSwipeDetected ? 0.80 : 0.84
        )
    }

    private func resolvedSwipeFeedbackDismissFlightLeadMilliseconds(for snapshot: SwipeProgressSnapshot) -> UInt64 {
        snapshot.fastSwipeDetected ? 110 : 150
    }

    private func resolvedSwipeFeedbackDismissFlightCleanupMilliseconds(
        for snapshot: SwipeProgressSnapshot
    ) -> UInt64 {
        snapshot.fastSwipeDetected ? 420 : 520
    }

    private func resolvedSwipeFeedbackDismissFlightAnimation(for snapshot: SwipeProgressSnapshot) -> Animation {
        .easeOut(duration: snapshot.fastSwipeDetected ? 0.24 : 0.30)
    }

    private func scheduleSwipeFeedbackDismissFlight(for snapshot: SwipeProgressSnapshot) {
        swipeFeedbackHideTask?.cancel()
        swipeFeedbackHideTask = Task { @MainActor in
            let leadMilliseconds = resolvedSwipeFeedbackDismissFlightLeadMilliseconds(for: snapshot)
            if leadMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(leadMilliseconds))
                guard !Task.isCancelled else { return }
            }

            withAnimation(resolvedSwipeFeedbackDismissFlightAnimation(for: snapshot)) {
                swipeFeedbackDismissFlightProgress = 1
            }

            try? await Task.sleep(
                for: .milliseconds(resolvedSwipeFeedbackDismissFlightCleanupMilliseconds(for: snapshot))
            )
            guard !Task.isCancelled else { return }

            swipeFeedbackIsLatched = false
            swipeFeedbackDisplayDirection = nil
            swipeFeedbackDisplayProgress = 0
            resetSwipeFeedbackDismissFlight()
            swipeFeedbackHideTask = nil
        }
    }

    private func softenLiveSwipeFeedbackOut() {
        guard swipeFeedbackLiveDirection != nil || swipeFeedbackLiveProgress > 0 else { return }

        swipeFeedbackLiveHideTask?.cancel()
        swipeFeedbackLiveHideTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.18)) {
                swipeFeedbackLiveProgress = 0
            }

            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }

            if swipeFeedbackLiveProgress <= 0.001 {
                swipeFeedbackLiveDirection = nil
                swipeFeedbackLiveDisplacementX = 0
                swipeFeedbackThresholdLocked = false
            }
            swipeFeedbackLiveHideTask = nil
        }
    }

    private func resetSwipeFeedbackPresentation() {
        swipeFeedbackHideTask?.cancel()
        swipeFeedbackHideTask = nil
        swipeFeedbackLiveHideTask?.cancel()
        swipeFeedbackLiveHideTask = nil
        liveSwipeFeedbackSnapshot = .idle
        resetLiveSwipeFeedback()
        swipeFeedbackIsLatched = false
        swipeFeedbackDisplayDirection = nil
        swipeFeedbackDisplayProgress = 0
        swipeFeedbackDisplayDisplacementX = 0
        swipeFeedbackCommitStartProgress = 0
        swipeFeedbackFastSwipeDetected = false
        resetSwipeFeedbackDismissFlight()
    }

    private func interruptLatchedSwipeFeedbackForNewDrag() {
        swipeFeedbackHideTask?.cancel()
        swipeFeedbackHideTask = nil
        swipeFeedbackIsLatched = false
        swipeFeedbackDisplayDirection = nil
        swipeFeedbackDisplayProgress = 0
        swipeFeedbackDisplayDisplacementX = 0
        swipeFeedbackCommitStartProgress = 0
        swipeFeedbackFastSwipeDetected = false
        resetSwipeFeedbackDismissFlight()
    }

    private func resetLiveSwipeFeedback() {
        swipeFeedbackLiveHideTask?.cancel()
        swipeFeedbackLiveHideTask = nil
        swipeFeedbackLiveDirection = nil
        swipeFeedbackLiveProgress = 0
        swipeFeedbackLiveDisplacementX = 0
        swipeFeedbackThresholdLocked = false
    }

    private func releaseThresholdLockedLiveSwipeFeedback(to progress: CGFloat, displacementX: CGFloat) {
        swipeFeedbackThresholdLocked = false
        withAnimation(.circularProgressSpring.speed(1.45)) {
            swipeFeedbackLiveProgress = progress
            swipeFeedbackLiveDisplacementX = displacementX
        }
    }

    private func collapseLiveSwipeFeedback() {
        swipeFeedbackThresholdLocked = false
        withAnimation(.easeOut(duration: 0.14)) {
            swipeFeedbackLiveProgress = 0
            swipeFeedbackLiveDisplacementX *= 0.42
        }
    }

    private func resetSwipeFeedbackDismissFlight() {
        swipeFeedbackDismissFlightProgress = 0
    }
}

private struct FlashCardsSwipeArrowFeedbackView: View {
    let presentation: FlashCardsSwipeArrowPresentation
    let isCompact: Bool
    let deadZone: CGFloat
    let displayCurve: CGFloat
    let trackingTravel: CGFloat
    let dismissTravel: CGFloat
    let baseWidth: CGFloat

    var body: some View {
        if direction != nil {
            ZStack {
                if FlashCardsSwipeArrowAnimationResource.animation != nil {
                    FlashCardsSwipeArrowLottieView(
                        presentation: presentation,
                        trackingAnimationProgress: trackingAnimationProgress,
                        commitStartAnimationProgress: commitStartAnimationProgress
                    )
                } else {
                    fallbackGlyph
                }
            }
            .padding(.horizontal, baseWidth * 0.10)
            .frame(width: baseWidth, height: baseWidth * 0.72)
            .rotationEffect(.degrees(rotationAngle))
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(x: offsetX, y: offsetY)
            .shadow(
                color: shadowColor.opacity(shadowOpacity),
                radius: shadowRadius,
                x: 0,
                y: shadowYOffset
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
        }
    }

    private var direction: SwipeDirection? {
        presentation.direction
    }

    private var directionSign: CGFloat {
        switch direction {
        case .left:
            -1
        case .right:
            1
        case nil:
            0
        }
    }

    private var visualProgress: CGFloat {
        resolvedVisualProgress(from: presentation.displayProgress)
    }

    private var commitEngageProgress: CGFloat {
        guard presentation.phase == .commit else { return 1 }

        let denominator = max(1 - presentation.commitStartProgress, 0.001)
        let normalizedProgress = (presentation.displayProgress - presentation.commitStartProgress) / denominator
        return resolvedEaseOut(normalizedProgress)
    }

    private var exitEase: CGFloat {
        resolvedEaseOut(presentation.dismissFlightProgress)
    }

    private var trackingAnimationProgress: CGFloat {
        resolvedAnimationProgress(from: presentation.displayProgress)
    }

    private var commitStartAnimationProgress: CGFloat {
        min(max(resolvedAnimationProgress(from: presentation.commitStartProgress), 0.08), 0.44)
    }

    private var trackingOffsetX: CGFloat {
        let progressTravel = trackingTravel * (0.42 + (visualProgress * 0.78))
        let displacementTravel = min(abs(presentation.displacementX) * 0.16, trackingTravel * 0.48)
        return directionSign * (progressTravel + displacementTravel)
    }

    private var committedBaseOffsetX: CGFloat {
        directionSign * max(abs(presentation.displacementX) * 0.18, trackingTravel * 0.88)
    }

    private var rotationAngle: Double {
        switch direction {
        case .left:
            180
        case .right:
            0
        case nil:
            0
        }
    }

    private var offsetX: CGFloat {
        switch presentation.phase {
        case .idle:
            0
        case .tracking:
            trackingOffsetX
        case .commit:
            trackingOffsetX + (directionSign * (isCompact ? 8 : 12) * commitEngageProgress)
        case .exit:
            committedBaseOffsetX + (directionSign * dismissTravel * exitEase)
        }
    }

    private var trackingOffsetY: CGFloat {
        -(isCompact ? 14 : 18) - (visualProgress * (isCompact ? 4 : 6))
    }

    private var offsetY: CGFloat {
        switch presentation.phase {
        case .idle:
            0
        case .tracking:
            trackingOffsetY
        case .commit:
            trackingOffsetY - ((isCompact ? 5 : 8) * commitEngageProgress)
        case .exit:
            trackingOffsetY - ((isCompact ? 12 : 18) * exitEase)
        }
    }

    private var scale: CGFloat {
        let trackingScale = 0.42 + (visualProgress * 0.38)
        let fastBoost: CGFloat = presentation.fastSwipeDetected ? 0.04 : 0

        return switch presentation.phase {
        case .idle:
            0.34
        case .tracking:
            trackingScale
        case .commit:
            trackingScale + (0.07 * commitEngageProgress) + fastBoost
        case .exit:
            0.88 - (0.10 * exitEase)
        }
    }

    private var opacity: Double {
        let trackingOpacity = min(0.96, 0.06 + (visualProgress * 0.94))

        return switch presentation.phase {
        case .idle:
            0
        case .tracking:
            Double(trackingOpacity)
        case .commit:
            Double(max(0.92, trackingOpacity))
        case .exit:
            Double(max(0, 1 - pow(exitEase, 1.08)))
        }
    }

    private var shadowColor: Color {
        Color(red: 0.24, green: 0.56, blue: 0.95)
    }

    private var shadowOpacity: Double {
        switch presentation.phase {
        case .idle:
            0
        case .tracking:
            Double(0.07 + (visualProgress * 0.08))
        case .commit:
            0.16
        case .exit:
            Double(0.10 * (1 - exitEase))
        }
    }

    private var shadowRadius: CGFloat {
        switch presentation.phase {
        case .idle:
            0
        case .tracking:
            isCompact ? 9 : 12
        case .commit:
            isCompact ? 12 : 14
        case .exit:
            isCompact ? 10 : 12
        }
    }

    private var shadowYOffset: CGFloat {
        switch presentation.phase {
        case .idle:
            0
        case .tracking:
            4
        case .commit:
            6
        case .exit:
            4
        }
    }

    private var fallbackGlyph: some View {
        Image(systemName: "chevron.forward.2")
            .font(.system(size: baseWidth * 0.34, weight: .black, design: .rounded))
            .foregroundStyle(Color(red: 0.35, green: 0.62, blue: 0.95))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resolvedVisualProgress(from rawProgress: CGFloat) -> CGFloat {
        let clampedProgress = min(max(rawProgress, 0), 1)
        guard clampedProgress > deadZone else { return 0 }

        let normalized = (clampedProgress - deadZone) / max(1 - deadZone, 0.001)
        return pow(min(max(normalized, 0), 1), displayCurve)
    }

    private func resolvedAnimationProgress(from rawProgress: CGFloat) -> CGFloat {
        0.04 + (resolvedVisualProgress(from: rawProgress) * 0.40)
    }

    private func resolvedEaseOut(_ progress: CGFloat) -> CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        return 1 - pow(1 - clampedProgress, 1.55)
    }
}

private struct FlashCardsSwipeArrowLottieView: UIViewRepresentable {
    let presentation: FlashCardsSwipeArrowPresentation
    let trackingAnimationProgress: CGFloat
    let commitStartAnimationProgress: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(animation: FlashCardsSwipeArrowAnimationResource.animation)
        view.backgroundBehavior = .pauseAndRestore
        view.contentMode = .scaleAspectFit
        view.currentProgress = 0
        view.animationSpeed = 1
        return view
    }

    func updateUIView(_ view: LottieAnimationView, context: Context) {
        context.coordinator.update(
            view,
            presentation: presentation,
            trackingAnimationProgress: trackingAnimationProgress,
            commitStartAnimationProgress: commitStartAnimationProgress
        )
    }

    final class Coordinator {
        private let commitEndProgress: CGFloat = 0.54
        private var lastCommitToken = -1
        private var lastPhase: FlashCardsSwipeArrowPhase = .idle

        func update(
            _ view: LottieAnimationView,
            presentation: FlashCardsSwipeArrowPresentation,
            trackingAnimationProgress: CGFloat,
            commitStartAnimationProgress: CGFloat
        ) {
            switch presentation.phase {
            case .idle:
                if view.isAnimationPlaying {
                    view.stop()
                }
                if abs(view.currentProgress) > 0.001 {
                    view.currentProgress = 0
                }
            case .tracking:
                if view.isAnimationPlaying {
                    view.stop()
                }
                let targetProgress = min(max(trackingAnimationProgress, 0.02), commitEndProgress - 0.06)
                if abs(view.currentProgress - targetProgress) > 0.002 {
                    view.currentProgress = targetProgress
                }
            case .commit:
                triggerCommitPlaybackIfNeeded(
                    on: view,
                    presentation: presentation,
                    commitStartAnimationProgress: commitStartAnimationProgress
                )
            case .exit:
                if presentation.commitToken != lastCommitToken {
                    triggerCommitPlaybackIfNeeded(
                        on: view,
                        presentation: presentation,
                        commitStartAnimationProgress: commitStartAnimationProgress
                    )
                }
            }

            lastPhase = presentation.phase
        }

        private func triggerCommitPlaybackIfNeeded(
            on view: LottieAnimationView,
            presentation: FlashCardsSwipeArrowPresentation,
            commitStartAnimationProgress: CGFloat
        ) {
            guard presentation.commitToken != lastCommitToken
                || !view.isAnimationPlaying
                || lastPhase == .tracking
            else {
                return
            }

            let startProgress = min(
                max(commitStartAnimationProgress, 0.06),
                commitEndProgress - 0.04
            )
            let segmentProgress = max(commitEndProgress - startProgress, 0.04)
            let animationDuration = view.animation?.duration ?? 2.24
            let desiredDuration = presentation.fastSwipeDetected ? 0.16 : 0.20
            let playbackSpeed = max(
                1.8,
                (animationDuration * Double(segmentProgress)) / desiredDuration
            )

            view.stop()
            view.currentProgress = startProgress
            view.animationSpeed = playbackSpeed
            view.play(
                fromProgress: startProgress,
                toProgress: commitEndProgress,
                loopMode: .playOnce,
                completion: nil
            )

            lastCommitToken = presentation.commitToken
        }
    }
}

@MainActor
@Observable
private final class FlashCardsPlayModeSimulationDebugState {
    var liveSnapshot: SwipeProgressSnapshot = .idle
    var showsLiveSwipeOverlay = false
    var flickSensitivity: CGFloat = 1.90
    var dismissDistanceThreshold: CGFloat = 180
    var dismissAnimationSpeed: CGFloat = 1
    var displayDeadZone: CGFloat = 0.12
    var displayCurve: CGFloat = 0.82
    var arrowBaseWidth: CGFloat = 28
    var tapAnimationStyle: FlashcardTapAnimationStyle = .flip3D
    var staticSwapTextMotion: FlashcardStaticSwapTextMotion = .animated
    var contentAlignment: FlashcardContentAlignment = .top
    var textSize: FlashcardTextSize = .large

    func update(with snapshot: SwipeProgressSnapshot) {
        liveSnapshot = snapshot
    }

    func reset() {
        liveSnapshot = .idle
    }
}

private struct FlashCardsPlayModeSimulationControlPanel: View {
    @Bindable var state: FlashCardsPlayModeSimulationDebugState
    let swipeCount: Int
    let currentLoopNumber: Int
    let leftSwipeCount: Int
    let rightSwipeCount: Int
    let onReset: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack {
                Text("Play Simulation")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                closeButton
            }

            HStack(spacing: 8) {
                statBadge("Loop \(currentLoopNumber)", tint: .secondary)
                statBadge("\(swipeCount) swipes", tint: .cyan)
                statBadge("\(leftSwipeCount)L", tint: .red)
                statBadge("\(rightSwipeCount)R", tint: .green)
            }

            Toggle(isOn: $state.showsLiveSwipeOverlay) {
                panelLabel("Live Swipe HUD")
            }
            .tint(.cyan)

            developerSliderRow(
                title: "Flick Sensitivity",
                value: $state.flickSensitivity,
                range: 0.55...1.90,
                tint: .cyan
            )

            developerSliderRow(
                title: "Dismiss Distance",
                value: $state.dismissDistanceThreshold,
                range: 72...180,
                tint: .mint
            )

            developerSliderRow(
                title: "Dismiss Speed",
                value: $state.dismissAnimationSpeed,
                range: 0.40...2.20,
                tint: .orange
            )

            developerSliderRow(
                title: "Arrow Dead Zone",
                value: $state.displayDeadZone,
                range: 0...0.35,
                tint: .yellow
            )

            developerSliderRow(
                title: "Arrow Curve",
                value: $state.displayCurve,
                range: 0.35...1.6,
                tint: .pink
            )

            developerSliderRow(
                title: "Arrow Width",
                value: $state.arrowBaseWidth,
                range: 16...64,
                tint: .mint
            )

            VStack(alignment: .leading, spacing: 6) {
                panelLabel("Tap Animation")

                Picker("Tap Animation", selection: $state.tapAnimationStyle) {
                    ForEach(FlashcardTapAnimationStyle.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                panelLabel("Content Alignment")

                Picker("Content Alignment", selection: $state.contentAlignment) {
                    ForEach(FlashcardContentAlignment.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                panelLabel("Text Size")

                Picker("Text Size", selection: $state.textSize) {
                    ForEach(FlashcardTextSize.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Button(action: onReset) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset Simulation")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(UIConstants.Spacing.large)
        .flashcardStyle(
            cornerRadius: UIConstants.Radius.maximum,
            surfaceRole: .widget,
            baseBorderBlurRadius: 1
        )
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }

    private func statBadge(_ label: String, tint: Color) -> some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private func panelLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(.primary)
            .textCase(.uppercase)
    }

    private func developerSliderRow(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Spacer(minLength: 0)

                Text(Double(value.wrappedValue).formatted(.number.precision(.fractionLength(2))))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range)
                .tint(tint)
        }
    }
}

private struct FlashCardsPlayModeSimulationSwipeHUD: View {
    let snapshot: SwipeProgressSnapshot
    let liveDirection: SwipeDirection?
    let liveProgress: CGFloat
    let latchedDirection: SwipeDirection?
    let latchedProgress: CGFloat
    let leftShownProgress: CGFloat
    let rightShownProgress: CGFloat
    let isLatched: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack {
                Text("Swipe HUD")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .textCase(.uppercase)

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.primary)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                hudBadge("TRACK \(directionLabel(snapshot.direction))", color: badgeColor(snapshot.direction))
                hudBadge("PROJ \(directionLabel(snapshot.projectedCommitDirection))", color: badgeColor(snapshot.projectedCommitDirection))
                hudBadge("LIVE \(directionLabel(liveDirection))", color: badgeColor(liveDirection))
                hudBadge(isLatched ? "LATCHED" : "TRACK", color: isLatched ? .pink : .secondary)
                hudBadge(phaseLabel, color: .secondary)
            }

            HStack(spacing: 12) {
                hudMetric("Dist", percent(snapshot.distanceProgress))
                hudMetric("Tilt", angle(snapshot.tiltAngleDegrees))
                hudMetric("Vel", "\(Int(snapshot.velocityX.rounded()))")
                hudMetric("Proj", percent(snapshot.projectedProgress))
                hudMetric("Commit", percent(snapshot.commitIntentProgress))
            }

            HStack(spacing: 12) {
                hudMetric("Live", percent(liveProgress))
                hudMetric("Latch", latchedDirection == nil ? "0%" : percent(latchedProgress))
                hudMetric("L", percent(leftShownProgress))
                hudMetric("R", percent(rightShownProgress))
            }
        }
        .padding(UIConstants.Spacing.medium)
        .frame(maxWidth: 360)
        .flashcardStyle(
            cornerRadius: 22,
            surfaceRole: .widget,
            baseBorderBlurRadius: 1
        )
    }

    private func hudBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func hudMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func directionLabel(_ direction: SwipeDirection?) -> String {
        switch direction {
        case .left:
            "LEFT"
        case .right:
            "RIGHT"
        case nil:
            "IDLE"
        }
    }

    private var phaseLabel: String {
        switch snapshot.phase {
        case .idle:
            "IDLE"
        case .dragging:
            "DRAG"
        case .cancelled:
            "CANCEL"
        case .committed:
            "COMMIT"
        }
    }

    private func badgeColor(_ direction: SwipeDirection?) -> Color {
        switch direction {
        case .left:
            .red
        case .right:
            .green
        case nil:
            .secondary
        }
    }

    private func percent(_ value: CGFloat) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    private func angle(_ value: CGFloat) -> String {
        let clampedValue = abs(value) < 0.05 ? 0 : value
        return "\(String(format: "%.1f", clampedValue)) deg"
    }
}

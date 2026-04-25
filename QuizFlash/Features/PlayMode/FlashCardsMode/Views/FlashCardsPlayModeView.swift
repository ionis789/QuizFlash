//
//  FlashCardsPlayModeView.swift
//  QuizFlash
//
//  The primary playback screen for a swipe-to-rate flashcard session.
//  This view is intentionally "dumb" — it only renders ViewModel state
//  and forwards user interactions to `FlashCardsPlayModeViewModel`.
//

import SwiftUI
import SwiftData
import UIKit
import Observation

// MARK: - FlashCardsPlayModeView

/// The main play-mode screen.
///
/// Displays a stack of `GameplayCard` views one at a time, a header progress bar,
/// and a completion overlay with session statistics when all cards have been reviewed.
///
/// All business logic (XP, SRS, gamification) lives in `FlashCardsPlayModeViewModel`.
/// This view only reads observable state and calls ViewModel methods.
struct FlashCardsPlayModeView: View {
    private struct BufferedCardEntry: Identifiable {
        let displayIndex: Int
        let card: PlayableCard

        var id: PersistentIdentifier { card.id }
    }

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(DevelopmentPreferences.self) private var developmentPreferences

    // MARK: - Properties

    /// The deck being studied — passed from the parent and forwarded to the ViewModel.
    let deck: DeckModel

    /// Safe-area values passed by the custom full-screen sheet container.
    let safeAreaInsets: UIEdgeInsets

    /// The `@Observable` ViewModel that owns all session state.
    @Bindable var viewModel: FlashCardsPlayModeViewModel

    @State private var headerHeight: CGFloat = 0
    @State private var editingCard: CardModel?
    @State private var showsDeveloperPanel = false
    @State private var developerSwipeDebugState = PlayModeDeveloperSwipeDebugState()
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

    // MARK: - Convenience

    private var accentColor: Color { ThemeManager.shared.accentColor.color }
    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var chromeButtonSize: CGFloat { UIConstants.Size.capsuleHeight }
    private var playSurfaceHorizontalPadding: CGFloat { 8 }
    private var preloadBufferDepth: Int { 2 }
    private var dismissDragOverlapBelowHeader: CGFloat { isCompact ? 60 : 80 }
    private var promotedCardScale: CGFloat { 0.952 }
    private var promotedCardSpring: Animation { .spring(response: 0.36, dampingFraction: 0.84) }
    private var dragDismissActivationHeight: CGFloat {
        headerHeight + currentHeaderBottomPadding + dismissDragOverlapBelowHeader
    }
    private var resolvedDeckTitle: String {
        let trimmedTitle = viewModel.deck.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Untitled Deck" : trimmedTitle
    }
    private var currentHeaderBottomPadding: CGFloat { isCompact ? 16 : 24 }
    private var currentPlayableCard: PlayableCard? {
        guard viewModel.currentIndex < viewModel.cards.count else { return nil }
        return viewModel.cards[viewModel.currentIndex]
    }
    private var reviewedProgressFraction: CGFloat {
        guard viewModel.totalCardCount > 0 else { return 0 }
        return CGFloat(viewModel.reviewedCardCount) / CGFloat(viewModel.totalCardCount)
    }
    private var wrongShareWithinReviewed: CGFloat {
        let reviewed = max(viewModel.reviewedCardCount, 0)
        guard reviewed > 0 else { return 0 }
        return CGFloat(viewModel.wrongCards.count) / CGFloat(reviewed)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let resolvedSafeTopInset = max(safeAreaInsets.top, geo.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)
            let cardBottomPadding: CGFloat = 2

            ZStack {
                screenBackground
                    .ignoresSafeArea()

                if !viewModel.isComplete {
                    VStack(spacing: 0) {
                        header(
                            safeTopInset: resolvedSafeTopInset,
                            horizontalPadding: playSurfaceHorizontalPadding
                        )
                        .padding(.bottom, currentHeaderBottomPadding)

                        cardArea
                            .padding(.horizontal, playSurfaceHorizontalPadding)
                            .padding(.bottom, cardBottomPadding)
                            .ignoresSafeArea(edges: .bottom)
                    }
                    .transition(.opacity)

                    if AppFeatures.current.showsInternalLabs, developmentPreferences.playModeDeveloperModeEnabled {
                        playModeDeveloperToolsOverlay(safeBottomInset: resolvedSafeBottomInset)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                if viewModel.isComplete {
                    completionOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .fullScreenSheetDragActivationHeight(dragDismissActivationHeight)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.isComplete)
        .task {
            if !viewModel.isSessionStarted {
                await viewModel.startSession(container: modelContext.container)
            }
        }
        .onDisappear {
            guard editingCard == nil else { return }
            showsDeveloperPanel = false
            developerSwipeDebugState.showsLiveSwipeOverlay = false
            resetSwipeFeedbackPresentation()
            developerSwipeDebugState.reset()
            viewModel.tearDown()
        }
        .onChange(of: viewModel.currentIndex) { _, _ in
            liveSwipeFeedbackSnapshot = .idle
            resetLiveSwipeFeedback()
            developerSwipeDebugState.reset()
        }
        .onChange(of: developmentPreferences.playModeDeveloperModeEnabled) { _, isEnabled in
            guard !isEnabled else { return }
            showsDeveloperPanel = false
            developerSwipeDebugState.showsLiveSwipeOverlay = false
            developerSwipeDebugState.reset()
        }
        .fullScreenCover(item: $editingCard) { card in
            NavigationStack {
                FlashcardEditorView(frontZone: card.frontZone, backZone: card.backZone) { frontZone, backZone in
                    if card.frontZone != frontZone || card.backZone != backZone {
                        card.frontZone = frontZone
                        card.backZone = backZone
                        card.editedAt = Date()
                        deck.editedAt = Date()
                        Task {
                            await viewModel.refreshCardSnapshot(for: card.persistentModelID)
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Card Area

    private var cardArea: some View {
        ZStack {
            if viewModel.isSessionStarted {
                let bufferedCards = bufferedCardEntries

                if !bufferedCards.isEmpty {
                    @Bindable var bindableViewModel = viewModel

                    ForEach(bufferedCards) { entry in
                        let isCurrentCard = entry.card.id == currentPlayableCard?.id
                        let flipBinding = isCurrentCard
                            ? $bindableViewModel.isFlipped
                            : .constant(viewModel.settings.revealFlow == .answerFirst)

                        GameplayCard(
                            card: entry.card,
                            onSwipe: { direction in
                                viewModel.handleSwipe(direction)
                            },
                            isInteractionEnabled: isCurrentCard,
                            allowsTapToFlip: viewModel.settings.flipBehavior == .tapToFlip,
                            tapAnimationStyle: viewModel.settings.tapAnimationStyle,
                            staticSwapTextMotion: viewModel.settings.staticSwapTextMotion,
                            contentAlignment: viewModel.settings.contentAlignment,
                            onSwipeProgress: resolvedSwipeProgressHandler(isCurrentCard: isCurrentCard),
                            swipeGestureTuning: resolvedSwipeGestureTuning,
                            isFlipped: flipBinding
                        )
                        .opacity(isCurrentCard ? 1 : 0.001)
                        .scaleEffect(isCurrentCard ? 1 : promotedCardScale)
                        .allowsHitTesting(isCurrentCard)
                        .accessibilityHidden(!isCurrentCard)
                        .zIndex(isCurrentCard ? 10 : Double(preloadBufferDepth - (entry.displayIndex - viewModel.currentIndex)))
                        .animation(promotedCardSpring, value: isCurrentCard)
                        .transition(.asymmetric(
                            insertion: .identity,
                            removal: .opacity
                        ))
                    }
                }

                swipeDirectionFeedbackOverlay
                    .zIndex(50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.20, dampingFraction: 0.86), value: viewModel.currentIndex)
    }

    private var bufferedCardEntries: [BufferedCardEntry] {
        guard !viewModel.cards.isEmpty, viewModel.currentIndex < viewModel.cards.count else { return [] }
        let upperBound = min(viewModel.cards.count, viewModel.currentIndex + preloadBufferDepth + 1)
        return Array(viewModel.cards[viewModel.currentIndex..<upperBound].enumerated()).map { offset, card in
            BufferedCardEntry(
                displayIndex: viewModel.currentIndex + offset,
                card: card
            )
        }
    }

    // MARK: - Header

    private func header(safeTopInset: CGFloat, horizontalPadding: CGFloat) -> some View {
        VStack(spacing: UIConstants.Spacing.standard) {
            HStack(spacing: UIConstants.Spacing.small) {
                flashcardsTitleBlock
                    .frame(maxWidth: .infinity)

                editCurrentCardButton
                dismissButton
            }
        }
        .padding(.top, safeTopInset + 6)
        .padding(.horizontal, horizontalPadding)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            if abs(headerHeight - newHeight) > 0.5 {
                headerHeight = newHeight
            }
        }
    }

    private var flashcardsTitleBlock: some View {
        VStack(spacing: 8) {
            Text(resolvedDeckTitle)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            flashcardsProgressChrome
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: chromeButtonSize)
    }

    private var flashcardsProgressChrome: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))

                if reviewedProgressFraction > 0 {
                    reviewProgressFill
                        .frame(width: proxy.size.width * reviewedProgressFraction)
                        .animation(.selectionToolbarSpring, value: viewModel.reviewedCardCount)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var reviewProgressFill: some View {
        if wrongShareWithinReviewed <= 0 {
            Capsule()
                .fill(Color.green)
        } else if wrongShareWithinReviewed >= 1 {
            Capsule()
                .fill(Color.red)
        } else {
            Capsule()
                .fill(reviewProgressGradient)
        }
    }

    private var reviewProgressGradient: LinearGradient {
        let red = Color.red
        let orange = Color.orange
        let yellow = Color.yellow
        let green = Color.green
        let center = min(max(wrongShareWithinReviewed, 0), 1)
        let transitionHalfWidth: CGFloat = center == 0 || center == 1 ? 0 : 0.08
        let leftTransition = max(0, center - transitionHalfWidth)
        let rightTransition = min(1, center + transitionHalfWidth)

        return LinearGradient(
            stops: [
                .init(color: red.opacity(0.88), location: 0),
                .init(color: red, location: max(0, leftTransition * 0.72)),
                .init(color: orange, location: leftTransition),
                .init(color: yellow, location: center),
                .init(color: Color(red: 0.58, green: 0.84, blue: 0.12), location: rightTransition),
                .init(color: green.opacity(0.96), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var dismissButton: some View {
        Button(action: handleDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .bold))
                .fontDesign(.rounded)
                .foregroundStyle(.primary)
                .frame(width: chromeButtonSize, height: chromeButtonSize)
        }
        .buttonStyle(.plain)
    }

    private var editCurrentCardButton: some View {
        Button(action: openCurrentCardEditor) {
            Image(systemName: "pencil")
                .font(.system(size: 18, weight: .bold))
                .fontDesign(.rounded)
                .foregroundStyle(accentColor)
                .frame(width: chromeButtonSize, height: chromeButtonSize)
        }
        .buttonStyle(.plain)
        .disabled(currentPlayableCard == nil)
        .opacity(currentPlayableCard == nil ? 0.45 : 1)
    }

    private func openCurrentCardEditor() {
        guard let currentPlayableCard,
              let cardModel = modelContext.model(for: currentPlayableCard.id) as? CardModel else {
            return
        }
        editingCard = cardModel
    }

    // MARK: - Completion Overlay

    private var completionOverlay: some View {
        if viewModel.wrongCards.isEmpty {
            return PlayModeCompletionOverlay(
                headline: "Session Complete!",
                xpEarned: viewModel.sessionXP,
                stats: completionStats,
                primaryActionTitle: "Continue",
                primaryAction: { handleDismiss() },
                secondaryActionTitle: nil,
                secondaryAction: nil
            )
        }

        if viewModel.settings.retryWrongCards {
            return PlayModeCompletionOverlay(
                headline: "Session Complete!",
                xpEarned: viewModel.sessionXP,
                stats: completionStats,
                primaryActionTitle: "Retry Wrong Cards",
                primaryAction: { viewModel.retryWrongCards() },
                secondaryActionTitle: "Continue",
                secondaryAction: { handleDismiss() }
            )
        }

        return PlayModeCompletionOverlay(
            headline: "Session Complete!",
            xpEarned: viewModel.sessionXP,
            stats: completionStats,
            primaryActionTitle: "Continue",
            primaryAction: { handleDismiss() },
            secondaryActionTitle: nil,
            secondaryAction: nil
        )
    }

    private var completionStats: [PlayModeCompletionStat] {
        [
            PlayModeCompletionStat(
                title: "Accuracy",
                value: "\(viewModel.sessionAccuracy)%",
                icon: "target",
                color: .green
            ),
            PlayModeCompletionStat(
                title: "Time",
                value: viewModel.formattedSessionDuration,
                icon: "timer",
                color: .blue
            ),
            PlayModeCompletionStat(
                title: "Correct",
                value: "\(viewModel.correctCount)",
                icon: "checkmark.circle.fill",
                color: .green
            ),
            PlayModeCompletionStat(
                title: "Wrong",
                value: "\(viewModel.wrongCards.count)",
                icon: "xmark.circle.fill",
                color: .red
            )
        ]
    }

    // MARK: - Background

    private var screenBackground: some View {
        CardPreviewModeBackground()
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

    private func playModeDeveloperToolsOverlay(safeBottomInset: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if developerSwipeDebugState.showsLiveSwipeOverlay {
                PlayModeDeveloperSwipeOverlayHUD(
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
                    PlayModeDeveloperSwipePanel(
                        state: developerSwipeDebugState,
                        onClose: closeDeveloperPanel
                    )
                        .frame(maxWidth: 300)
                        .transition(playModeDeveloperPanelTransition)
                }

                Button(action: toggleDeveloperPanel) {
                    Image(systemName: showsDeveloperPanel ? "slider.horizontal.3.circle.fill" : "slider.horizontal.3")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(showsDeveloperPanel ? accentColor : .primary)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .flashcardStyle(
                    cornerRadius: 24,
                    surfaceRole: .widget,
                    baseBorderBlurRadius: showsDeveloperPanel ? 3 : 1
                )
            }
            .padding(.horizontal, UIConstants.Layout.compactScreenEdgeInset)
            .padding(.bottom, safeBottomInset + 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleDeveloperPanel() {
        withAnimation(.circularProgressSpring) {
            showsDeveloperPanel.toggle()
            if !showsDeveloperPanel {
                developerSwipeDebugState.reset()
            }
        }
    }

    private func closeDeveloperPanel() {
        withAnimation(.circularProgressSpring) {
            showsDeveloperPanel = false
            developerSwipeDebugState.reset()
        }
    }

    private func closeDeveloperSwipeOverlay() {
        withAnimation(.circularProgressSpring) {
            developerSwipeDebugState.showsLiveSwipeOverlay = false
        }
    }

    private func resolvedSwipeProgressHandler(
        isCurrentCard: Bool
    ) -> ((SwipeProgressSnapshot) -> Void)? {
        guard isCurrentCard else {
            return nil
        }

        return { snapshot in
            liveSwipeFeedbackSnapshot = snapshot
            updateLiveSwipeFeedback(with: snapshot)
            updateSwipeFeedbackPresentation(with: snapshot)

            if developmentPreferences.playModeDeveloperModeEnabled, showsDeveloperPanel {
                developerSwipeDebugState.update(with: snapshot)
            }
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

    private func handleDismiss() {
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            dismiss()
        }
    }

    private var playModeDeveloperPanelTransition: AnyTransition {
        AnyTransition.move(edge: .bottom)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.96, anchor: .bottomTrailing))
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

    private func latchSwipeFeedback(
        with snapshot: SwipeProgressSnapshot,
        for direction: SwipeDirection
    ) {
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

    private func resolvedSwipeFeedbackCommitAnimation(
        for snapshot: SwipeProgressSnapshot
    ) -> Animation {
        .spring(
            response: snapshot.fastSwipeDetected ? 0.24 : 0.29,
            dampingFraction: snapshot.fastSwipeDetected ? 0.80 : 0.84
        )
    }

    private func resolvedSwipeFeedbackDismissFlightLeadMilliseconds(
        for snapshot: SwipeProgressSnapshot
    ) -> UInt64 {
        snapshot.fastSwipeDetected ? 110 : 150
    }

    private func resolvedSwipeFeedbackDismissFlightCleanupMilliseconds(
        for snapshot: SwipeProgressSnapshot
    ) -> UInt64 {
        snapshot.fastSwipeDetected ? 420 : 520
    }

    private func resolvedSwipeFeedbackDismissFlightAnimation(
        for snapshot: SwipeProgressSnapshot
    ) -> Animation {
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

@MainActor
@Observable
private final class PlayModeDeveloperSwipeDebugState {
    var liveSnapshot: SwipeProgressSnapshot = .idle
    var showsLiveSwipeOverlay = false
    var flickSensitivity: CGFloat = 1.90
    var dismissDistanceThreshold: CGFloat = 180
    var dismissAnimationSpeed: CGFloat = 1
    var displayDeadZone: CGFloat = 0.12
    var displayCurve: CGFloat = 0.82
    var arrowBaseWidth: CGFloat = 28

    var displayProgress: CGFloat {
        let clampedDeadZone = min(max(displayDeadZone, 0), 0.95)
        let normalized = max(0, liveSnapshot.commitIntentProgress - clampedDeadZone) / max(1 - clampedDeadZone, 0.001)
        return pow(min(max(normalized, 0), 1), max(displayCurve, 0.2))
    }

    func update(with snapshot: SwipeProgressSnapshot) {
        liveSnapshot = snapshot
    }

    func reset() {
        liveSnapshot = .idle
    }
}

private struct PlayModeDeveloperSwipePanel: View {
    @Bindable var state: PlayModeDeveloperSwipeDebugState
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack {
                Text("Play Debug")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                closeButton
            }

            HStack {
                Spacer(minLength: 0)

                if state.liveSnapshot.fastSwipeDetected {
                    Text("FLICK")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.cyan.opacity(0.16), in: Capsule())
                }

                Text(directionLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(directionColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(directionColor.opacity(0.14), in: Capsule())

                Text(phaseLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }

            progressRow(
                title: "Distance",
                value: state.liveSnapshot.distanceProgress,
                tint: .cyan
            )

            progressRow(
                title: "Velocity",
                value: state.liveSnapshot.velocityProgress,
                tint: .orange,
                valueText: velocityText
            )

            progressRow(
                title: "Projected",
                value: state.liveSnapshot.projectedProgress,
                tint: .yellow
            )

            progressRow(
                title: "Commit Intent",
                value: state.liveSnapshot.commitIntentProgress,
                tint: .red
            )

            progressRow(
                title: "Display Progress",
                value: state.displayProgress,
                tint: .green
            )

            Toggle(isOn: $state.showsLiveSwipeOverlay) {
                Text("Live Swipe HUD")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .textCase(.uppercase)
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
        .accessibilityLabel("Close debug panel")
    }

    private var directionLabel: String {
        switch state.liveSnapshot.direction {
        case .left:
            "LEFT"
        case .right:
            "RIGHT"
        case nil:
            "IDLE"
        }
    }

    private var phaseLabel: String {
        switch state.liveSnapshot.phase {
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

    private var directionColor: Color {
        switch state.liveSnapshot.direction {
        case .left:
            .red
        case .right:
            .green
        case nil:
            .secondary
        }
    }

    private func progressRow(title: String, value: CGFloat, tint: Color) -> some View {
        progressRow(title: title, value: value, tint: tint, valueText: progressText(for: value))
    }

    private func progressRow(title: String, value: CGFloat, tint: Color, valueText: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Spacer(minLength: 0)

                Text(valueText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))

                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * min(max(value, 0), 1))
                }
            }
            .frame(height: 8)
        }
    }

    private var velocityText: String {
        let velocity = Int(state.liveSnapshot.velocityX.rounded())
        return "\(velocity) pt/s"
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

    private func progressText(for value: CGFloat) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }
}

private struct PlayModeDeveloperSwipeOverlayHUD: View {
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

// MARK: - iOS 17 Retain-Cycle Wrapper

/// Wraps `FlashCardsPlayModeView` to avoid the iOS 17 retain-cycle caused by
/// `.fullScreenCover` permanently retaining a `@State` ViewModel initialised
/// inside `init()`.
///
/// The ViewModel is created lazily on first appearance via `.onAppear`, ensuring
/// the closure-based initialisation escapes the cover's internal storage before
/// the persistent reference is established.
struct DefaultModePlay: View {
    @Environment(ThemeManager.self) private var themeManager

    let deck: DeckModel
    var safeAreaInsets: UIEdgeInsets = .zero

    @State private var viewModel: FlashCardsPlayModeViewModel? = nil

    var body: some View {
        Group {
            if let vm = viewModel {
                FlashCardsPlayModeView(
                    deck: deck,
                    safeAreaInsets: safeAreaInsets,
                    viewModel: vm
                )
            } else {
                themeManager.screenBackground
                    .onAppear {
                        if self.viewModel == nil {
                            self.viewModel = FlashCardsPlayModeViewModel(
                                deck: deck,
                                settings: deck.playModeSettings?.flashcardSettings ?? FlashcardModeSettings()
                            )
                        }
                    }
            }
        }
    }
}

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
        struct Identity: Hashable {
            let runGeneration: Int
            let cardID: PersistentIdentifier
        }

        let runGeneration: Int
        let displayIndex: Int
        let card: PlayableCard

        var id: Identity {
            Identity(runGeneration: runGeneration, cardID: card.id)
        }
    }

    private enum ScoreZoneEdge {
        case leading
        case trailing
    }

    private enum DebugCardCaptureState: Equatable {
        case idle
        case saved
        case failed
    }

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(DevelopmentPreferences.self) private var developmentPreferences
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

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
    @State private var currentLayoutDebugSnapshotsByFace: [String: ZoneContentLayoutDebugSnapshot] = [:]
    @State private var currentLayoutDebugCardID: PersistentIdentifier?
    @State private var didCopyFloatingLayoutDebug = false
    @State private var debugCardCaptureState = DebugCardCaptureState.idle
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
#if DEBUG
    @State private var startupDebugState = FlashcardsStartupDebugState()
#endif

    private static let renderDebugDeckTitle = "Math Render Debug"
    private static let renderDebugDeckColorHex = "#7C3AED"

    // MARK: - Convenience

    private var accentColor: Color { ThemeManager.shared.accentColor.color }
    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var chromeButtonSize: CGFloat { UIConstants.Size.actionButton }
    private var playSurfaceHorizontalPadding: CGFloat {
        isCompact
            ? FlashcardPlayLayoutTuning.screenToCardHorizontalPaddingCompact
            : FlashcardPlayLayoutTuning.screenToCardHorizontalPaddingRegular
    }
    private var flipPerspectiveBottomClearance: CGFloat { isCompact ? 14 : 22 }
    private var scoreZoneHeight: CGFloat { isCompact ? 44 : 52 }
    private var scoreZoneBottomPadding: CGFloat { isCompact ? 10 : 16 }
    private var cardBottomReserve: CGFloat { flipPerspectiveBottomClearance }
    private var bottomChromeHeight: CGFloat { scoreZoneHeight + scoreZoneBottomPadding + 6 }
    private var preloadBufferDepth: Int { 2 }
    private var promotedCardScale: CGFloat { 0.952 }
    private var promotedCardSpring: Animation { .spring(response: 0.36, dampingFraction: 0.84) }
    private var resolvedDeckTitle: String {
        let trimmedTitle = viewModel.deck.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Untitled Deck" : trimmedTitle
    }
    private var locale: Locale { appPreferences.resolvedLocale }
    private var currentHeaderBottomPadding: CGFloat { isCompact ? 16 : 18 }
    private var currentPlayableCard: PlayableCard? {
        guard viewModel.currentIndex < viewModel.cards.count else { return nil }
        return viewModel.cards[viewModel.currentIndex]
    }
    private var playSessionPositionText: String {
        let total = max(viewModel.totalCardCount, viewModel.cards.count)
        guard total > 0 else { return "0 / 0" }
        let current = min(max(viewModel.currentIndex + 1, 1), total)
        return "\(current) / \(total)"
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let resolvedSafeTopInset = resolvedTopSafeInset(
                geometrySafeTop: geo.safeAreaInsets.top,
                containerHeight: geo.size.height
            )
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)
            let bottomControlInset = max(resolvedSafeBottomInset - 6, 10)
            let cardBottomPadding = bottomChromeHeight + bottomControlInset

            ZStack {
                if !viewModel.isComplete {
                    VStack(spacing: 0) {
                        header(
                            safeTopInset: resolvedSafeTopInset,
                            horizontalPadding: playSurfaceHorizontalPadding
                        )
                        .padding(.bottom, currentHeaderBottomPadding)
                        .zIndex(100)

                        cardArea
                            .padding(.horizontal, playSurfaceHorizontalPadding)
                            .padding(.bottom, cardBottomPadding)
                            .overlay(alignment: .bottom) {
                                if viewModel.isSessionStarted {
                                    bottomScoreZones
                                        .frame(height: bottomChromeHeight)
                                        .padding(.bottom, bottomControlInset)
                                }
                            }
                            .zIndex(1)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .transition(.opacity)

                    if developmentPreferences.playModeDeveloperModeEnabled {
                        playModeDeveloperToolsOverlay(
                            safeBottomInset: resolvedSafeBottomInset,
                            containerSize: geo.size
                        )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                if viewModel.isComplete {
                    completionOverlay
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                        .clipped()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .clipped()
            .background(Color.black.ignoresSafeArea())
        }
        .animation(.smooth(duration: 0.26, extraBounce: 0), value: viewModel.isComplete)
        .keepsScreenAwake()
        .onAppear {
#if DEBUG
            startupDebugState.reset()
            startupDebugState.record("view appear")
#endif
        }
        .task {
            if !viewModel.isSessionStarted {
#if DEBUG
                startupDebugState.record("task start")
#endif
                await viewModel.startSession(container: modelContext.container)
#if DEBUG
                startupDebugState.record("task returned")
#endif
            }
        }
        .onDisappear {
            guard editingCard == nil else { return }
#if DEBUG
            startupDebugState.record("view disappear")
#endif
            showsDeveloperPanel = false
            developerSwipeDebugState.showsLiveSwipeOverlay = false
            resetSwipeFeedbackPresentation()
            developerSwipeDebugState.reset()
            viewModel.tearDown()
        }
#if DEBUG
        .onChange(of: viewModel.isSessionStarted) { _, isStarted in
            startupDebugState.record("isSessionStarted \(isStarted)")
        }
        .onChange(of: viewModel.hasLoadedAllCards) { _, hasLoadedAllCards in
            startupDebugState.record("loadedAll \(hasLoadedAllCards)")
        }
        .onChange(of: viewModel.cards.count) { _, count in
            startupDebugState.record("cards.count \(count)/\(viewModel.totalCardCount)")
        }
#endif
        .onChange(of: viewModel.currentIndex) { _, _ in
#if DEBUG
            startupDebugState.record("currentIndex \(viewModel.currentIndex)")
#endif
            liveSwipeFeedbackSnapshot = .idle
            currentLayoutDebugSnapshotsByFace = [:]
            currentLayoutDebugCardID = nil
            debugCardCaptureState = .idle
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
                FlashcardEditorView(
                    frontZone: card.frontZone,
                    backZone: card.backZone,
                    contentAlignment: viewModel.settings.contentAlignment,
                    textSize: viewModel.settings.textSize
                ) { frontZone, backZone in
                    if card.frontZone != frontZone || card.backZone != backZone {
                        card.frontZone = frontZone
                        card.backZone = backZone
                        card.editedAt = Date()
                        deck.editedAt = Date()
                        CloudSyncCoordinator.shared.enqueueUpsert(for: deck, context: modelContext)
                        Task {
                            await viewModel.refreshCardSnapshot(for: card.persistentModelID)
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func resolvedTopSafeInset(geometrySafeTop: CGFloat, containerHeight: CGFloat) -> CGFloat {
        let reportedInset = max(safeAreaInsets.top, geometrySafeTop)
        guard fullScreenSheetDismiss != nil else { return reportedInset }

        let compactSheetFallback: CGFloat = containerHeight >= 800 ? 59 : 28
        let minimumSheetInset = isCompact ? compactSheetFallback : 24
        return max(reportedInset, minimumSheetInset)
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
                            : .constant(false)

                        GameplayCard(
                            card: entry.card,
                            onSwipe: { direction in
                                viewModel.handleSwipe(direction)
                            },
                            isInteractionEnabled: isCurrentCard,
                            tapAnimationStyle: viewModel.settings.tapAnimationStyle,
                            staticSwapTextMotion: viewModel.settings.staticSwapTextMotion,
                            contentAlignment: viewModel.settings.contentAlignment,
                            textSize: viewModel.settings.textSize,
                            onSwipeProgress: resolvedSwipeProgressHandler(isCurrentCard: isCurrentCard),
                            swipeGestureTuning: resolvedSwipeGestureTuning,
                            onLayoutDebugSnapshot: isCurrentCard && shouldCollectCurrentLayoutDebug
                                ? { snapshot in
                                    updateCurrentLayoutDebugSnapshot(snapshot, cardID: entry.card.id)
                                }
                                : nil,
                            isFlipped: flipBinding
                        )
                        .padding(.bottom, cardBottomReserve)
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
#if DEBUG
                        .onAppear {
                            if isCurrentCard {
                                startupDebugState.record("card appear #\(entry.displayIndex + 1)")
                            }
                        }
#endif
                    }
                }

                swipeDirectionFeedbackOverlay
                    .zIndex(50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.20, dampingFraction: 0.86), value: viewModel.currentIndex)
#if DEBUG
        .onAppear {
            startupDebugState.record("cardArea appear")
        }
#endif
    }

    private var bottomScoreZones: some View {
        HStack(spacing: 14) {
            scoreZone(
                count: viewModel.wrongCards.count,
                systemName: "xmark",
                tint: Color.red.opacity(0.92),
                edge: .leading
            )

            Spacer(minLength: 0)

            playSessionPositionPill
                .layoutPriority(1)

            Spacer(minLength: 0)

            scoreZone(
                count: viewModel.correctCount,
                systemName: "checkmark",
                tint: Color.green.opacity(0.92),
                edge: .trailing
            )
        }
        .padding(.horizontal, isCompact ? 8 : 14)
        .padding(.bottom, scoreZoneBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private var playSessionPositionPill: some View {
        Text(playSessionPositionText)
            .font(.system(size: isCompact ? 18 : 20, weight: .black))
            .foregroundStyle(themeManager.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .monospacedDigit()
            .padding(.horizontal, isCompact ? 16 : 18)
            .frame(height: scoreZoneHeight)
            .background {
                Capsule()
                    .fill(themeManager.surfacePrimary.opacity(0.66))
                    .overlay {
                        Capsule()
                            .strokeBorder(themeManager.textPrimary.opacity(0.08), lineWidth: 1)
                    }
            }
    }

    private func scoreZone(
        count: Int,
        systemName: String,
        tint: Color,
        edge: ScoreZoneEdge
    ) -> some View {
        HStack(spacing: 8) {
            if edge == .trailing {
                Image(systemName: systemName)
                    .font(.system(size: isCompact ? 13 : 14, weight: .black))
                    .foregroundStyle(tint)
            }

            Text("\(count)")
                .font(.system(size: isCompact ? 18 : 20, weight: .black))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())

            if edge == .leading {
                Image(systemName: systemName)
                    .font(.system(size: isCompact ? 13 : 14, weight: .black))
                    .foregroundStyle(tint)
            }
        }
        .padding(.horizontal, isCompact ? 12 : 14)
        .frame(minWidth: isCompact ? 60 : 66)
        .frame(height: scoreZoneHeight)
        .background {
            Capsule()
                .fill(themeManager.surfacePrimary.opacity(0.62))
                .overlay {
                    Capsule()
                        .strokeBorder(tint.opacity(0.48), lineWidth: 1.4)
                }
        }
        .shadow(color: tint.opacity(0.12), radius: 12, y: 6)
        .animation(.snappy(duration: 0.22, extraBounce: 0.04), value: count)
    }

#if DEBUG
    private func flashcardsStartupDebugPanel(
        safeTopInset: CGFloat,
        safeBottomInset: CGFloat,
        cardBottomPadding: CGFloat
    ) -> some View {
        let pool = MathWebViewPool.shared.debugSnapshot()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("FLASHCARDS PERF")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                Spacer(minLength: 0)
                Text(startupDebugState.elapsedText)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .monospacedDigit()
            }

            debugLine("started", viewModel.isSessionStarted.description)
            debugLine("cards", "\(viewModel.cards.count)/\(viewModel.totalCardCount) loadedAll=\(viewModel.hasLoadedAllCards)")
            debugLine("index", "\(viewModel.currentIndex) current=\(currentPlayableCard?.cardNumber.description ?? "nil")")
            debugLine("sheet", "fullScreen=\((fullScreenSheetDismiss != nil).description)")
            debugLine("safe", "top \(Int(safeTopInset)) bottom \(Int(safeBottomInset)) cardBottom \(Int(cardBottomPadding))")
            debugLine("header", "\(Int(headerHeight))")
            debugLine("webPool", "idle \(pool.idleCount) prewarmed \(pool.isPrewarmed) tasks \(pool.pendingPrewarmTaskCount)")

            Divider()
                .overlay(Color.white.opacity(0.45))

            ForEach(startupDebugState.events.suffix(7)) { event in
                Text(event.displayText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.78))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.yellow.opacity(0.65), lineWidth: 1)
                }
        }
        .foregroundStyle(Color.yellow)
    }

    private func debugLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.yellow.opacity(0.75))
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
#endif

    private var bufferedCardEntries: [BufferedCardEntry] {
        guard !viewModel.cards.isEmpty, viewModel.currentIndex < viewModel.cards.count else { return [] }
        let upperBound = min(viewModel.cards.count, viewModel.currentIndex + preloadBufferDepth + 1)
        return Array(viewModel.cards[viewModel.currentIndex..<upperBound].enumerated()).map { offset, card in
            BufferedCardEntry(
                runGeneration: viewModel.playRunGeneration,
                displayIndex: viewModel.currentIndex + offset,
                card: card
            )
        }
    }

    private var currentVisibleFaceDebugTitle: String {
        viewModel.isFlipped ? "back" : "front"
    }

    private var currentVisibleZone: ZoneModel? {
        guard let currentPlayableCard else { return nil }
        return viewModel.isFlipped ? currentPlayableCard.backZone : currentPlayableCard.frontZone
    }

    private var shouldCollectCurrentLayoutDebug: Bool {
        developmentPreferences.playModeDeveloperModeEnabled && showsDeveloperPanel
    }

    private var currentLayoutDebugReport: String? {
        guard
            let currentPlayableCard,
            let currentVisibleZone,
            let snapshot = currentLayoutDebugSnapshot,
            currentLayoutDebugCardID == currentPlayableCard.id,
            snapshot.face == currentVisibleFaceDebugTitle
        else {
            return nil
        }

        return FlashcardLayoutDebugReportFormatter.makeReport(
            deckTitle: resolvedDeckTitle,
            card: currentPlayableCard,
            currentIndex: viewModel.currentIndex,
            totalCount: max(viewModel.totalCardCount, viewModel.cards.count),
            isFlipped: viewModel.isFlipped,
            settings: viewModel.settings,
            visibleZone: currentVisibleZone,
            snapshot: snapshot
        )
    }

    private var currentLayoutDebugSnapshot: ZoneContentLayoutDebugSnapshot? {
        guard currentLayoutDebugCardID == currentPlayableCard?.id else { return nil }
        return currentLayoutDebugSnapshotsByFace[currentVisibleFaceDebugTitle]
    }

    private func updateCurrentLayoutDebugSnapshot(
        _ snapshot: ZoneContentLayoutDebugSnapshot,
        cardID: PersistentIdentifier
    ) {
        guard currentPlayableCard?.id == cardID else { return }
        currentLayoutDebugCardID = cardID
        currentLayoutDebugSnapshotsByFace[snapshot.face] = snapshot
    }

    // MARK: - Header

    private func header(safeTopInset: CGFloat, horizontalPadding: CGFloat) -> some View {
        ZStack(alignment: .top) {
            FlashCardsHeaderControlsBridge(
                buttonSize: chromeButtonSize,
                editTint: UIColor(accentColor),
                closeTint: UIColor(themeManager.roleColor(.circularToolbarForeground)),
                backgroundTint: UIColor(themeManager.roleColor(.circularToolbarFill)),
                onEdit: openCurrentCardEditor,
                onClose: handleDismiss,
                closeMenu: closeProgressMenu
            )
            .frame(height: chromeButtonSize)
            .zIndex(2)

            flashcardsTitleBlock
                .padding(.horizontal, chromeButtonSize + UIConstants.Spacing.standard)
                .frame(height: chromeButtonSize, alignment: .center)
                .allowsHitTesting(false)
                .zIndex(1)
        }
        .frame(height: chromeButtonSize, alignment: .top)
        .padding(.top, safeTopInset + UIConstants.Layout.deckNavigationTopPadding)
        .padding(.horizontal, max(horizontalPadding, UIConstants.Layout.compactScreenEdgeInset))
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            if abs(headerHeight - newHeight) > 0.5 {
                headerHeight = newHeight
            }
        }
    }

    private var flashcardsTitleBlock: some View {
        Text(resolvedDeckTitle)
            .font(.system(size: isCompact ? 19 : 22, weight: .bold))
            .foregroundStyle(themeManager.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .allowsTightening(true)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
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

    private func playModeDeveloperToolsOverlay(
        safeBottomInset: CGFloat,
        containerSize: CGSize
    ) -> some View {
        let horizontalInset = UIConstants.Layout.compactScreenEdgeInset
        let panelWidth = min(containerSize.width - (horizontalInset * 2), 320)
        let availablePanelHeight = containerSize.height - safeBottomInset - bottomChromeHeight - 128
        let panelMaxHeight = min(max(availablePanelHeight, 160), 220)

        return ZStack(alignment: .bottomTrailing) {
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
                .allowsHitTesting(true)
            }

            if showsDeveloperPanel {
#if DEBUG
                let performanceContent = AnyView(
                    flashcardsStartupDebugPanel(
                        safeTopInset: 0,
                        safeBottomInset: safeBottomInset,
                        cardBottomPadding: bottomChromeHeight + max(safeBottomInset - 6, 10)
                    )
                )
#else
                let performanceContent: AnyView? = nil
#endif

                PlayModeDeveloperSwipePanel(
                    state: developerSwipeDebugState,
                    maxHeight: panelMaxHeight,
                    performanceContent: performanceContent,
                    layoutDebugSnapshot: currentLayoutDebugSnapshot,
                    layoutDebugReport: currentLayoutDebugReport,
                    onClose: closeDeveloperPanel
                )
                .frame(width: panelWidth)
                .padding(.leading, horizontalInset)
                .padding(.bottom, safeBottomInset + 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .transition(playModeDeveloperPanelTransition)
            }

            VStack(alignment: .trailing, spacing: UIConstants.Spacing.medium) {
                if currentLayoutDebugReport != nil {
                    Button(action: saveCurrentCardToRenderDebugDeck) {
                        HStack(spacing: 8) {
                            Image(systemName: debugCardCaptureIconName)
                                .font(.system(size: 15, weight: .black))
                            Text(debugCardCaptureTitle)
                                .font(.system(size: 15, weight: .black))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(debugCardCaptureBackgroundColor, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))

                    Button(action: copyFloatingLayoutDebugReport) {
                        HStack(spacing: 8) {
                            Image(systemName: didCopyFloatingLayoutDebug ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 15, weight: .black))
                            Text(didCopyFloatingLayoutDebug ? "Copied" : "Copy")
                                .font(.system(size: 15, weight: .black))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Color.black.opacity(0.72), in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }

                PlayModeDebugButtonBridge(
                    title: showsDeveloperPanel ? "Hide Debug" : "Play Debug",
                    isActive: showsDeveloperPanel,
                    accentTint: UIColor(accentColor),
                    onTap: toggleDeveloperPanel
                )
                .frame(width: showsDeveloperPanel ? 136 : 128, height: 44)
            }
            .padding(.horizontal, horizontalInset)
            .padding(.bottom, safeBottomInset + bottomChromeHeight + 4)
            .allowsHitTesting(true)
        }
        .frame(width: containerSize.width, height: containerSize.height, alignment: .bottomTrailing)
        .zIndex(1_200)
    }

    private var debugCardCaptureTitle: String {
        switch debugCardCaptureState {
        case .idle:
            return "Save Card"
        case .saved:
            return "Saved"
        case .failed:
            return "Failed"
        }
    }

    private var debugCardCaptureIconName: String {
        switch debugCardCaptureState {
        case .idle:
            return "tray.and.arrow.down"
        case .saved:
            return "checkmark"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var debugCardCaptureBackgroundColor: Color {
        switch debugCardCaptureState {
        case .idle:
            return Color.purple.opacity(0.78)
        case .saved:
            return Color.green.opacity(0.78)
        case .failed:
            return Color.red.opacity(0.78)
        }
    }

    private func saveCurrentCardToRenderDebugDeck() {
        guard
            let currentPlayableCard,
            let sourceCard = modelContext.safeModel(for: currentPlayableCard.id, as: CardModel.self)
        else {
            showDebugCardCaptureState(.failed)
            return
        }

        do {
            let debugDeck = try fetchOrCreateRenderDebugDeck()
            let existingMaxCardNumber = debugDeck.cards.map(\.cardNumber).max() ?? 0
            let nextCardNumber = max(debugDeck.lastAssignedCardNumber, existingMaxCardNumber) + 1
            let originalCardCount = max(debugDeck.cardCount, debugDeck.cards.count)
            let now = Date()

            let capturedCard = CardModel(
                content: sourceCard.cardContent,
                cardNumber: nextCardNumber,
                isPinned: true,
                creationSource: sourceCard.creationSource
            )
            capturedCard.createdAt = now
            capturedCard.editedAt = now
            capturedCard.dueDate = now
            capturedCard.deck = debugDeck

            debugDeck.cards.append(capturedCard)
            debugDeck.cardCount = originalCardCount + 1
            debugDeck.lastAssignedCardNumber = nextCardNumber
            debugDeck.editedAt = now

            modelContext.insert(capturedCard)
            try modelContext.save()
            showDebugCardCaptureState(.saved)
        } catch {
            modelContext.rollback()
            showDebugCardCaptureState(.failed)
        }
    }

    private func fetchOrCreateRenderDebugDeck() throws -> DeckModel {
        let title = Self.renderDebugDeckTitle
        var descriptor = FetchDescriptor<DeckModel>(
            predicate: #Predicate { deck in
                deck.title == title
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 1

        if let existingDeck = try modelContext.fetch(descriptor).first {
            return existingDeck
        }

        let debugDeck = DeckModel(
            title: Self.renderDebugDeckTitle,
            colorHex: Self.renderDebugDeckColorHex
        )
        modelContext.insert(debugDeck)
        return debugDeck
    }

    private func showDebugCardCaptureState(_ state: DebugCardCaptureState) {
        debugCardCaptureState = state
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if debugCardCaptureState == state {
                debugCardCaptureState = .idle
            }
        }
    }

    private func copyFloatingLayoutDebugReport() {
        guard let currentLayoutDebugReport else { return }
        UIPasteboard.general.string = currentLayoutDebugReport
        didCopyFloatingLayoutDebug = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            didCopyFloatingLayoutDebug = false
        }
    }

    private func toggleDeveloperPanel() {
        withAnimation(.circularProgressSpring) {
            showsDeveloperPanel.toggle()
            if !showsDeveloperPanel {
                developerSwipeDebugState.reset()
                currentLayoutDebugSnapshotsByFace = [:]
                currentLayoutDebugCardID = nil
            }
        }
    }

    private func closeDeveloperPanel() {
        withAnimation(.circularProgressSpring) {
            showsDeveloperPanel = false
            developerSwipeDebugState.reset()
            currentLayoutDebugSnapshotsByFace = [:]
            currentLayoutDebugCardID = nil
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

    private var shouldConfirmDismiss: Bool {
        viewModel.totalSessionSwipes > 0 && !viewModel.isComplete
    }

    private var closeProgressMenu: UIMenu? {
        guard shouldConfirmDismiss else { return nil }

        return UIMenu(children: [
            UIAction(
                title: localized("Close and keep progress"),
                image: UIImage(systemName: "checkmark.circle")
            ) { _ in
                handleDismiss()
            },
            UIAction(
                title: localized("Continue playing"),
                image: UIImage(systemName: "play.fill")
            ) { _ in }
        ])
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
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

nonisolated private enum FlashcardLayoutDebugReportFormatter {
    @MainActor
    static func makeReport(
        deckTitle: String,
        card: PlayableCard,
        currentIndex: Int,
        totalCount: Int,
        isFlipped: Bool,
        settings: FlashcardModeSettings,
        visibleZone: ZoneModel,
        snapshot: ZoneContentLayoutDebugSnapshot
    ) -> String {
        var lines: [String] = []
        lines.append("QuizFlash Flashcard Layout Debug")
        lines.append("timestamp: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("deck: \(deckTitle)")
        lines.append("position: \(currentIndex + 1) / \(max(totalCount, 0))")
        lines.append("cardNumber: \(card.cardNumber)")
        lines.append("cardID: \(card.id)")
        lines.append("visibleFace: \(snapshot.face)")
        lines.append("isFlipped: \(isFlipped)")
        lines.append(
            "settings: tapAnimation=\(settings.tapAnimationStyle.rawValue), staticSwapMotion=\(settings.staticSwapTextMotion.rawValue), contentAlignment=\(settings.contentAlignment.rawValue), textSize=\(settings.textSize.rawValue)"
        )
        lines.append("frontPreview: \(card.frontZone.previewText(maxLength: 220))")
        lines.append("backPreview: \(card.backZone.previewText(maxLength: 220))")
        lines.append("")
        lines.append("FACE METRICS")
        lines.append("containerSize: \(size(snapshot.containerSize))")
        lines.append("horizontalPadding: \(metric(snapshot.horizontalPadding))")
        lines.append("verticalPadding: \(metric(snapshot.verticalPadding))")
        lines.append("availableContentSize: \(size(snapshot.availableContentSize))")
        lines.append("estimatedContentSize: \(size(snapshot.estimatedContentSize))")
        lines.append("measuredContentSize: \(size(snapshot.measuredContentSize))")
        lines.append("measurementSource: \(snapshot.measurementSource)")
        lines.append("contentBodyHeight: \(metric(snapshot.contentBodyHeight))")
        lines.append("contentFitsVertically: \(snapshot.contentFitsVertically)")
        lines.append("centeredTopInset: \(metric(snapshot.centeredTopInset))")
        lines.append("scrollContentHeight: \(metric(snapshot.scrollContentHeight))")
        lines.append("")
        lines.append("SCROLL DECISION")
        appendScrollDecisionLines(to: &lines, snapshot: snapshot)
        lines.append("")
        lines.append("FACE / SCROLL TIMELINE")
        if snapshot.faceDebugEvents.isEmpty {
            lines.append("    <none>")
        } else {
            lines.append(contentsOf: snapshot.faceDebugEvents.map { "    \($0)" })
        }
        lines.append("")
        lines.append("CARD GESTURE DEBUG")
        lines.append(cardGestureDebugLine(for: SwipeTouchDebugStore.latest))
        lines.append("")
        lines.append("ZONE TREE")
        lines.append(contentsOf: zoneTreeLines(for: visibleZone, path: "root", depth: 0))
        lines.append("")
        lines.append("LEAF METRICS")

        if snapshot.leafSnapshots.isEmpty {
            lines.append("no leaf metrics captured")
        } else {
            for leaf in snapshot.leafSnapshots {
                lines.append(contentsOf: leafLines(for: leaf))
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func appendScrollDecisionLines(
        to lines: inout [String],
        snapshot: ZoneContentLayoutDebugSnapshot
    ) {
        let leafBlockSum = snapshot.leafSnapshots.reduce(CGFloat(0)) { partial, leaf in
            partial + leaf.blockSize.height
        }
        let spacingTotal = CGFloat(max(snapshot.leafSnapshots.count - 1, 0)) * ZoneContentMetrics.childSpacing
        let leafBodyHeight = leafBlockSum + spacingTotal
        let leafScrollHeight = snapshot.verticalPadding + leafBodyHeight + snapshot.verticalPadding
        let availableHeight = snapshot.availableContentSize.height
        let scrollEnabled = !snapshot.contentFitsVertically

        lines.append("availableHeight: \(metric(availableHeight))")
        lines.append("estimatedHeight: \(metric(snapshot.estimatedContentSize.height))")
        lines.append("rootGeometryHeight: \(snapshot.measurementSource == "root-geometry" ? metric(snapshot.measuredContentSize.height) : "fallback-only")")
        lines.append("leafBlockSum: \(metric(leafBlockSum))")
        lines.append("spacingTotal: \(metric(spacingTotal))")
        lines.append("leafBodyHeight: \(metric(leafBodyHeight))")
        lines.append("leafScrollHeight: \(metric(leafScrollHeight))")
        lines.append("appliedBodyHeight: \(metric(snapshot.contentBodyHeight))")
        lines.append("source: \(snapshot.measurementSource)")
        lines.append("scrollEnabled: \(scrollEnabled)")
    }

    private static func zoneTreeLines(for zone: ZoneModel, path: String, depth: Int) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        if zone.isLeaf {
            var line = "\(indent)- \(path) leaf type=\(zone.contentType.rawValue) hasContent=\(zone.hasContent) sizeMode=\(zone.sizeMode.rawValue)"
            if zone.contentType == .text || zone.contentType == .code {
                line += " chars=\(zone.text.count) preview=\"\(singleLinePreview(zone.text, limit: 120))\""
            }
            return [line]
        }

        let children = zone.children ?? []
        var lines = [
            "\(indent)- \(path) container direction=\(zone.direction.rawValue) children=\(children.count) filledChildren=\(children.filter(\.hasContent).count)"
        ]
        for (index, child) in children.enumerated() {
            lines.append(contentsOf: zoneTreeLines(for: child, path: "\(path).\(index)", depth: depth + 1))
        }
        return lines
    }

    private static func leafLines(for leaf: ZoneContentLeafLayoutDebugSnapshot) -> [String] {
        let maxEstimatedLine = leaf.estimatedLineWidths.max() ?? 0
        let textWidthLimit = leaf.textWidthLimit ?? leaf.contentLayoutWidth
        let rightSpaceAfterBlock = max(leaf.availableWidth - leaf.leadingInset - leaf.blockSize.width, 0)
        let remainingTextWidth = max(textWidthLimit - maxEstimatedLine, 0)
        let lineWidths = leaf.estimatedLineWidths.map(metric).joined(separator: ", ")
        let renderedLineWidths = leaf.renderedLineWidths.map(metric).joined(separator: ", ")
        let renderedLines = leaf.renderedLineTexts.enumerated()
            .map { index, lineText in
                let lineWidth = index < leaf.renderedLineWidths.count ? leaf.renderedLineWidths[index] : 0
                return "    \(index + 1). [\(metric(lineWidth))] \"\(lineText)\""
            }
            .joined(separator: "\n")
        let renderedTokenLines = tokenDebugLines(for: leaf.renderedTokenLines)
        let renderedScrollableMath = scrollableMathDebugLines(for: leaf.renderedScrollableMath)
        let mathGestureDebug = gestureDebugLine(for: leaf.mathGestureDebug)
        let renderStatusDebug = renderStatusDebugLine(for: leaf.renderStatusDebug)
        let nativeRenderDebug = nativeRenderDebugLines(for: leaf.nativeRenderDebug)
        let measurementEvents = leaf.measurementEvents.isEmpty
            ? "    <none>"
            : leaf.measurementEvents.map { "    \($0)" }.joined(separator: "\n")

        return [
            "- \(leaf.path) id=\(leaf.zoneID.uuidString)",
            "  type=\(leaf.contentType.rawValue) hasContent=\(leaf.hasContent) math=\(leaf.containsMath) inlineCode=\(leaf.containsInlineCode)",
            "  availableWidth=\(metric(leaf.availableWidth)) estimated=\(size(leaf.estimatedSize)) rendered=\(size(leaf.renderedContentSize))",
            "  block=\(size(leaf.blockSize)) leadingInset=\(metric(leaf.leadingInset)) rightSpaceAfterBlock=\(metric(rightSpaceAfterBlock))",
            "  measurements updates=\(leaf.measurementUpdateCount) resets=\(leaf.measurementResetCount) rawMeasured=\(size(leaf.rawMeasuredContentSize)) frameH=\(leaf.contentFrameHeight.map(metric) ?? "nil") slack=\(metric(leaf.blockHeightSlack))",
            "  lastMeasurement source=\(leaf.lastMeasurementSource) decision=\"\(leaf.lastMeasurementDecision)\"",
            "  measurementFlow:",
            measurementEvents,
            "  contentLayoutWidth=\(metric(leaf.contentLayoutWidth)) textWidthLimit=\(metric(textWidthLimit)) remainingTextWidthAfterWidestLine=\(metric(remainingTextWidth))",
            "  textInsets=\(metric(leaf.textHorizontalInsets)) intrinsicText=\(leaf.usesIntrinsicTextMeasurement)",
            "  sizeMode=\(leaf.zoneSizeMode.rawValue)",
            "  style=\(leaf.textStyle.rawValue) font=\(leaf.fontFamily.rawValue) bold=\(leaf.isBold) italic=\(leaf.isItalic) highlight=\(leaf.highlightColor.rawValue)",
            "  chars=\(leaf.textCharacterCount) explicitLines=\(leaf.textLineCount) estimatedLineWidths=[\(lineWidths)]",
            "  renderedLineWidths=[\(renderedLineWidths)]",
            "  renderedLines:",
            renderedLines.isEmpty ? "    <none>" : renderedLines,
            "  renderedTokenLines:",
            renderedTokenLines.isEmpty ? "    <none>" : renderedTokenLines,
            "  renderedScrollableMath:",
            renderedScrollableMath.isEmpty ? "    <none>" : renderedScrollableMath,
            "  renderStatusDebug:",
            renderStatusDebug,
            "  nativeRenderPipeline:",
            nativeRenderDebug,
            "  mathGestureDebug:",
            mathGestureDebug,
            "  preview=\"\(leaf.textPreview)\"",
            "  fullText:",
            leaf.fullText.isEmpty ? "  <empty>" : indentMultiline(leaf.fullText, prefix: "  | ")
        ]
    }

    private static func tokenDebugLines(for lines: [MixedMathRenderedLineDebug]) -> String {
        guard !lines.isEmpty else { return "" }

        return lines.enumerated()
            .map { offset, line in
                let remaining = max(line.widthLimit - line.width, 0)
                let nextFirstToken = offset + 1 < lines.count ? lines[offset + 1].tokens.first : nil
                let nextFitText: String
                if let nextFirstToken {
                    let fitsAlone = nextFirstToken.width <= remaining
                    nextFitText = " nextFirst=\"\(singleLinePreview(nextFirstToken.text, limit: 40))\" width=\(metric(nextFirstToken.width)) fitsRemainingWithoutSpace=\(fitsAlone)"
                } else {
                    nextFitText = ""
                }

                let tokens = line.tokens
                    .map { token in
                        "      - \(token.kind) \"\(singleLinePreview(token.text, limit: 80))\" frame=(x:\(metric(token.left)), y:\(metric(token.top)), w:\(metric(token.width)), h:\(metric(token.height)), r:\(metric(token.right)), b:\(metric(token.bottom)))"
                    }
                    .joined(separator: "\n")

                let header = "    \(line.index). frame=(x:\(metric(line.left)), y:\(metric(line.top)), w:\(metric(line.width)), h:\(metric(line.height)), r:\(metric(line.right)), b:\(metric(line.bottom))) limit=\(metric(line.widthLimit)) remaining=\(metric(remaining))\(nextFitText)"
                return tokens.isEmpty ? header : "\(header)\n\(tokens)"
            }
            .joined(separator: "\n")
    }

    private static func scrollableMathDebugLines(for rows: [MixedMathScrollableDebug]) -> String {
        guard !rows.isEmpty else { return "" }

        return rows.enumerated()
            .map { index, row in
                "    \(index + 1). kind=\(row.kind) wrapperHeight=\(metric(row.wrapperHeight)) clientHeight=\(metric(row.clientHeight)) scrollHeight=\(metric(row.scrollHeight)) visualHeight=\(metric(row.visualHeight)) visualTop=\(metric(row.visualTop)) visualBottom=\(metric(row.visualBottom)) paddingTop=\(metric(row.paddingTop)) paddingBottom=\(metric(row.paddingBottom)) topAdjustment=\(metric(row.topAdjustment))"
            }
            .joined(separator: "\n")
    }

    private static func gestureDebugLine(for snapshot: MixedMathGestureDebugSnapshot?) -> String {
        guard let snapshot else { return "    <none>" }

        return "    decision=\(snapshot.decision) reason=\"\(snapshot.reason)\" direction=\"\(snapshot.direction)\" location=(x:\(metric(snapshot.location.x)), y:\(metric(snapshot.location.y))) h=\(metric(snapshot.horizontalMagnitude)) v=\(metric(snapshot.verticalMagnitude)) canLeft=\(snapshot.canScrollLeft) canRight=\(snapshot.canScrollRight) regions=\(snapshot.regionCount)"
    }

    private static func renderStatusDebugLine(for snapshot: MixedMathRenderStatusDebug?) -> String {
        guard let snapshot else { return "    <none>" }

        return "    stage=\(snapshot.stage) contentLen=\(snapshot.contentLength) childCount=\(snapshot.childCount) textLen=\(snapshot.textLength) body=\(metric(snapshot.bodyWidth))x\(metric(snapshot.bodyHeight)) content=\(metric(snapshot.contentWidth))x\(metric(snapshot.contentHeight)) scroll=\(metric(snapshot.contentScrollWidth))x\(metric(snapshot.contentScrollHeight)) inlineCode=\(snapshot.inlineCodeCount) math=\(snapshot.mathCount) displayMath=\(snapshot.displayMathCount) codeScroll=\(snapshot.inlineCodeScrollCount) inlineMathScroll=\(snapshot.inlineMathScrollCount) layoutReports=\(snapshot.layoutMetricReportCount) lineReports=\(snapshot.lineDebugReportCount)"
    }

    private static func nativeRenderDebugLines(for snapshot: MixedMathNativeRenderDebug?) -> String {
        guard let snapshot else { return "    <none>" }

        let header = "    webView=\(snapshot.webViewID) source=\(snapshot.checkoutSource) checkout=\(snapshot.checkoutCount) window=\(snapshot.windowAttached ? 1 : 0) hidden=\(snapshot.isHidden ? 1 : 0) alpha=\(metric(snapshot.alpha)) layerOpacity=\(metric(CGFloat(snapshot.layerOpacity))) effectiveOpacity=\(metric(CGFloat(snapshot.effectiveOpacity))) frame=\(rect(snapshot.frame)) bounds=\(rect(snapshot.bounds)) intersectsWindow=\(snapshot.intersectsWindow ? 1 : 0) stage=\(snapshot.stage) token=\(snapshot.renderToken) readiness=\(snapshot.readinessChecks) didFinish=\(snapshot.didFinishCount) jsExec=\(snapshot.javaScriptExecutionCount) heightMsg=\(snapshot.heightMessageCount)(\(metric(snapshot.lastHeight))) widthMsg=\(snapshot.widthMessageCount)(\(metric(snapshot.lastWidth))) statusMsg=\(snapshot.renderStatusMessageCount) error=\"\(snapshot.lastError)\""
        guard !snapshot.events.isEmpty else { return header }
        return ([header, "    events:"] + snapshot.events.map { "      - \($0)" })
            .joined(separator: "\n")
    }

    private static func cardGestureDebugLine(for snapshot: SwipeTouchDebugSnapshot?) -> String {
        guard let snapshot else { return "    <none>" }

        let location = snapshot.locationInWebView.map {
            "(x:\(metric($0.x)), y:\(metric($0.y)))"
        } ?? "nil"
        return "    event=\(snapshot.event) recognizer=\(snapshot.recognizer) decision=\(snapshot.decision) reason=\"\(snapshot.reason)\" touchedView=\(snapshot.touchedViewClass) webLocation=\(location) translation=(x:\(metric(snapshot.translation.x)), y:\(metric(snapshot.translation.y))) velocity=(x:\(metric(snapshot.velocity.x)), y:\(metric(snapshot.velocity.y))) webRegions=\(snapshot.webRegionCount) canLeft=\(snapshot.webRegionCanScrollLeft) canRight=\(snapshot.webRegionCanScrollRight)"
    }

    private static func singleLinePreview(_ value: String, limit: Int) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "..."
    }

    private static func indentMultiline(_ value: String, prefix: String) -> String {
        value.components(separatedBy: .newlines)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    private static func size(_ size: CGSize) -> String {
        "\(metric(size.width)) x \(metric(size.height))"
    }

    private static func metric(_ value: CGFloat) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.05 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", Double(value))
    }

    private static func rect(_ value: CGRect) -> String {
        "\(metric(value.minX)),\(metric(value.minY)),\(metric(value.width))x\(metric(value.height))"
    }
}

private struct PlayModeDeveloperSwipePanel: View {
    @Bindable var state: PlayModeDeveloperSwipeDebugState
    let maxHeight: CGFloat
    let performanceContent: AnyView?
    let layoutDebugSnapshot: ZoneContentLayoutDebugSnapshot?
    let layoutDebugReport: String?
    let onClose: () -> Void

    @State private var didCopyLayoutDebug = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader

            Divider()
                .overlay(Color.white.opacity(0.10))

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                    if let performanceContent {
                        debugSection("Startup Perf") {
                            performanceContent
                        }
                    }

                    debugSection("Card Layout") {
                        layoutDebugSection
                    }

                    debugSection("Math Scroll Gesture") {
                        mathGestureDebugSection
                    }

                    debugSection("Live Swipe") {
                        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                            statusChips

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

                            toggleRow
                        }
                    }

                    debugSection("Controls") {
                        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
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
                    }
                }
                .padding(UIConstants.Spacing.medium)
            }
        }
        .frame(maxHeight: maxHeight)
        .flashcardStyle(
            cornerRadius: UIConstants.Radius.maximum,
            surfaceRole: .widget,
            baseBorderBlurRadius: 1
        )
        .onChange(of: layoutDebugReport ?? "") { _, _ in
            didCopyLayoutDebug = false
        }
    }

    private var panelHeader: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Play Debug")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Swipe state and tuning")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            closeButton
        }
        .padding(.horizontal, UIConstants.Spacing.medium)
        .padding(.vertical, UIConstants.Spacing.small)
    }

    private var statusChips: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            debugChip(directionLabel, tint: directionColor)
            debugChip(phaseLabel, tint: .gray)

            if state.liveSnapshot.fastSwipeDetected {
                debugChip("FLICK", tint: .cyan)
            }

            Spacer(minLength: 0)
        }
    }

    private var toggleRow: some View {
        Toggle(isOn: $state.showsLiveSwipeOverlay) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Live Swipe HUD")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .textCase(.uppercase)

                Text(state.showsLiveSwipeOverlay ? "Visible while dragging" : "Hidden")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.cyan)
        .padding(.horizontal, UIConstants.Spacing.medium)
        .padding(.vertical, UIConstants.Spacing.small)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var mathGestureDebugSection: some View {
        if let snapshot = latestMathGestureDebug {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                HStack(spacing: UIConstants.Spacing.small) {
                    debugChip(snapshot.decision, tint: snapshot.decision == "WEB" ? .cyan : .green)
                    debugChip(snapshot.reason.uppercased(), tint: snapshot.decision == "WEB" ? .cyan : .orange)
                }

                debugLayoutLine("direction", snapshot.direction)
                debugLayoutLine("touch", "x=\(metricText(snapshot.location.x)) y=\(metricText(snapshot.location.y))")
                debugLayoutLine("motion", "h=\(metricText(snapshot.horizontalMagnitude)) v=\(metricText(snapshot.verticalMagnitude))")
                debugLayoutLine("formula", "left=\(snapshot.canScrollLeft) right=\(snapshot.canScrollRight)")
                debugLayoutLine("regions", "\(snapshot.regionCount)")
            }
        } else {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                debugChip("WAITING", tint: .secondary)
                Text("Drag a scrollable formula; this shows whether the gesture stays in math or is handed to the card.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var latestMathGestureDebug: MixedMathGestureDebugSnapshot? {
        layoutDebugSnapshot?
            .leafSnapshots
            .compactMap(\.mathGestureDebug)
            .max(by: { $0.timestamp < $1.timestamp })
    }

    @ViewBuilder
    private var layoutDebugSection: some View {
        if let snapshot = layoutDebugSnapshot {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                HStack(spacing: UIConstants.Spacing.small) {
                    debugChip(snapshot.face.uppercased(), tint: .cyan)
                    debugChip("\(snapshot.leafSnapshots.count) LEAFS", tint: .orange)
                    debugChip(snapshot.contentFitsVertically ? "FITS" : "SCROLL", tint: .mint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    debugLayoutLine("container", sizeText(snapshot.containerSize))
                    debugLayoutLine("available", sizeText(snapshot.availableContentSize))
                    debugLayoutLine("estimated", sizeText(snapshot.estimatedContentSize))
                    debugLayoutLine("measured", sizeText(snapshot.measuredContentSize))
                    debugLayoutLine("top inset", metricText(snapshot.centeredTopInset))
                }

                if let widestLeaf = snapshot.leafSnapshots.max(by: { $0.blockSize.width < $1.blockSize.width }) {
                    debugLayoutLine(
                        "widest leaf",
                        "\(widestLeaf.path) block=\(metricText(widestLeaf.blockSize.width)) lead=\(metricText(widestLeaf.leadingInset))"
                    )
                }

                Button(action: copyLayoutDebugReport) {
                    HStack(spacing: 8) {
                        Image(systemName: didCopyLayoutDebug ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13, weight: .black))
                        Text(didCopyLayoutDebug ? "Copied" : "Copy Layout")
                            .font(.caption.weight(.black))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(layoutDebugReport == nil)
                .opacity(layoutDebugReport == nil ? 0.45 : 1)
            }
        } else {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                debugChip("WAITING", tint: .secondary)
                Text("Open the current flashcard face until layout metrics arrive.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func copyLayoutDebugReport() {
        guard let layoutDebugReport else { return }
        UIPasteboard.general.string = layoutDebugReport
        didCopyLayoutDebug = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            didCopyLayoutDebug = false
        }
    }

    private var closeButton: some View {
        ChromeSoftCircleSymbolButton(
            systemName: "xmark",
            accessibilityLabel: "Close debug panel",
            action: onClose
        )
    }

    private func debugChip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            }
    }

    private func debugLayoutLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(width: 74, alignment: .leading)

            Text(value)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func debugSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                content()
            }
            .padding(UIConstants.Spacing.small)
            .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
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
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer(minLength: 0)

                Text(valueText)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 70, alignment: .trailing)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.07), in: Capsule())
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
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer(minLength: 0)

                Text(sliderValueText(value.wrappedValue))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 70, alignment: .trailing)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.07), in: Capsule())
            }

            Slider(value: value, in: range)
                .tint(tint)
        }
        .padding(.horizontal, UIConstants.Spacing.small)
        .padding(.vertical, UIConstants.Spacing.small)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func progressText(for value: CGFloat) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    private func sliderValueText(_ value: CGFloat) -> String {
        Double(value).formatted(.number.precision(.fractionLength(2)))
    }

    private func sizeText(_ size: CGSize) -> String {
        "\(metricText(size.width)) x \(metricText(size.height))"
    }

    private func metricText(_ value: CGFloat) -> String {
        Double(value).formatted(.number.precision(.fractionLength(0...1)))
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

                ChromeSoftCircleSymbolButton(
                    systemName: "xmark",
                    accessibilityLabel: "Close swipe HUD",
                    action: onClose
                )
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

#if DEBUG
private struct FlashcardsStartupDebugEvent: Identifiable, Equatable {
    let id = UUID()
    let milliseconds: Int
    let message: String

    var displayText: String {
        "\(milliseconds)ms  \(message)"
    }
}

private struct FlashcardsStartupDebugState: Equatable {
    private var startTime = CACurrentMediaTime()
    private(set) var events: [FlashcardsStartupDebugEvent] = []

    var elapsedText: String {
        "\(Int((CACurrentMediaTime() - startTime) * 1_000))ms"
    }

    mutating func reset() {
        startTime = CACurrentMediaTime()
        events = []
    }

    mutating func record(_ message: String) {
        let elapsed = Int((CACurrentMediaTime() - startTime) * 1_000)
        events.append(
            FlashcardsStartupDebugEvent(
                milliseconds: elapsed,
                message: message
            )
        )
        if events.count > 18 {
            events.removeFirst(events.count - 18)
        }
    }
}
#endif

// MARK: - Play Mode Debug Button Bridge

private struct PlayModeDebugButtonBridge: UIViewRepresentable {
    let title: String
    let isActive: Bool
    let accentTint: UIColor
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system, primaryAction: UIAction { [weak coordinator = context.coordinator] _ in
            coordinator?.onTap()
        })
        button.isUserInteractionEnabled = true
        button.clipsToBounds = true
        button.layer.cornerCurve = .continuous
        button.layer.cornerRadius = 22
        button.accessibilityLabel = title
        applyStyle(to: button)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        context.coordinator.onTap = onTap
        uiView.accessibilityLabel = title
        applyStyle(to: uiView)
    }

    private func applyStyle(to button: UIButton) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: "slider.horizontal.3")
        configuration.imagePadding = 8
        configuration.baseForegroundColor = isActive ? accentTint : .white
        configuration.baseBackgroundColor = UIColor(white: 0.18, alpha: 0.86)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14)
        configuration.background.cornerRadius = 22
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            return outgoing
        }
        button.configuration = configuration
    }

    final class Coordinator {
        var onTap: () -> Void

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }
    }
}

// MARK: - FlashCards Header Controls Bridge

private struct FlashCardsHeaderControlsBridge: UIViewRepresentable {
    let buttonSize: CGFloat
    let editTint: UIColor
    let closeTint: UIColor
    let backgroundTint: UIColor
    let onEdit: () -> Void
    let onClose: () -> Void
    let closeMenu: UIMenu?

    func makeCoordinator() -> Coordinator {
        Coordinator(onEdit: onEdit, onClose: onClose)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let editButton = makeButton(
            systemName: "pencil",
            tint: editTint,
            accessibilityLabel: "Edit current card",
            action: UIAction { [weak coordinator = context.coordinator] _ in
                coordinator?.onEdit()
            }
        )

        let closeButton = makeButton(
            systemName: "xmark",
            tint: closeTint,
            accessibilityLabel: "Close",
            action: UIAction { [weak coordinator = context.coordinator] _ in
                coordinator?.onClose()
            }
        )

        context.coordinator.editButton = editButton
        context.coordinator.closeButton = closeButton

        view.addSubview(editButton)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            editButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            editButton.topAnchor.constraint(equalTo: view.topAnchor),
            editButton.widthAnchor.constraint(equalToConstant: buttonSize),
            editButton.heightAnchor.constraint(equalToConstant: buttonSize),

            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            closeButton.topAnchor.constraint(equalTo: view.topAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: buttonSize),
            closeButton.heightAnchor.constraint(equalToConstant: buttonSize)
        ])

        applyStyle(to: editButton, systemName: "pencil", tint: editTint)
        applyStyle(to: closeButton, systemName: "xmark", tint: closeTint)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onEdit = onEdit
        context.coordinator.onClose = onClose
        context.coordinator.editButton?.backgroundColor = backgroundTint
        context.coordinator.closeButton?.backgroundColor = backgroundTint
        if let editButton = context.coordinator.editButton {
            applyStyle(to: editButton, systemName: "pencil", tint: editTint)
        }
        if let closeButton = context.coordinator.closeButton {
            applyStyle(to: closeButton, systemName: "xmark", tint: closeTint)
            closeButton.menu = closeMenu
            closeButton.showsMenuAsPrimaryAction = closeMenu != nil
        }
    }

    private func makeButton(
        systemName: String,
        tint: UIColor,
        accessibilityLabel: String,
        action: UIAction
    ) -> UIButton {
        let button = UIButton(type: .system, primaryAction: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = accessibilityLabel
        button.backgroundColor = backgroundTint
        button.layer.cornerCurve = .continuous
        button.layer.cornerRadius = buttonSize / 2
        button.clipsToBounds = true
        button.menu = systemName == "xmark" ? closeMenu : nil
        button.showsMenuAsPrimaryAction = systemName == "xmark" && closeMenu != nil
        applyStyle(to: button, systemName: systemName, tint: tint)
        return button
    }

    private func applyStyle(to button: UIButton, systemName: String, tint: UIColor) {
        let pointSize = min(
            UIConstants.Size.circularChromeSymbol - 2,
            max(UIConstants.Size.iconSmall, buttonSize * 0.40)
        )
        let configuration = UIImage.SymbolConfiguration(pointSize: CGFloat(pointSize), weight: .bold)
        button.setImage(UIImage(systemName: systemName, withConfiguration: configuration), for: .normal)
        button.tintColor = tint
        button.backgroundColor = backgroundTint
        button.layer.cornerRadius = buttonSize / 2
    }

    final class Coordinator {
        var onEdit: () -> Void
        var onClose: () -> Void
        weak var editButton: UIButton?
        weak var closeButton: UIButton?

        init(onEdit: @escaping () -> Void, onClose: @escaping () -> Void) {
            self.onEdit = onEdit
            self.onClose = onClose
        }
    }
}

// MARK: - iOS 17 Retain-Cycle Wrapper

/// Wraps `FlashCardsPlayModeView` and owns the session view model for the
/// lifetime of a single play-mode presentation.
struct DefaultModePlay: View {
    let deck: DeckModel
    var safeAreaInsets: UIEdgeInsets = .zero

    @State private var viewModel: FlashCardsPlayModeViewModel

    init(
        deck: DeckModel,
        safeAreaInsets: UIEdgeInsets = .zero,
        viewModel: FlashCardsPlayModeViewModel? = nil
    ) {
        self.deck = deck
        self.safeAreaInsets = safeAreaInsets
        _viewModel = State(
            initialValue: viewModel ?? FlashCardsPlayModeViewModel(
                deck: deck,
                settings: deck.playModeSettings?.flashcardSettings ?? FlashcardModeSettings()
            )
        )
    }

    var body: some View {
        FlashCardsPlayModeView(
            deck: deck,
            safeAreaInsets: safeAreaInsets,
            viewModel: viewModel
        )
    }
}

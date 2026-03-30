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

    // MARK: - Properties

    /// The deck being studied — passed from the parent and forwarded to the ViewModel.
    let deck: DeckModel

    /// Safe-area values passed by the custom full-screen sheet container.
    let safeAreaInsets: UIEdgeInsets

    /// The `@Observable` ViewModel that owns all session state.
    @Bindable var viewModel: FlashCardsPlayModeViewModel

    @State private var headerHeight: CGFloat = 0
    @State private var editingCard: CardModel?

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
            let cardBottomPadding: CGFloat = 2

            ZStack {
                if fullScreenSheetDismiss == nil {
                    screenBackground
                        .ignoresSafeArea()
                }

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
            viewModel.tearDown()
        }
        .fullScreenCover(item: $editingCard) { card in
            NavigationStack {
                CreateCardView(frontZone: card.frontZone, backZone: card.backZone) { frontZone, backZone in
                    if card.frontZone != frontZone || card.backZone != backZone {
                        card.frontZone = frontZone
                        card.backZone = backZone
                        card.editedAt = Date()
                        deck.editedAt = Date()
                        try? modelContext.save()

                        Task {
                            await viewModel.refreshCardSnapshot(for: card.persistentModelID)
                        }
                    }
                    editingCard = nil
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
        .glassButton(shape: .capsule)
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
                .glassButton(shape: .circle)
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
                .glassButton(shape: .circle)
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

    private func handleDismiss() {
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            dismiss()
        }
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

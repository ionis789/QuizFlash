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
    private var resolvedDeckTitle: String {
        let trimmedTitle = viewModel.deck.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Untitled Deck" : trimmedTitle
    }
    private var currentPlayableCard: PlayableCard? {
        guard viewModel.currentIndex < viewModel.cards.count else { return nil }
        return viewModel.cards[viewModel.currentIndex]
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let isScreenLandscape = geo.size.width > geo.size.height
            let resolvedSafeTopInset = max(safeAreaInsets.top, geo.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)
            let headerHorizontalPadding: CGFloat = isCompact ? 20 : 32
            let headerBottomPadding: CGFloat = isCompact ? 20 : 30

            ZStack {
                if fullScreenSheetDismiss == nil {
                    screenBackground
                        .ignoresSafeArea()
                }

                if !viewModel.isComplete {
                    VStack(spacing: 0) {
                        header(
                            safeTopInset: resolvedSafeTopInset,
                            horizontalPadding: headerHorizontalPadding
                        )
                            .padding(.bottom, headerBottomPadding)

                        cardArea
                            .padding(.horizontal, isCompact ? 16 : (isScreenLandscape ? geo.size.width * 0.15 : 40))
                            .padding(.bottom, max(resolvedSafeBottomInset, isCompact ? 20 : 40))
                    }
                        .transition(.opacity)
                }

                if viewModel.isComplete {
                    completionOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
                .fullScreenSheetDragActivationHeight(headerHeight)
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
                if !viewModel.cards.isEmpty && viewModel.currentIndex < viewModel.cards.count {
                    // Render exactly ONE card — the current one. No pre-loading.
                    let index = viewModel.currentIndex
                    let card = viewModel.cards[index]

                    @Bindable var bindableViewModel = viewModel

                    GameplayCard(
                        card: card,
                        onSwipe: { direction in
                            viewModel.handleSwipe(direction)
                        },
                        isFlipped: $bindableViewModel.isFlipped
                    )
                    // Unique ID forces SwiftUI to replace the visual when the card changes.
                    .id(card.id)
                        .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .opacity
                    ))
                }
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: viewModel.currentIndex)
    }

    // MARK: - Header

    private func header(safeTopInset: CGFloat, horizontalPadding: CGFloat) -> some View {
        PlayModeSessionHeader(
            deckTitle: resolvedDeckTitle,
            subtitle: viewModel.isFlipped ? "ANSWER" : "QUESTION",
            progressLabel: "\(viewModel.reviewedCardCount)/\(max(viewModel.totalCardCount, 1)) reviewed",
            progressFraction: viewModel.progressFraction,
            safeTopInset: safeTopInset,
            horizontalPadding: horizontalPadding,
            measuredHeight: $headerHeight
        ) {
            liveScoreChrome
        } trailing: {
            HStack(spacing: UIConstants.Spacing.small) {
                editCurrentCardButton
                dismissButton
            }
        }
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

    private var liveScoreChrome: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            scoreMetric(
                value: viewModel.wrongCards.count,
                symbol: "chevron.compact.left",
                tint: .red,
                arrowLeading: true
            )
            scoreMetric(
                value: viewModel.correctCount,
                symbol: "chevron.compact.right",
                tint: .green,
                arrowLeading: false
            )
        }
    }

    private func scoreMetric(
        value: Int,
        symbol: String,
        tint: Color,
        arrowLeading: Bool
    ) -> some View {
        HStack(spacing: 4) {
            if arrowLeading {
                scoreArrow(symbol: symbol, tint: tint)
            }

            Text("\(value)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.94))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))

            if !arrowLeading {
                scoreArrow(symbol: symbol, tint: tint)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func scoreArrow(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(tint.opacity(0.95))
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
                Color(uiColor: .systemBackground)
                    .onAppear {
                    if self.viewModel == nil {
                        self.viewModel = FlashCardsPlayModeViewModel(deck: deck)
                    }
                }
            }
        }
    }
}

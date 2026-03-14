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
    @State private var leadingChromeWidth: CGFloat = 68
    @State private var trailingChromeWidth: CGFloat = (UIConstants.Size.capsuleHeight * 2) + UIConstants.Spacing.small
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
            let headerTopPadding: CGFloat = resolvedSafeTopInset + UIConstants.Spacing.tiny
            let headerHorizontalPadding: CGFloat = isCompact ? 20 : 32
            let headerBottomPadding: CGFloat = isCompact ? 20 : 30

            ZStack {
                if fullScreenSheetDismiss == nil {
                    screenBackground
                        .ignoresSafeArea()
                }

                if !viewModel.isComplete {
                    VStack(spacing: 0) {
                        header
                            .padding(.top, headerTopPadding)
                            .padding(.horizontal, headerHorizontalPadding)
                            .padding(.bottom, headerBottomPadding)
                            .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { newHeight in
                            if abs(headerHeight - newHeight) > 0.5 {
                                headerHeight = newHeight
                            }
                        }

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

    private var header: some View {
        VStack(spacing: UIConstants.Spacing.standard) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 56, height: 5)
                .accessibilityHidden(true)

            GeometryReader { proxy in
                let sideClearance = max(leadingChromeWidth, trailingChromeWidth)
                let titleWidth = max(
                    0,
                    proxy.size.width - (sideClearance * 2) - (UIConstants.Spacing.standard * 2)
                )

                ZStack {
                    VStack(spacing: 2) {
                        Text(resolvedDeckTitle)
                            .font(.system(size: isCompact ? 20 : 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                            .frame(maxWidth: titleWidth)

                        Text(viewModel.isFlipped ? "ANSWER" : "QUESTION")
                            .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .animation(.spring(response: 0.3), value: viewModel.isFlipped)
                    }

                    HStack(spacing: UIConstants.Spacing.standard) {
                        liveScoreChrome
                            .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.width
                        } action: { newWidth in
                            if abs(leadingChromeWidth - newWidth) > 0.5 {
                                leadingChromeWidth = newWidth
                            }
                        }

                        Spacer(minLength: 0)

                        HStack(spacing: UIConstants.Spacing.small) {
                            editCurrentCardButton
                            dismissButton
                        }
                            .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.width
                        } action: { newWidth in
                            if abs(trailingChromeWidth - newWidth) > 0.5 {
                                trailingChromeWidth = newWidth
                            }
                        }
                    }
                }
            }
                .frame(height: chromeButtonSize)

            progressChrome
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

    private var progressChrome: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))

                    Capsule()
                        .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.82), accentColor, Color.white.opacity(0.92)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                        .frame(
                        width: max(
                            0,
                            min(
                                proxy.size.width,
                                proxy.size.width * viewModel.progressFraction
                            )
                        )
                    )
                }
            }
                .frame(height: 6)

            HStack(spacing: 8) {
                Text("\(viewModel.reviewedCardCount)/\(max(viewModel.totalCardCount, 1)) reviewed")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(Int((viewModel.progressFraction * 100).rounded()))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.3), value: viewModel.currentIndex)
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
        ZStack {
            // Blurred backdrop to focus attention on the summary card.
            Color.black.opacity(0.5).ignoresSafeArea()
                .background(.ultraThinMaterial)

            VStack(spacing: 0) {

                // ── Victory header ───────────────────────────────────────────
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.yellow.opacity(0.2))
                            .frame(width: 120, height: 120)
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(
                                .linearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                            .shadow(color: .orange.opacity(0.5), radius: 10, y: 5)
                    }
                        .padding(.bottom, 8)

                    Text("Session Complete!")
                        .font(isCompact ? .title : .largeTitle)
                        .fontWeight(.black)

                    // XP badge — value comes from the ViewModel.
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("+\(viewModel.sessionXP) XP")
                            .fontWeight(.bold)
                    }
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                        Capsule().fill(
                                .linearGradient(
                                colors: [.orange, .red],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    )
                        .shadow(color: .orange.opacity(0.3), radius: 8, y: 4)
                }
                    .padding(.top, 40)
                    .padding(.bottom, 32)

                // ── Statistics grid ──────────────────────────────────────────
                // Accuracy and duration are computed by the ViewModel —
                // the view simply reads and displays the result.
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 16
                ) {
                    SessionStatBox(
                        title: "Accuracy",
                        value: "\(viewModel.sessionAccuracy)%", // Use ViewModel prop
                        icon: "target",
                        color: .green
                    )
                    SessionStatBox(
                        title: "Time",
                        value: viewModel.formattedSessionDuration, // Use ViewModel prop
                        icon: "timer",
                        color: .blue
                    )
                    SessionStatBox(
                        title: "Correct",
                        value: "\(viewModel.correctCount)",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    SessionStatBox(
                        title: "Wrong",
                        value: "\(viewModel.wrongCards.count)",
                        icon: "xmark.circle.fill",
                        color: .red
                    )
                }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)

                // ── Action buttons ───────────────────────────────────────────
                VStack(spacing: 16) {
                    if !viewModel.wrongCards.isEmpty {
                        Button {
                            viewModel.retryWrongCards()
                        } label: {
                            Label("Retry Wrong Cards", systemImage: "arrow.counterclockwise")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                                .foregroundStyle(.orange)
                                .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }

                    Button(action: handleDismiss) {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 10, y: 5)
                    }
                }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
                .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.2), radius: 30, y: 15)
            )
                .padding(isCompact ? 24 : 60)
        }
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

// MARK: - SessionStatBox

/// A single statistics tile used inside the completion overlay grid.
private struct SessionStatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
            .padding(16)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
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

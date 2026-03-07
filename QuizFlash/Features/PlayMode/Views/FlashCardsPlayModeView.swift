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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    // MARK: - Properties

    /// The deck being studied — passed from the parent and forwarded to the ViewModel.
    let deck: DeckModel

    /// The `@Observable` ViewModel that owns all session state.
    @Bindable var viewModel: FlashCardsPlayModeViewModel

    // MARK: - Convenience

    private var accentColor: Color { ThemeManager.shared.accentColor.color }
    private var isCompact: Bool { horizontalSizeClass == .compact }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let isScreenLandscape = geo.size.width > geo.size.height

            ZStack {
                screenBackground
                    .ignoresSafeArea()

                if !viewModel.isComplete {
                    VStack(spacing: 0) {
                        header
                            .padding(.top, 16)
                            .padding(.horizontal, isCompact ? 20 : 32)
                            .padding(.bottom, isCompact ? 20 : 30)

                        cardArea
                            .padding(.horizontal, isCompact ? 16 : (isScreenLandscape ? geo.size.width * 0.15 : 40))
                            .padding(.bottom, isCompact ? 20 : 40)
                    }
                    .transition(.opacity)
                }

                if viewModel.isComplete {
                    completionOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.isComplete)
        .task {
            if !viewModel.isSessionStarted {
                await viewModel.startSession(container: modelContext.container)
            }
        }
        .onDisappear {
            viewModel.tearDown()
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
                    let card  = viewModel.cards[index]

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
                        removal:   .opacity
                    ))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: viewModel.currentIndex)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 16) {
            // Title + dismiss button
            ZStack {
                HStack {
                    Spacer()
                    Text(viewModel.deck.title)
                        .font(.headline.bold())
                    Spacer()
                }
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 24).bold())
                            .fontDesign(.rounded)
                            .padding(8)
                            .frame(width: 50, height: 50)
                            .background {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Circle()
                                            .fill(Color.white.opacity(0.35))
                                            .blur(radius: 10)
                                            .mask(Capsule().stroke(lineWidth: 4))
                                            .blendMode(.overlay)
                                    }
                            }
                    }
                }
            }

            // Progress bar — one segment per card in the session.
            HStack(spacing: 4) {
                ForEach(viewModel.progressSegments, id: \.id) { segment in
                    Capsule()
                        .fill(segment.completed ? accentColor : Color.gray.opacity(0.5))
                        .frame(height: 4)
                }
            }
            .animation(.spring(response: 0.3), value: viewModel.currentIndex)

            // Question/Answer indicator and live score counters.
            HStack {
                Text(viewModel.isFlipped ? "ANSWER" : "QUESTION")
                    .font(.caption.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                    .animation(.spring(response: 0.3), value: viewModel.isFlipped)

                Spacer()

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text("\(viewModel.wrongCards.count)").font(.subheadline.weight(.semibold))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("\(viewModel.correctCount)").font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
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
                        icon:  "target",
                        color: .green
                    )
                    SessionStatBox(
                        title: "Time",
                        value: viewModel.formattedSessionDuration, // Use ViewModel prop
                        icon:  "timer",
                        color: .blue
                    )
                    SessionStatBox(
                        title: "Correct",
                        value: "\(viewModel.correctCount)",
                        icon:  "checkmark.circle.fill",
                        color: .green
                    )
                    SessionStatBox(
                        title: "Wrong",
                        value: "\(viewModel.wrongCards.count)",
                        icon:  "xmark.circle.fill",
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

                    Button { dismiss() } label: {
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
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)]
                : [Color(uiColor: .systemGray6), Color(uiColor: .systemBackground)],
            startPoint: .top,
            endPoint:   .bottom
        )
    }
}

// MARK: - SessionStatBox

/// A single statistics tile used inside the completion overlay grid.
private struct SessionStatBox: View {
    let title: String
    let value: String
    let icon:  String
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

    @State private var viewModel: FlashCardsPlayModeViewModel? = nil

    var body: some View {
        Group {
            if let vm = viewModel {
                FlashCardsPlayModeView(deck: deck, viewModel: vm)
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

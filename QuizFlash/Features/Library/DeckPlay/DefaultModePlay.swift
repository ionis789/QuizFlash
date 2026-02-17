//
//  DefaultModePlay.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

struct DefaultModePlay: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var viewModel: DefaultModePlayViewModel

    private var accentColor: Color { ThemeManager.shared.accentColor.color }
    private var isCompact: Bool { horizontalSizeClass == .compact }

    private var screenBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)]
            : [Color(uiColor: .systemGray6), Color(uiColor: .systemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    init(deck: DeckModel) {
        _viewModel = State(initialValue: DefaultModePlayViewModel(deck: deck))
    }

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
        .navigationBarHidden(true)
    }

    // MARK: - Card Area
    private var cardArea: some View {
        ZStack {
            if viewModel.currentIndex < viewModel.cards.count {
                // Notice the use of Bindable to pass the binding down safely
                @Bindable var bindableViewModel = viewModel
                
                GameplayCard(
                    card: viewModel.cards[viewModel.currentIndex],
                    onSwipe: { direction in
                        viewModel.handleSwipe(direction)
                    },
                    isFlipped: $bindableViewModel.isFlipped
                )
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.82)),
                        removal: .opacity
                    )
                )
                .id(viewModel.cards[viewModel.currentIndex].createdAt)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: viewModel.currentIndex)
    }

    // MARK: - Header
    private var header: some View {
        VStack(spacing: 16) {
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
                            .font(.headline.bold())
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
            }

            // Progress Bar
            HStack(spacing: 4) {
                ForEach(0..<viewModel.cards.count, id: \.self) { index in
                    Capsule()
                        .fill(index < viewModel.currentIndex ? accentColor : Color.gray.opacity(0.5))
                        .frame(height: 4)
                }
            }
            .animation(.spring(response: 0.3), value: viewModel.currentIndex)

            // Q/A Indicator & Stats
            HStack {
                Text(viewModel.isFlipped ? "ANSWER" : "QUESTION")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .animation(.spring(response: 0.3), value: viewModel.isFlipped)

                Spacer()

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("\(viewModel.correctCount)").font(.subheadline.weight(.semibold))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text("\(viewModel.wrongCards.count)").font(.subheadline.weight(.semibold))
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
            Color.black.opacity(0.4).ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: isCompact ? 60 : 80))
                    .foregroundStyle(.yellow)

                Text("Complete!")
                    .font(isCompact ? .title : .largeTitle)
                    .fontWeight(.bold)

                HStack(spacing: isCompact ? 24 : 40) {
                    StatItem(value: "\(viewModel.correctCount)", label: "Correct", color: .green)
                    StatItem(value: "\(viewModel.wrongCards.count)", label: "Wrong", color: .red)
                    StatItem(value: "\(viewModel.cards.count)", label: "Total", color: .blue)
                }

                VStack(spacing: 12) {
                    if !viewModel.wrongCards.isEmpty {
                        Button {
                            viewModel.retryWrongCards()
                        } label: {
                            Label("Retry Wrong Cards", systemImage: "arrow.counterclockwise")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: isCompact ? .infinity : 280)
                                .padding(.vertical, 14)
                                .background(Color.orange, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                        }
                    }

                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: isCompact ? .infinity : 280)
                            .padding(.vertical, 14)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 8)
            }
            .padding(isCompact ? 28 : 40)
            .background(
                RoundedRectangle(cornerRadius: isCompact ? 24 : 32)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
            )
            .padding(.horizontal, isCompact ? 32 : 60)
        }
    }
}

private struct StatItem: View {
    let value: String
    let label: String
    var color: Color = .primary
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

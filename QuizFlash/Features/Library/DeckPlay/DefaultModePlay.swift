import SwiftUI

struct DefaultModePlay: View {
    let deck: DeckModel

    @Environment(\.dismiss) private var dismiss

    @State private var cards: [CardModel]
    @State private var currentIndex: Int = 0
    @State private var correctCount: Int = 0
    @State private var isFlipped: Bool = false
    @State private var isComplete: Bool = false
    @State private var wrongCards: [CardModel] = []

    init(deck: DeckModel) {
        self.deck = deck
        _cards = State(initialValue: deck.cards.shuffled())
    }

    private var progress: Double {
        guard !cards.isEmpty else { return 0 }
        return Double(currentIndex) / Double(cards.count)
    }

    private var scorePercentage: Int {
        guard currentIndex > 0 else { return 0 }
        return Int((Double(correctCount) / Double(currentIndex)) * 100)
    }

    var body: some View {
        ZStack {
            // Background
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Minimal header
                header
                    .padding(.top, 12)
                    .padding(.horizontal, 20)

                Spacer()

                // Card
                ZStack {
                    if currentIndex < cards.count {
                        cardView(at: currentIndex)
                            .transition(.asymmetric(
                            insertion: .scale(scale: 0.95).combined(with: .opacity),
                            removal: .identity
                        ))
                            .id(cards[currentIndex].createdAt)
                    }
                }
                    .frame(height: 480)
                    .padding(.horizontal, 24)

                Spacer()

                // Footer hints
                footerHint
                    .padding(.bottom, 40)
            }

            // Completion overlay
            if isComplete {
                completionOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isComplete)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentIndex)
            .navigationBarHidden(true)
            .onChange(of: currentIndex) {
            isFlipped = false
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack {




            // Score pill


            Spacer()

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }

    // MARK: - Card View
    @ViewBuilder
    private func cardView(at index: Int) -> some View {
        let card = cards[index]

        SwipeableCard(onSwipe: handleSwipe, onTap: handleTap) {
            FlipCardPreview(card: card, isPreviewMode: false, isFlipped: $isFlipped)
        }
    }

    private func handleTap() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            isFlipped.toggle()
        }
    }

    // MARK: - Footer
    private var footerHint: some View {
        HStack {

            // Progress pill
            HStack(spacing: 8) {
                Text("\(currentIndex)/\(cards.count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()

                // Mini progress bar
                Capsule()
                    .fill(Color(uiColor: .systemGray5))
                    .frame(width: 200, height: 4)
                    .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: 200 * progress, height: 4)
                        .animation(.spring(response: 0.3), value: progress)
                }
            }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            
            

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(correctCount)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
        }

//        HStack(spacing: 32) {
//            Label("Wrong", systemImage: "arrow.left")
//                .foregroundStyle(.red.opacity(0.8))
//
//            Label("Flip", systemImage: "hand.tap")
//                .foregroundStyle(.secondary)
//
//            Label("Correct", systemImage: "arrow.right")
//                .foregroundStyle(.green.opacity(0.8))
//        }
//        .font(.caption.weight(.medium))
    }

    // MARK: - Completion Overlay
    private var completionOverlay: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .padding(.bottom, 4)

                // Title
                Text("Complete!")
                    .font(.title2.weight(.bold))

                // Score
                Text("\(correctCount) of \(cards.count) correct")
                    .font(.body)
                    .foregroundStyle(.secondary)

                // Percentage
                Text("\(scorePercentage)%")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                // Buttons
                VStack(spacing: 10) {
                    if !wrongCards.isEmpty {
                        Button {
                            retryWrongCards()
                        } label: {
                            Label("Retry \(wrongCards.count) Mistakes", systemImage: "arrow.counterclockwise")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                            .foregroundStyle(.primary)
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }
                }
                    .padding(.top, 8)
            }
                .padding(28)
                .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
            )
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Actions
    private func handleSwipe(_ direction: SwipeDirection) {
        guard currentIndex < cards.count else { return }

        if direction == .right {
            correctCount += 1
        } else {
            wrongCards.append(cards[currentIndex])
        }

        currentIndex += 1

        if currentIndex >= cards.count {
            isComplete = true
        }
    }

    private func retryWrongCards() {
        let retry = wrongCards
        wrongCards = []
        cards = retry.shuffled()
        currentIndex = 0
        correctCount = 0
        isFlipped = false
        isComplete = false
    }
}

// MARK: - Supporting Views

private struct ScoreCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.subheadline.weight(.bold))

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct HintLabel: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
            .foregroundStyle(color)
    }
}

private struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

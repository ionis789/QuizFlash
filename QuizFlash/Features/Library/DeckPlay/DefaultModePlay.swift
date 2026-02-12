import SwiftUI

struct DefaultModePlay: View {
    let deck: DeckModel
    @Environment(\.dismiss) private var dismiss

    @State private var cards: [CardModel]
    @State private var currentIndex: Int = 0
    @State private var correctCount: Int = 0
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

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text(deck.title).font(.title3.bold())
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.semibold))
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                    // CARD AREA (Dynamic Size pt iPad)
                    ZStack {
                        if currentIndex < cards.count {
                            GameplayCard(
                                card: cards[currentIndex],
                                onSwipe: handleSwipe
                            )
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.95).combined(with: .opacity),
                                removal: .identity
                            ))
                            .id(cards[currentIndex].id)
                        }
                    }
                    // AICI e fixul pentru iPad: lățime dinamică, max 600px
                    .frame(width: min(geo.size.width - 40, 600), height: geo.size.height * 0.75)
                    .padding(.vertical, 20)

                    Spacer()

                    // Footer
                    HStack {
                        // Progress
                        HStack(spacing: 8) {
                            Text("\(currentIndex)/\(cards.count)")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                            Capsule().fill(Color(uiColor: .systemGray5)).frame(width: 150, height: 4)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.blue).frame(width: 150 * progress, height: 4)
                                }
                        }
                        .padding(10).background(.ultraThinMaterial, in: Capsule())

                        // Score
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("\(correctCount)").font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                        .padding(10).background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.bottom, 20)
                }
                .frame(width: geo.size.width, height: geo.size.height)

                // Completion Overlay
                if isComplete {
                    completionOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .zIndex(10)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isComplete)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentIndex)
        .navigationBarHidden(true)
    }
    
    // ... Logică identică ...
    private var completionOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 60)).foregroundStyle(.green)
                Text("Complete!").font(.title.bold()).foregroundStyle(.white)
                Text("Score: \(Int((Double(correctCount)/Double(cards.count))*100))%").font(.title2.bold()).foregroundStyle(.white.opacity(0.9))
                HStack(spacing: 20) {
                    if !wrongCards.isEmpty {
                        Button("Retry Mistakes") { retryWrongCards() }.buttonStyle(.borderedProminent).tint(.orange)
                    }
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent).tint(.blue)
                }
            }
            .padding(40).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }

    private func handleSwipe(_ direction: SwipeDirection) {
        guard currentIndex < cards.count else { return }
        if direction == .right { correctCount += 1 } else { wrongCards.append(cards[currentIndex]) }
        currentIndex += 1
        if currentIndex >= cards.count { isComplete = true }
    }

    private func retryWrongCards() {
        cards = wrongCards.shuffled(); wrongCards = []; currentIndex = 0; correctCount = 0; isComplete = false
    }
}


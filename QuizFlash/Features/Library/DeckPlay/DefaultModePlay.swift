//
//  DefaultModePlay.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

struct DefaultModePlay: View {
    let deck: DeckModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var cards: [CardModel]
    @State private var currentIndex: Int = 0
    @State private var correctCount: Int = 0
    @State private var isComplete: Bool = false
    @State private var wrongCards: [CardModel] = []
    @State private var isFlipped: Bool = false

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

    private static func studyOrderedCards(_ deckCards: [CardModel]) -> [CardModel] {
        deckCards.sorted { a, b in
            let aSeen = a.lastSeenAt != nil
            let bSeen = b.lastSeenAt != nil
            if !aSeen, bSeen { return true }
            if aSeen, !bSeen { return false }
            if !aSeen, !bSeen { return a.createdAt < b.createdAt }
            guard let aDate = a.lastSeenAt, let bDate = b.lastSeenAt else { return false }
            if aDate != bDate { return aDate < bDate }
            return a.timesWrong > b.timesWrong
        }
    }

    init(deck: DeckModel) {
        self.deck = deck
        _cards = State(initialValue: Self.studyOrderedCards(deck.cards))
    }

    var body: some View {
        GeometryReader { geo in
            let isScreenLandscape = geo.size.width > geo.size.height

            ZStack {
                screenBackground
                    .ignoresSafeArea()

                if !isComplete {
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


                if isComplete {
                    completionOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isComplete)
            .navigationBarHidden(true)
    }

    // MARK: - Card Area
    private var cardArea: some View {
        ZStack {
            if currentIndex < cards.count {
                GameplayCard(
                    card: cards[currentIndex],
                    onSwipe: handleSwipe,
                    isFlipped: $isFlipped // Pasăm referința (Binding) mai jos
                )
                    .transition(
                        .asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.82)),
                        removal: .opacity
                    )
                )
                    .id(cards[currentIndex].createdAt)
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: currentIndex)
    }

    // MARK: - NOU: Header Compus Minimalist
    private var header: some View {
        VStack(spacing: 16) {
            // Rândul 1: Titlu și X

            ZStack {
                HStack {
                    Spacer()
                    Text(deck.title)
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


            // Rândul 2: Progress Bar Segmentat
            HStack(spacing: 4) {
                ForEach(0..<cards.count, id: \.self) { index in
                    Capsule()
                        .fill(
                        index < currentIndex ? accentColor : Color.gray.opacity(0.5)
                    )
                        .frame(height: 4)
                }
            }
                .animation(.spring(response: 0.3), value: currentIndex)

            // Rândul 3: Q/A Indicator (Stânga) și Stats (Dreapta)
            HStack {
                // Indicator Q/A legat de starea `isFlipped`

                Text(isFlipped ? "ANSWER" : "QUESTION")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .animation(.spring(response: 0.3), value: isFlipped)

                Spacer()

                // Stats
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("\(correctCount)").font(.subheadline.weight(.semibold))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text("\(wrongCards.count)").font(.subheadline.weight(.semibold))
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
                    StatItem(value: "\(correctCount)", label: "Correct", color: .green)
                    StatItem(value: "\(wrongCards.count)", label: "Wrong", color: .red)
                    StatItem(value: "\(cards.count)", label: "Total", color: .blue)
                }

                VStack(spacing: 12) {
                    if !wrongCards.isEmpty {
                        Button { retryWrongCards() } label: {
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

    private func handleSwipe(_ direction: SwipeDirection) {
        guard currentIndex < cards.count else { return }
        let card = cards[currentIndex]
        let now = Date()

        if card.stats == nil { card.stats = CardStats(card: card) }
        if let stats = card.stats {
            stats.totalAttempts += 1
            stats.lastAttemptDate = now
            if direction == .right {
                stats.correctCount += 1
                stats.streak += 1
            } else {
                stats.wrongCount += 1
                stats.streak = 0
            }
        }

        if direction == .right {
            correctCount += 1
            card.lastSeenAt = now
            card.timesCorrect += 1
        } else {
            wrongCards.append(card)
            card.lastSeenAt = now
            card.timesWrong += 1
        }

        // Resetăm starea cardului la QUESTION pentru următorul card
        isFlipped = false

        currentIndex += 1
        if currentIndex >= cards.count { isComplete = true }
    }

    private func retryWrongCards() {
        let retry = wrongCards
        wrongCards = []
        cards = DefaultModePlay.studyOrderedCards(retry)
        currentIndex = 0
        correctCount = 0
        isComplete = false
        isFlipped = false // Asigurăm resetarea la Retry
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

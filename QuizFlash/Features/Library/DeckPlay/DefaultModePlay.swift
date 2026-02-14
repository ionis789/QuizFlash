//
//  DefaultModePlay.swift
//  QuizFlash
//
//  Adaptive card game with swipe and study-order (learning) algorithm.
//

import SwiftUI
import SwiftData

struct DefaultModePlay: View {
    let deck: DeckModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var cards: [CardModel]
    @State private var currentIndex: Int = 0
    @State private var correctCount: Int = 0
    @State private var isComplete: Bool = false
    @State private var wrongCards: [CardModel] = []

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var isIPad: Bool { horizontalSizeClass == .regular && verticalSizeClass == .regular }

    /// Same background as editor card preview — depth and consistency
    private var screenBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)]
                : [Color(uiColor: .systemGray6), Color(uiColor: .systemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Study order: never seen first, then oldest seen, then most wrong (prioritize weak cards)
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
    
    private var progress: Double {
        guard !cards.isEmpty else { return 0 }
        return Double(currentIndex) / Double(cards.count)
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                screenBackground
                    .ignoresSafeArea()

                if isLandscape {
                    landscapeLayout(size: geo.size)
                } else {
                    portraitLayout(size: geo.size)
                }
                
                // Completion overlay
                if isComplete {
                    completionOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isComplete)
        .navigationBarHidden(true)
    }
    
    // MARK: - Portrait Layout
    
    private func portraitLayout(size: CGSize) -> some View {
        let horizontalPadding: CGFloat = isIPad ? 80 : 24
        let headerFooterHeight: CGFloat = isIPad ? 180 : 160
        
        let cardHeight = size.height - headerFooterHeight
        let cardWidth = size.width - (horizontalPadding * 2)
        
        let maxHeight = cardWidth * 1.6
        let finalCardHeight = min(cardHeight, maxHeight)
        
        return VStack(spacing: 0) {
            header
                .padding(.top, 12)
                .padding(.horizontal, 20)
            
            Spacer()
            
            cardArea(width: cardWidth, height: finalCardHeight)
            
            Spacer()
            
            footerHint
                .padding(.bottom, isCompact ? 40 : 60)
        }
    }
    
    // MARK: - Landscape Layout
    
    private func landscapeLayout(size: CGSize) -> some View {
        let sidebarWidth: CGFloat = 150
        let statsWidth: CGFloat = 100
        let cardAreaWidth = size.width - sidebarWidth - statsWidth - 60
        let cardHeight = size.height * 0.85
        let cardWidth = min(cardAreaWidth, cardHeight * 1.3)
        
        return HStack(spacing: 0) {
            VStack(spacing: 20) {
                Text(deck.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                
                progressIndicator
                
                Spacer()
                
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .frame(width: sidebarWidth)
            .padding(.vertical, 20)
            
            cardArea(width: cardWidth, height: cardHeight)
                .frame(maxWidth: .infinity)
            
            VStack(spacing: 16) {
                StatItem(value: "\(correctCount)", label: "Correct", color: .green)
                StatItem(value: "\(wrongCards.count)", label: "Wrong", color: .red)
            }
            .frame(width: statsWidth)
            .padding(.vertical, 20)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Card Area (UPDATED)
    
    private func cardArea(width: CGFloat, height: CGFloat) -> some View {
        let safeWidth = max(width, 100)
        let safeHeight = max(height, 100)

        return ZStack {
            if currentIndex < cards.count {
                GameplayCard(
                    card: cards[currentIndex],
                    onSwipe: handleSwipe
                )
                .frame(width: safeWidth, height: safeHeight)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity)
                            .animation(.spring(response: 0.4, dampingFraction: 0.82)),
                        removal: .identity
                    )
                )
                .id(cards[currentIndex].createdAt)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: currentIndex)
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text(deck.title)
                .font(.title3.bold())
            
            Spacer()
            
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        VStack(spacing: 8) {
            Text("\(currentIndex)/\(cards.count)")
                .font(.headline.monospacedDigit())
            
            Capsule()
                .fill(Color(uiColor: .systemGray5))
                .frame(width: isCompact ? 200 : 120, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: (isCompact ? 200 : 120) * progress, height: 4)
                        .animation(.spring(response: 0.3), value: progress)
                }
        }
    }
    
    // MARK: - Footer
    
    private var footerHint: some View {
        HStack(spacing: isCompact ? 16 : 24) {
            progressIndicator
            
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(correctCount)")
                        .font(.subheadline.weight(.semibold))
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("\(wrongCards.count)")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }
    
    // MARK: - Completion Overlay
    
    private var completionOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
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
                        Button {
                            retryWrongCards()
                        } label: {
                            Label("Retry Wrong Cards", systemImage: "arrow.counterclockwise")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: isCompact ? .infinity : 280)
                                .padding(.vertical, 14)
                                .background(Color.orange, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                        }
                    }
                    
                    Button {
                        dismiss()
                    } label: {
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
    
    // MARK: - Actions

    private func handleSwipe(_ direction: SwipeDirection) {
        guard currentIndex < cards.count else { return }
        let card = cards[currentIndex]
        let now = Date()

        if direction == .right {
            correctCount += 1
            card.lastSeenAt = now
            card.timesCorrect += 1
        } else {
            wrongCards.append(card)
            card.lastSeenAt = now
            card.timesWrong += 1
        }

        currentIndex += 1
        if currentIndex >= cards.count {
            isComplete = true
        }
    }

    private func retryWrongCards() {
        let retry = wrongCards
        wrongCards = []
        cards = DefaultModePlay.studyOrderedCards(retry)
        currentIndex = 0
        correctCount = 0
        isComplete = false
    }
}

// MARK: - Supporting Views

private struct StatItem: View {
    let value: String
    let label: String
    var color: Color = .primary
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

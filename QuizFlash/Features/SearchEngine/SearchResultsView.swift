//
//  SearchResultsView.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

struct SearchResultsView: View {
    @Environment(\.modelContext) private var context
    @Environment(NavigationManager.self) private var router
    
    let results: [DeckSearchResultItem]
    let query: String
    
    // Triggered when the user taps on a specific CARD
    let onCardTap: (PersistentIdentifier) -> Void
    
    var body: some View {
        if results.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                LazyVStack(spacing: 32) {
                    ForEach(results) { result in
                        searchResultGroup(for: result)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 60)
            }
        }
    }
    
    // MARK: - UI Components
    private func searchResultGroup(for result: DeckSearchResultItem) -> some View {
        VStack(spacing: 16) {
            // 1. DECK CONTAINER (Main Parent)
            Button {
                navigateToDeck(with: result.id)
            } label: {
                deckHeader(for: result)
            }
            .buttonStyle(ScaleButtonStyle())
            
            // 2. MATCHING CARDS (Centered Children)
            if !result.matchedCards.isEmpty {
                VStack(spacing: 12) {
                    ForEach(result.matchedCards) { card in
                        Button {
                            onCardTap(card.id)
                        } label: {
                            cardSnippetRow(card: card)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.85)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
    
    private func deckHeader(for result: DeckSearchResultItem) -> some View {
        let deckColor = Color(hex: result.deckColorHex) ?? .blue
        
        return HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [deckColor.opacity(0.8), deckColor.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: result.deckIcon.isEmpty ? "sparkles.rectangle.stack.fill" : result.deckIcon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HighlightedText(
                    text: result.deckTitle,
                    query: query,
                    font: .title3.weight(.bold),
                    baseColor: .primary
                )
                
                Text("\(result.matchedCards.count) matching card\(result.matchedCards.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
    
    private func cardSnippetRow(card: MatchedCardInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            
            // Side Indicator Badge
            HStack {
                Text(card.matchSide.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(badgeColor(for: card.matchSide).opacity(0.15))
                    .foregroundStyle(badgeColor(for: card.matchSide))
                    .clipShape(Capsule())
                Spacer()
            }
            
            // Snippet
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.quote")
                    .font(.subheadline)
                    .foregroundStyle(ThemeManager.shared.accentColor.color)
                    .padding(.top, 2)
                
                HighlightedText(
                    text: card.snippet,
                    query: query,
                    font: .subheadline,
                    baseColor: .secondary
                )
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }
    
    private func badgeColor(for side: CardSideMatch) -> Color {
        switch side {
        case .front: return .blue
        case .back: return .purple
        case .both: return .orange
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            Text("No Results Found")
                .font(.title3.weight(.semibold))
            
            Text("Try searching for different keywords.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
    
    // MARK: - Actions
    private func navigateToDeck(with id: PersistentIdentifier) {
        if let deck = context.model(for: id) as? DeckModel {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                router.path.append(deck)
            }
        }
    }
}

//
//  SearchResultsView.swift
//  QuizFlash
//
//  Created by Ion Socol on 17.02.2026.
//


import SwiftUI
import SwiftData

struct SearchResultsView: View {
    @Environment(\.modelContext) private var context
    @Environment(NavigationManager.self) private var router
    
    let results: [DeckSearchResultItem]
    let query: String
    
    var body: some View {
        if results.isEmpty {
            emptyStateView
        } else {
            LazyVStack(spacing: 16) {
                ForEach(results) { result in
                    Button {
                        navigateToDeck(with: result.id)
                    } label: {
                        searchResultCard(for: result)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - UI Components
    
    private func searchResultCard(for result: DeckSearchResultItem) -> some View {
        let deckColor = Color(hex: result.deckColorHex) ?? .blue
        
        return VStack(alignment: .leading, spacing: 12) {
            // Deck Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [deckColor.opacity(0.7), deckColor.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)

                    Image(systemName: result.deckIcon.isEmpty ? "sparkles.rectangle.stack.fill" : result.deckIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                
                HighlightedText(
                    text: result.deckTitle,
                    query: query,
                    font: .body.weight(.semibold),
                    baseColor: .primary
                )
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            
            // Matched Snippets
            if !result.matchedCards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    // Show up to 3 snippets to keep the UI clean
                    ForEach(result.matchedCards.prefix(3)) { card in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "text.quote")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                            
                            HighlightedText(
                                text: card.snippet,
                                query: query,
                                font: .caption,
                                baseColor: .secondary
                            )
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        }
                    }
                    
                    if result.matchedCards.count > 3 {
                        Text("+ \(result.matchedCards.count - 3) more matches")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 24)
                    }
                }
                .padding(.leading, 12)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        // Fetch the active DeckModel instance from the main context
        if let deck = context.model(for: id) as? DeckModel {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                router.path.append(deck)
            }
        }
    }
}

//
//  DeckProgressView.swift
//  QuizFlash
//

import SwiftUI

struct DeckProgressView: View {
    let deck: DeckModel
    let stats: DeckStats
    let cards: [GridCardInfo]
    
    // MARK: - Deck-Specific Metrics Logic
    
    private var totalCards: Int { max(deck.cardCount, 1) }
    
    private var newCards: Int {
        cards.filter { $0.reviewHistoryIsEmpty }.count
    }
    
    private var learningCards: Int {
        cards.filter { !$0.reviewHistoryIsEmpty && $0.interval < 14 }.count
    }
    
    private var masteredCards: Int {
        cards.filter { !$0.reviewHistoryIsEmpty && $0.interval >= 14 }.count
    }
    
    private var newRatio: Double { Double(newCards) / Double(totalCards) }
    private var learningRatio: Double { Double(learningCards) / Double(totalCards) }
    private var masteredRatio: Double { Double(masteredCards) / Double(totalCards) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Premium section header matching standard iOS HIG
            Text("DECK PROGRESS")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 24)
            
            VStack(spacing: 24) {
                // ── Segmented Progress Bar ─────────────────────────────────
                GeometryReader { geo in
                    HStack(spacing: 6) { // Wider spacing between segments
                        if masteredCards > 0 {
                            Capsule()
                                .fill(Color.teal.gradient) // Gradients add a premium touch
                                .frame(width: max(0, geo.size.width * masteredRatio - 6))
                        }
                        if learningCards > 0 {
                            Capsule()
                                .fill(Color.orange.gradient)
                                .frame(width: max(0, geo.size.width * learningRatio - 6))
                        }
                        if newCards > 0 {
                            Capsule()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: max(0, geo.size.width * newRatio - 6))
                        }
                    }
                }
                .frame(height: 16) // Thicker bar for better visibility
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: deck.cardCount)
                
                // ── Legend ───────────────────────────────────────────────
                HStack(spacing: 0) {
                    LegendItem(color: .teal, count: masteredCards, label: "Mastered")
                    Spacer()
                    LegendItem(color: .orange, count: learningCards, label: "Learning")
                    Spacer()
                    LegendItem(color: .gray.opacity(0.5), count: newCards, label: "New")
                }
                
                Divider()
                    .overlay(.white.opacity(0.05))
                
                // ── Deck Quick Stats (Reference App Style) ────────────────
                HStack {
                    QuickStat(title: "Due Today", value: "\(stats.dueCards)", color: stats.dueCards > 0 ? .red : .primary)
                    Spacer()
                    QuickStat(title: "Accuracy", value: "\(stats.accuracy)%", color: .primary)
                    Spacer()
                    QuickStat(title: "Reviews", value: "\(stats.totalReviews)", color: .primary)
                }
            }
            .padding(24) // Spacious padding inside the card
            .background {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(
                        Color(uiColor: .secondarySystemBackground)
                        .shadow(.inner(color: Color.white.opacity(0.15), radius: 1, x: 0, y: 0))
                )
            }
                .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Subcomponents

private struct LegendItem: View {
    let color: Color
    let count: Int
    let label: String
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            HStack(spacing: 4) {
                Text("\(count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct QuickStat: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { // Left-aligned looks more analytical/modern
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded)) // Huge numbers
                .foregroundStyle(color)
            
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

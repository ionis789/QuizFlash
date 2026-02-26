//
//  DeckProgressView.swift
//  QuizFlash
//
//  Created by Ion Socol on 26.02.2026.
//

import SwiftUI

struct DeckProgressView: View {
    let deck: DeckModel
    let stats: DeckStats
    
    // MARK: - Deck-Specific Metrics Logic
    
    private var totalCards: Int { max(deck.cards.count, 1) } // Evităm împărțirea la zero
    
    // Carduri neatinse
    private var newCards: Int {
        deck.cards.filter { $0.reviewHistory.isEmpty }.count
    }
    
    // Carduri în proces de învățare (interval sub 14 zile)
    private var learningCards: Int {
        deck.cards.filter { !$0.reviewHistory.isEmpty && $0.interval < 14 }.count
    }
    
    // Carduri bine reținute (interval >= 14 zile)
    private var masteredCards: Int {
        deck.cards.filter { !$0.reviewHistory.isEmpty && $0.interval >= 14 }.count
    }
    
    private var newRatio: Double { Double(newCards) / Double(totalCards) }
    private var learningRatio: Double { Double(learningCards) / Double(totalCards) }
    private var masteredRatio: Double { Double(masteredCards) / Double(totalCards) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DECK PROGRESS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            
            VStack(spacing: 20) {
                
                // ── Segmented Progress Bar ─────────────────────────────────
                GeometryReader { geo in
                    HStack(spacing: 4) {
                        // Mastered (Verde/Teal)
                        if masteredCards > 0 {
                            Capsule()
                                .fill(Color.teal)
                                .frame(width: max(0, geo.size.width * masteredRatio - 4))
                        }
                        // Learning (Galben/Portocaliu)
                        if learningCards > 0 {
                            Capsule()
                                .fill(Color.orange)
                                .frame(width: max(0, geo.size.width * learningRatio - 4))
                        }
                        // New (Gri deschis)
                        if newCards > 0 {
                            Capsule()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: max(0, geo.size.width * newRatio - 4))
                        }
                    }
                }
                .frame(height: 12)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: deck.cards.count)
                
                // ── Legendă ───────────────────────────────────────────────
                HStack(spacing: 0) {
                    LegendItem(color: .teal, count: masteredCards, label: "Mastered")
                    Spacer()
                    LegendItem(color: .orange, count: learningCards, label: "Learning")
                    Spacer()
                    LegendItem(color: .secondary.opacity(0.5), count: newCards, label: "New")
                }
                
                Divider()
                
                // ── Deck Quick Stats ──────────────────────────────────────
                HStack {
                    QuickStat(title: "Due Today", value: "\(stats.dueCards)", color: stats.dueCards > 0 ? .red : .primary)
                    Spacer()
                    QuickStat(title: "Accuracy", value: "\(stats.accuracy)%", color: .primary)
                    Spacer()
                    QuickStat(title: "Total Reviews", value: "\(stats.totalReviews)", color: .primary)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .padding(.horizontal, 20)
        }
    }
}

private struct LegendItem: View {
    let color: Color
    let count: Int
    let label: String
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count)")
                .font(.subheadline.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct QuickStat: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

//
//  SearchResultsView.swift
//  QuizFlash
//
//  ARCHITECTURE
//  ─────────────────────────────────────────────────────────────────────────────
//
//  ScrollView  (owned by LibraryLayout's ScrollViewReader)
//    └── LazyVStack  ← deck groups are lazy; only visible ones are alive
//          └── SearchResultGroupView  (Equatable — skips redraws if unchanged)
//                ├── DeckHeaderRow          — always visible, tap → open deck
//                └── CardListSection
//                      ├── Collapsed:  first `Layout.previewCount` (3) cards
//                      │               + "Show N more" button  (if overflow)
//                      └── Expanded:   ALL matchedCards in a LazyVStack
//                                      so only cards scrolled into view get
//                                      their HighlightedText tasks spawned.
//                                      No "open deck" CTA — everything is
//                                      available inline with highlights.
//
//  WHY NO ANIMATIONS ON THE LIST:
//  Animating a LazyVStack during rapid search-result streaming (5+ updates/sec)
//  causes SwiftUI layout-engine thrash. Animations live only on discrete user
//  actions (expand tap = withAnimation(.spring)).

import SwiftUI
import SwiftData

// MARK: - Layout Constants

private enum Layout {
    /// Cards shown before the "Show more" button appears.
    static let previewCount = 3
}

// MARK: - Container

/// Displays a list of search results matching the query.
/// List items use a lazy container to defer loading of card previews.
struct SearchResultsView: View {
    @Environment(\.modelContext) private var context
    @Environment(NavigationManager.self) private var router
    @Environment(LibraryViewModel.self) private var viewModel

    let results: [DeckSearchResultItem]
    let query: String
    let isSearchLoading: Bool
    let onCardTap: (PersistentIdentifier) -> Void

    var body: some View {
        LazyVStack(spacing: 28) {
            ForEach(results) { result in
                SearchResultGroupView(
                    result: result,
                    query: query,
                    isExpanded: viewModel.expandedSearchDecks.contains(result.id),
                    onDeckTap: { navigateToDeck(with: result.id) },
                    onCardTap: onCardTap,
                    onToggleExpand: { toggleExpansion(for: result.id) }
                )
                    .equatable()
            }
        }
            .safeAreaPadding(.top, 55)
            .safeAreaPadding(.bottom, 80)
    }

    // MARK: - Helpers

    /// Animated toggle for expanding a specific result deck.
    private func toggleExpansion(for id: PersistentIdentifier) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            viewModel.toggleSearchDeckExpansion(for: id)
        }
    }

    private func navigateToDeck(with id: PersistentIdentifier) {
        guard let deck = context.safeModel(for: id, as: DeckModel.self) else { return }
        // Back label is frozen at push time — "Search" indicates the user navigated
        // from a search result, so the back button correctly reads "< Search".
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            router.append(DeckNavigationValue(
                deckID: deck.persistentModelID,
                backLabel: "Search"
            ))
        }
    }
}

// MARK: - Equatable Group View

private struct SearchResultGroupView: View, Equatable {

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.result == rhs.result
            && lhs.query == rhs.query
            && lhs.isExpanded == rhs.isExpanded
    }

    let result: DeckSearchResultItem
    let query: String
    let isExpanded: Bool
    let onDeckTap: () -> Void
    let onCardTap: (PersistentIdentifier) -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onDeckTap) {
                DeckHeaderRow(result: result, query: query)
            }
                .buttonStyle(ScaleButtonStyle())

            if !result.matchedCards.isEmpty {
                CardListSection(
                    result: result,
                    query: query,
                    isExpanded: isExpanded,
                    onCardTap: onCardTap,
                    onToggleExpand: onToggleExpand
                )
            }
        }
    }
}

// MARK: - Deck Header Row

private struct DeckHeaderRow: View {
    let result: DeckSearchResultItem
    let query: String

    var body: some View {
        let deckColor = Color(hex: result.deckColorHex) ?? .blue
        HStack(spacing: 14) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(LinearGradient(
                    colors: [deckColor.opacity(0.8), deckColor.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                    .frame(width: 44, height: 44)
                Image(systemName: result.deckIcon.isEmpty
                    ? "sparkles.rectangle.stack.fill"
                : result.deckIcon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }

            // Title + match count
            VStack(alignment: .leading, spacing: 3) {
                HighlightedText(
                    text: result.deckTitle,
                    query: query,
                    font: .title3.weight(.bold),
                    baseColor: .primary
                )
                Text(matchCountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground)) // Or ThemeManager if custom card background is preferred.
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    private var matchCountLabel: String {
        let n = result.totalMatchedCardsCount
        // If we hit the 200-card cap, show "200+" to signal truncation.
        if result.overflowCardCount > 0 {
            return "\(result.matchedCards.count)+ matching cards"
        }
        return "\(n) matching card\(n == 1 ? "" : "s")"
    }
}

// MARK: - Card List Section

private struct CardListSection: View {

    let result: DeckSearchResultItem
    let query: String
    let isExpanded: Bool
    let onCardTap: (PersistentIdentifier) -> Void
    let onToggleExpand: () -> Void

    // Always-visible preview slice
    private var previewCards: ArraySlice<MatchedCardInfo> {
        result.matchedCards.prefix(Layout.previewCount)
    }

    // Hidden-until-expanded slice (indices 3…n)
    private var extraCards: ArraySlice<MatchedCardInfo> {
        result.matchedCards.dropFirst(Layout.previewCount)
    }

    // Count shown on the "Show more" button
    private var hiddenCount: Int {
        extraCards.count + result.overflowCardCount
    }

    var body: some View {
        VStack(spacing: 10) {
            // ── Always-visible preview ────────────────────────────────────────
            ForEach(previewCards) { card in
                cardButton(card)
            }

            // ── Expand / collapse ─────────────────────────────────────────────
            if hiddenCount > 0 {
                if isExpanded {
                    expandedSection
                } else {
                    showMoreButton
                }
            }
        }
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Show More Button

    private var showMoreButton: some View {
        let accent = ThemeManager.shared.accentColor.color
        return Button(action: onToggleExpand) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Show \(hiddenCount) more card\(hiddenCount == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(0.5)
            }
                .foregroundStyle(accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(
                accent.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
                .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(accent.opacity(0.18), lineWidth: 1)
            )
        }
            .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Expanded Section

    private var expandedSection: some View {
        VStack(spacing: 0) {
            // ── LazyVStack for extra cards ────────────────────────────────────
            // Correct scope for lazy evaluation:
            //  • Lives inside the parent ScrollView → lazy context is available
            //  • The deck header above is already on screen → no height-jump
            //  • Each CardSnippetRow's HighlightedText.task(id:) fires only
            //    when the row scrolls into the viewport → no mass task spawning
            LazyVStack(spacing: 10) {
                ForEach(extraCards) { card in
                    cardButton(card)
                }

                // If the deck exceeded even the 200-card cap, acknowledge it.
                if result.overflowCardCount > 0 {
                    Text("+ \(result.overflowCardCount) more cards not shown (query too broad)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
            }
                .frame(maxWidth: .infinity)

            // ── Collapse button ───────────────────────────────────────────────
            Button(action: onToggleExpand) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Show less")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                    .foregroundStyle(.secondary)
            }
                .buttonStyle(ScaleButtonStyle())
                .padding(.top, 8)
        }
    }

    // MARK: - Card Button

    private func cardButton(_ card: MatchedCardInfo) -> some View {
        Button { onCardTap(card.id) } label: {
            CardSnippetRow(card: card, query: query)
        }
            .buttonStyle(ScaleButtonStyle())
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Card Snippet Row

private struct CardSnippetRow: View {
    let card: MatchedCardInfo
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Match side badge
            HStack {
                Text(card.matchSide.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(badgeColor.opacity(0.15))
                    .foregroundStyle(badgeColor)
                    .clipShape(Capsule())
                Spacer()
            }

            // Snippet with async highlights
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.quote")
                    .font(.subheadline)
                    .foregroundStyle(ThemeManager.shared.accentColor.color)
                    .padding(.top, 2)

                // HighlightedText runs string-search on a background thread.
                // Plain text is shown instantly; highlighted version swaps in
                // asynchronously without blocking the main thread.
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

    private var badgeColor: Color {
        switch card.matchSide {
        case .front: .blue
        case .back: .purple
        case .both: .orange
        case .content: .teal
        }
    }
}

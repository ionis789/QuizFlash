//
//  SearchResultsView.swift
//  QuizFlash
//
//  Integrated, deck-first search results for Library and Folder surfaces.
//

import SwiftUI
import SwiftData

// MARK: - SearchResultsView

/// Renders a flat, deck-first result list that stays visually aligned with the
/// minimalist Library rows instead of presenting a separate search surface.
struct SearchResultsView: View {
    @Environment(\.modelContext) private var context
    @Environment(NavigationManager.self) private var router

    let results: [DeckSearchResultItem]
    let query: String
    let isSearchLoading: Bool
    let onCardTap: (PersistentIdentifier) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if results.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(results) { result in
                        SearchDeckResultRow(
                            result: result,
                            query: query,
                            onDeckTap: { navigateToDeck(with: result.id) },
                            onCardTap: onCardTap
                        )
                    }
                }
            }
        }
        .padding(.top, UIConstants.Spacing.small)
        .padding(.bottom, 80)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isSearchLoading ? "Searching…" : "No matching decks or cards")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)

            Text(
                isSearchLoading
                    ? "Keeping the current list stable while the next result set is prepared."
                    : "Try a broader phrase, another deck title, or a different card keyword."
            )
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
        .padding(.top, UIConstants.Spacing.large)
    }

    private func navigateToDeck(with id: PersistentIdentifier) {
        guard let deck = context.safeModel(for: id, as: DeckModel.self) else { return }
        router.append(DeckNavigationValue(
            deckID: deck.persistentModelID,
            backLabel: "Search"
        ))
    }
}

// MARK: - SearchDeckResultRow

private struct SearchDeckResultRow: View {
    let result: DeckSearchResultItem
    let query: String
    let onDeckTap: () -> Void
    let onCardTap: (PersistentIdentifier) -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var visibleSnippets: ArraySlice<MatchedCardInfo> {
        result.matchedCards.prefix(2)
    }

    private var hiddenMatchCount: Int {
        max(0, result.totalMatchedCardsCount - visibleSnippets.count)
    }

    private var timeAgoString: String {
        Self.relativeFormatter.localizedString(for: result.editedAt, relativeTo: Date())
    }

    private var deckTint: Color {
        Color(hex: result.deckColorHex) ?? ThemeManager.shared.accentColor.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onDeckTap) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HighlightedText(
                            text: result.deckTitle,
                            query: query,
                            font: .system(size: 22, weight: .bold, design: .rounded),
                            baseColor: .primary
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                        HStack(spacing: 12) {
                            LibraryDeckMetaLabel(
                                systemImage: "rectangle.stack.fill",
                                text: "\(result.cardCount) card\(result.cardCount == 1 ? "" : "s")"
                            )
                            LibraryDeckMetaLabel(
                                systemImage: "clock",
                                text: timeAgoString
                            )
                            LibraryDeckMetaLabel(
                                systemImage: "sparkles",
                                text: "\(result.totalMatchedCardsCount) match\(result.totalMatchedCardsCount == 1 ? "" : "es")"
                            )
                            Spacer(minLength: 0)
                        }
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(visibleSnippets) { card in
                Button {
                    onCardTap(card.id)
                } label: {
                    SearchSnippetRow(card: card, query: query)
                }
                .buttonStyle(.plain)
            }

            if hiddenMatchCount > 0 {
                Text("+\(hiddenMatchCount) more match\(hiddenMatchCount == 1 ? "" : "es") in this deck")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 56)
            }
        }
        .padding(.horizontal, UIConstants.Layout.compactScreenEdgeInset + 4)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            LibraryRowSeparator(tint: deckTint)
                .padding(.top, 10)
        }
    }
}

// MARK: - SearchSnippetRow

private struct SearchSnippetRow: View {
    let card: MatchedCardInfo
    let query: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(card.matchSide.rawValue)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(badgeColor.opacity(0.14), in: Capsule())

            HighlightedText(
                text: card.snippet,
                query: query,
                font: .system(size: 15, weight: .medium, design: .rounded),
                baseColor: .secondary
            )
            .lineLimit(3)
            .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
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

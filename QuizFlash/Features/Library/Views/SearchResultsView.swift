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
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(NavigationManager.self) private var router

    @State private var displayedResults: [DeckSearchResultItem] = []
    @State private var displayedQuery = ""
    @State private var snapshotOpacity: Double = 1
    @State private var snapshotTransitionTask: Task<Void, Never>?

    let results: [DeckSearchResultItem]
    let query: String
    let isSearchLoading: Bool
    let expandedDeckIDs: Set<PersistentIdentifier>
    let onCardTap: (PersistentIdentifier) -> Void
    let onToggleDeckExpansion: (PersistentIdentifier) -> Void

    private var shouldShowEmptyState: Bool {
        displayedResults.isEmpty && !isSearchLoading
    }

    private var resultPresentationToken: String {
        let resultToken = results
            .map { "\($0.id)-\($0.totalMatchedCardsCount)" }
            .joined(separator: "|")
        return "\(query)::\(resultToken)"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !displayedResults.isEmpty {
                resultList
            }

            if shouldShowEmptyState {
                emptyState
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .opacity(snapshotOpacity)
        .padding(.top, UIConstants.Spacing.huge + UIConstants.Spacing.large)
        .padding(.bottom, 80)
        .onAppear {
            updateDisplayedSnapshot(animated: false)
        }
        .onChange(of: resultPresentationToken) { _, _ in
            updateDisplayedSnapshot(animated: true)
        }
        .onDisappear {
            snapshotTransitionTask?.cancel()
            snapshotTransitionTask = nil
        }
    }

    private var resultList: some View {
        LazyVStack(spacing: 0) {
            ForEach(displayedResults) { result in
                SearchDeckResultRow(
                    result: result,
                    query: displayedQuery,
                    isExpanded: expandedDeckIDs.contains(result.id),
                    onDeckTap: { navigateToDeck(with: result.id) },
                    onCardTap: onCardTap,
                    onToggleExpansion: { onToggleDeckExpansion(result.id) }
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 18) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 58, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .opacity(0.55)

            Text(localized("No matching decks or cards"))
                .font(.system(.title3).weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
        .padding(.top, UIConstants.Spacing.huge + UIConstants.Spacing.extraLarge)
    }

    private func navigateToDeck(with id: PersistentIdentifier) {
        guard let deck = context.safeModel(for: id, as: DeckModel.self) else { return }
        router.append(DeckNavigationValue(
            deckID: deck.persistentModelID,
            backLabel: AppLocalization.string("Search", locale: appPreferences.resolvedLocale)
        ))
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: appPreferences.resolvedLocale)
    }

    private func updateDisplayedSnapshot(animated: Bool) {
        snapshotTransitionTask?.cancel()

        guard animated, !displayedQuery.isEmpty || !displayedResults.isEmpty else {
            snapshotTransitionTask = nil
            setDisplayedSnapshot()
            snapshotOpacity = 1
            return
        }

        snapshotTransitionTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            setDisplayedSnapshot()
            snapshotOpacity = 0.92

            withAnimation(.easeOut(duration: 0.18)) {
                snapshotOpacity = 1
            }

            snapshotTransitionTask = nil
        }
    }

    private func setDisplayedSnapshot() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            displayedResults = results
            displayedQuery = query
        }
    }
}

// MARK: - SearchDeckResultRow

private struct SearchDeckResultRow: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let result: DeckSearchResultItem
    let query: String
    let isExpanded: Bool
    let onDeckTap: () -> Void
    let onCardTap: (PersistentIdentifier) -> Void
    let onToggleExpansion: () -> Void

    private let collapsedSnippetLimit = 5

    private var visibleSnippets: [MatchedCardInfo] {
        isExpanded ? result.matchedCards : Array(result.matchedCards.prefix(collapsedSnippetLimit))
    }

    private var hiddenMatchCount: Int {
        max(0, result.totalMatchedCardsCount - visibleSnippets.count)
    }

    private var hasExpandableMatches: Bool {
        result.totalMatchedCardsCount > collapsedSnippetLimit
    }

    private var timeAgoString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = appPreferences.resolvedLocale
        return formatter.localizedString(for: result.editedAt, relativeTo: Date())
    }

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    private var accentColor: Color {
        themeManager.accentColor.color
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private func localizedFormat(_ value: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = AppLocalization.string(value, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    private var localizedCardCount: String {
        AppLocalization.numbered(
            result.cardCount,
            singular: "%d card",
            plural: "%d cards",
            locale: locale
        )
    }

    private var localizedMoreMatchesCount: String {
        AppLocalization.numbered(
            hiddenMatchCount,
            singular: "%d more match",
            plural: "%d more matches",
            locale: locale
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onDeckTap) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HighlightedText(
                            text: result.deckTitle,
                            query: query,
                            font: .system(size: 22, weight: .bold),
                            baseColor: .primary
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                        HStack(spacing: 12) {
                            LibraryDeckMetaLabel(
                                systemImage: "rectangle.stack.fill",
                                text: localizedCardCount
                            )
                            LibraryDeckMetaLabel(
                                systemImage: "clock",
                                text: timeAgoString
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

            ForEach(Array(visibleSnippets.enumerated()), id: \.element.id) { index, card in
                Button {
                    onCardTap(card.id)
                } label: {
                    SearchSnippetRow(card: card, query: query)
                }
                .buttonStyle(.plain)

                if index < visibleSnippets.count - 1 {
                    AppSectionSeparator()
                        .opacity(0.45)
                        .padding(.vertical, 2)
                }
            }

            if hiddenMatchCount > 0 && !isExpanded {
                Button(action: onToggleExpansion) {
                    Text(localizedMoreMatchesCount)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accentColor)
                        .padding(.top, 2)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if isExpanded && hasExpandableMatches {
                Button(action: onToggleExpansion) {
                    Text(localized("Hide"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accentColor)
                        .padding(.top, 2)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, UIConstants.Layout.compactScreenEdgeInset + 4)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            AppSectionSeparator()
        }
    }
}

// MARK: - SearchSnippetRow

private struct SearchSnippetRow: View {
    let card: MatchedCardInfo
    let query: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HighlightedText(
                text: card.snippet,
                query: query,
                font: .system(size: 15, weight: .medium),
                baseColor: .secondary
            )
            .lineLimit(3)
            .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

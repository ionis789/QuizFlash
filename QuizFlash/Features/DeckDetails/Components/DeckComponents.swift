//
//  DeckComponents.swift
//  QuizFlash
//
//  Reusable deck-detail UI components. All views here are dumb — they receive
//  data via `let` / `var` properties and fire callbacks via closures.
//  No `@Query`, `@Environment(\.modelContext)`, or fetch logic appears here.
//

import SwiftUI
import UIKit

// MARK: - DeckHeaderView

/// Compact deck-identity header showing the deck title, card count,
/// creation date, and an inline edit button.
///
/// Used at the top of a deck row or sheet header — not in the main `DeckView`
/// scroll canvas (which uses the larger inline hero layout instead).
struct DeckHeaderView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Inputs

    /// The deck whose metadata is displayed.
    let deck: DeckModel
    /// Called when the user taps the edit (pencil) button.
    var onEdit: () -> Void

    // MARK: - Computed Properties

    /// The deck's brand colour, falling back to `.blue` when the hex string is invalid.
    private var deckColor: Color {
        Color(hex: deck.colorHex) ?? .blue
    }

    /// Deck creation date formatted as a medium-style string (e.g. "Feb 8, 2026").
    private var formattedCreationDate: String {
        let formatter = DateFormatter()
        formatter.locale = appPreferences.resolvedLocale
        formatter.calendar = appPreferences.resolvedCalendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: deck.createdAt)
    }

    private var locale: Locale { appPreferences.resolvedLocale }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private func localizedFormat(_ value: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = AppLocalization.string(value, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {

                // Title and subtitle
                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.title)
                        .font(.title.weight(.bold)).fontDesign(.rounded)
                        .foregroundStyle(themeManager.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Label(localizedFormat("%d cards", deck.cardCount), systemImage: "rectangle.stack")
                        Text("•")
                        Text(formattedCreationDate)
                    }
                        .font(.caption)
                        .foregroundStyle(themeManager.textSecondary)
                }

                Spacer()

                // Edit button
                Button(action: onEdit) {
                    Image(systemName: "pencil.line")
                        .font(
                            .system(
                            size: 11,
                            weight: .bold
                        )
                    )
                        .foregroundStyle(themeManager.roleColor(.buttonDangerForeground))
                }
                    .quizFlashButtonStyle(.surface, shape: .capsule, size: UIConstants.Size.heroInlineActionHeight)
            }
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
            .background(themeManager.screenBackground)
    }
}

// MARK: - DeckPlayModesView

/// Compact deck play-mode actions shown without horizontal scrolling.
struct DeckPlayModesView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Inputs

    /// The deck being played — used to disable tiles when it has no cards.
    let deck: DeckModel
    /// Lightweight compatibility counts derived from the deck snapshot.
    let availability: PlayModeCardAvailability
    /// Frozen recent-usage dates for the current deck-view session.
    let recentUsageSnapshot: [DeckPlayModeDestination: Date]
    /// Called when the user taps a play-mode card.
    let onOpenMode: (DeckPlayModeDestination) -> Void
    /// Called when the user taps the mode-specific options button.
    let onOpenSettings: (DeckPlayModeDestination) -> Void

    // MARK: - Computed Properties

    private var accentColor: Color { themeManager.roleColor(.buttonPrimaryFill) }
    private var deckColor: Color { Color(hex: deck.colorHex) ?? accentColor }
    private var orderedModes: [DeckPlayModeDestination] {
        let visibleModes = DeckPlayModeDestination.allCases
        let defaultOrder = Dictionary(
            uniqueKeysWithValues: visibleModes.enumerated().map { ($1, $0) }
        )

        return visibleModes.sorted { lhs, rhs in
            let lhsCanLaunch = lhs.canLaunch(with: availability, deck: deck)
            let rhsCanLaunch = rhs.canLaunch(with: availability, deck: deck)

            if lhsCanLaunch != rhsCanLaunch {
                return lhsCanLaunch && !rhsCanLaunch
            }

            let lhsRecentUsage = recentUsageSnapshot[lhs]
            let rhsRecentUsage = recentUsageSnapshot[rhs]

            switch (lhsRecentUsage, rhsRecentUsage) {
            case let (lhsDate?, rhsDate?):
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }

            return (defaultOrder[lhs] ?? 0) < (defaultOrder[rhs] ?? 0)
        }
    }
    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Text(AppLocalization.string("PLAY MODES", locale: appPreferences.resolvedLocale))
                .font(.caption.weight(.heavy))
                .foregroundStyle(themeManager.textSecondary.opacity(0.72))
                .padding(.horizontal, UIConstants.Layout.heroScreenEdgeInset)

            HStack(spacing: UIConstants.Spacing.small) {
                ForEach(orderedModes) { mode in
                    PlayModeCard(
                        mode: mode,
                        tintColor: mode.tintColor(
                            deckColor: deckColor,
                            accentColor: accentColor
                        ),
                        canPlay: mode.canLaunch(with: availability, deck: deck),
                        onOpenMode: onOpenMode,
                        onOpenSettings: onOpenSettings
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .padding(.vertical, UIConstants.Spacing.small)
        }
    }
}

// MARK: - PlayModeCard (private)

/// A single play-mode tile inside `DeckPlayModesView`.
private struct PlayModeCard: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Inputs

    let mode: DeckPlayModeDestination
    let tintColor: Color
    let canPlay: Bool
    let onOpenMode: (DeckPlayModeDestination) -> Void
    let onOpenSettings: (DeckPlayModeDestination) -> Void

    @State private var unavailableWiggleOffset: CGFloat = 0
    @State private var unavailableScale: CGFloat = 1
    @State private var unavailableFeedbackTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                if canPlay {
                    onOpenMode(mode)
                } else {
                    runUnavailableFeedbackSequence()
                }
            } label: {
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(tintColor.opacity(canPlay ? 0.18 : 0.12))
                            .frame(width: 44, height: 44)

                        Image(systemName: mode.systemImage)
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(canPlay ? tintColor : tintColor.opacity(0.72))
                    }

                    Text(mode.localizedTitle(locale: appPreferences.resolvedLocale))
                        .font(.system(size: 21, weight: .black, design: .rounded))
                        .foregroundStyle(themeManager.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .duoPressableSurfaceStyle()

            Button {
                onOpenSettings(mode)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tintColor)
                    .rotationEffect(.degrees(90))
                    .frame(width: 30, height: 30)
            }
            .padding(5)

        }
        .opacity(canPlay ? 1 : 0.56)
        .flashcardStyle(cornerRadius: 26, surfaceRole: .widget)
        .offset(x: unavailableWiggleOffset)
        .scaleEffect(unavailableScale, anchor: .center)
        .onDisappear {
            unavailableFeedbackTask?.cancel()
            unavailableFeedbackTask = nil
        }
    }

    private func runUnavailableFeedbackSequence() {
        unavailableFeedbackTask?.cancel()
        emitUnavailableFeedbackHaptic()
        unavailableScale = 1
        unavailableWiggleOffset = 0

        withAnimation(.linear(duration: 0.065).repeatCount(3, autoreverses: true)) {
            unavailableWiggleOffset = 8
        }

        unavailableFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) {
                unavailableWiggleOffset = 0
            }
            withAnimation(.smooth(duration: 0.22, extraBounce: 0)) {
                unavailableScale = 0.9
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.18, extraBounce: 0)) {
                unavailableScale = 1
            }
        }
    }

    private func emitUnavailableFeedbackHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }
}

// MARK: - DeckSectionToolbar

/// Pinned section-header toolbar that shows the card count label.
///
/// The label fades and slides away when the title pill (`DeckHeroView`) becomes visible,
/// preventing redundant text on screen.
struct DeckSectionToolbar: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Inputs

    /// The deck whose card count is displayed.
    let deck: DeckModel
    /// When `true`, the pill is visible — fade the label to avoid redundancy.
    var pillVisible: Bool = false

    // MARK: - Body

    var body: some View {
        HStack {
            Text(
                String(
                    format: AppLocalization.string("CARDS(%d)", locale: appPreferences.resolvedLocale),
                    locale: appPreferences.resolvedLocale,
                    deck.cardCount
                )
            )
                .font(.caption.weight(.bold))
                .foregroundStyle(themeManager.textSecondary)
                .opacity(pillVisible ? 0 : 1)
                .offset(x: pillVisible ? -8 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pillVisible)
            Spacer()
        }
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .padding(.vertical, 8)
    }
}

// MARK: - DeckActionOverlay

/// Floating action buttons rendered as a top-trailing overlay on `DeckContentView`.
///
/// Keeps the semantic add CTA on accent chrome while utility controls use the
/// softer filled-circle treatment shared by detail sheets and editor dismiss actions.
struct DeckActionOverlay: View {

    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Inputs

    /// The deck being acted upon (passed to contextual actions).
    let deck: DeckModel
    /// `true` when the view is in multi-card selection mode.
    let isSelecting: Bool
    /// Current deck sort order shown in the native overflow menu.
    @Binding var sortOrder: SortOrder
    /// Current deck grouping mode shown in the native overflow menu.
    @Binding var groupingMode: DeckCardGroupingMode
    /// Called when the user taps the "+" button.
    let onAdd: () -> Void
    /// Called when the user taps "Select Cards" in the menu.
    let onStartSelection: () -> Void
    /// Called when the user taps the top checkmark while selecting.
    let onDoneSelection: () -> Void
    /// Called when the user taps "Export Deck" in the menu.
    let onExport: () -> Void

    // MARK: - Computed Properties

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            addButton
            menuButton
        }
    }

    private var locale: Locale { appPreferences.resolvedLocale }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    // MARK: - Add Button

    private var addButton: some View {
        ChromeSoftCircleSymbolButton(
            systemName: "plus",
            accessibilityLabel: localized("Add card"),
            action: onAdd,
            tint: themeManager.roleColor(.buttonDangerForeground)
        )
    }

    // MARK: - Menu Button

    private var menuButton: some View {
        SelectionModeMenuButton(
            isSelecting: isSelecting,
            menuAccessibilityLabel: localized("More actions"),
            doneAccessibilityLabel: localized("Done selecting cards"),
            onDone: onDoneSelection
        ) { prepareSelectionVisual, finishMenuInteraction in
            UIMenu(children: [
                SelectionModeMenuElement.action(
                    title: localized("Select Cards"),
                    systemImage: "checkmark.circle",
                    isEnabled: !isSelecting
                ) {
                    prepareSelectionVisual()
                    onStartSelection()
                },
                SelectionModeMenuElement.action(
                    title: localized("Export Deck"),
                    systemImage: "square.and.arrow.up"
                ) {
                    finishMenuInteraction()
                    onExport()
                },
                SelectionModeMenuElement.action(
                    title: localized("Group by Card Type"),
                    systemImage: "square.grid.2x2",
                    state: groupingMode == .byCardType ? .on : .off
                ) {
                    finishMenuInteraction()
                    groupingMode = groupingMode == .byCardType ? .chronological : .byCardType
                },
                deckSortMenu(finishMenuInteraction: finishMenuInteraction)
            ])
        }
    }

    private func deckSortMenu(finishMenuInteraction: @escaping () -> Void) -> UIMenu {
        UIMenu(
            title: localized("Sort By"),
            image: UIImage(systemName: "arrow.up.arrow.down"),
            children: SortOrder.allCases.map { order in
                SelectionModeMenuElement.action(
                    title: order.localizedTitle(locale: locale),
                    systemImage: sortOrder == order ? "checkmark" : order.icon,
                    state: sortOrder == order ? .on : .off
                ) {
                    finishMenuInteraction()
                    sortOrder = order
                }
            }
        )
    }

}

// MARK: - DeckSelectionBottomBar

/// A floating bottom bar presented during multi-card selection mode.
///
/// Shows a "Done" button on the leading side and a destructive
/// "Delete(N)" button on the trailing side. Both actions are delegated
/// via closures — this view holds no state.
struct DeckSelectionBottomBar: View {
    @Environment(AppPreferences.self) private var appPreferences

    // MARK: - Inputs

    /// The number of currently selected cards, displayed in the delete button label.
    let selectedCount: Int
    let isSelectAllEnabled: Bool
    /// Called when the user selects every visible card.
    var onSelectAll: () -> Void
    /// Called when the user taps the delete button to confirm batch deletion.
    var onDelete: () -> Void

    private var locale: Locale { appPreferences.resolvedLocale }

    // MARK: - Body

    var body: some View {
        SelectionActionToolbar(
            selectedCount: selectedCount,
            actions: [
                .text(
                    id: "selectAll",
                    title: AppLocalization.string("Select All", locale: locale),
                    accessibilityLabel: AppLocalization.string("Select all cards", locale: locale),
                    isEnabled: isSelectAllEnabled,
                    action: onSelectAll
                ),
                .icon(
                    id: "delete",
                    systemName: "trash",
                    title: AppLocalization.string("Delete", locale: locale),
                    accessibilityLabel: deleteAccessibilityLabel,
                    isEnabled: selectedCount > 0,
                    tint: .destructive,
                    action: onDelete
                )
            ]
        )
    }

    private var deleteAccessibilityLabel: String {
        String(
            format: AppLocalization.string(
                selectedCount == 1 ? "Delete %d selected card" : "Delete %d selected cards",
                locale: locale
            ),
            locale: locale,
            selectedCount
        )
    }
}

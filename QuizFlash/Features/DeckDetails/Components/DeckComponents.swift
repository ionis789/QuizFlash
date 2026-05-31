//
//  DeckComponents.swift
//  QuizFlash
//
//  Reusable deck-detail UI components. All views here are dumb — they receive
//  data via `let` / `var` properties and fire callbacks via closures.
//  No `@Query`, `@Environment(\.modelContext)`, or fetch logic appears here.
//

import SwiftUI

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
                    .quizFlashButtonStyle(.accentAlt, shape: .capsule, size: UIConstants.Size.heroInlineActionHeight)
            }
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
            .background(themeManager.screenBackground)
    }
}

// MARK: - DeckPlayModesView

/// A horizontally scrolling carousel of deck play-mode cards.
///
/// The card width intentionally leaves part of the next card visible so the
/// section communicates that more modes are available with a horizontal swipe.
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
    /// Called when the user taps a mode tile that is currently unavailable.
    let onRequestUnavailableMode: (DeckPlayModeDestination) -> Void

    // MARK: - Computed Properties

    private var accentColor: Color { themeManager.roleColor(.buttonPrimaryFill) }
    private var deckColor: Color { Color(hex: deck.colorHex) ?? accentColor }
    private var orderedModes: [DeckPlayModeDestination] {
        let visibleModes = DeckPlayModeDestination.allCases.filter { $0 != .learn }
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

            GeometryReader { proxy in
                let availableWidth = max(0, proxy.size.width - (UIConstants.Layout.screenEdgeInset * 2))
                let widthScale = UIConstants.isPad ? 0.36 : 0.78
                let cardWidth = min(max(availableWidth * widthScale, 220), UIConstants.isPad ? 290 : 300)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: UIConstants.Spacing.standard) {
                        ForEach(orderedModes) { mode in
                            PlayModeCard(
                                mode: mode,
                                tintColor: mode.tintColor(
                                    deckColor: deckColor,
                                    accentColor: accentColor
                                ),
                                statusText: mode.localizedStatusText(
                                    locale: appPreferences.resolvedLocale,
                                    in: availability,
                                    deck: deck
                                ),
                                canPlay: mode.canLaunch(with: availability, deck: deck),
                                onOpenMode: onOpenMode,
                                onOpenSettings: onOpenSettings,
                                onRequestUnavailableMode: onRequestUnavailableMode
                            )
                                .frame(width: cardWidth)
                        }
                    }
                        .scrollTargetLayout()
                        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
                        .padding(.vertical, UIConstants.Spacing.small)
                }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            }
                .frame(height: 188)
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
    let statusText: String
    let canPlay: Bool
    let onOpenMode: (DeckPlayModeDestination) -> Void
    let onOpenSettings: (DeckPlayModeDestination) -> Void
    let onRequestUnavailableMode: (DeckPlayModeDestination) -> Void

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                Button {
                    if canPlay {
                        onOpenMode(mode)
                    } else {
                        onRequestUnavailableMode(mode)
                    }
                } label: {
                    HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(tintColor.opacity(canPlay ? 0.18 : 0.12))
                                .frame(width: 56, height: 56)

                            Image(systemName: mode.systemImage)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(canPlay ? tintColor : tintColor.opacity(0.72))
                        }

                        VStack(alignment: .leading, spacing: UIConstants.Spacing.tiny) {
                            Text(mode.localizedTitle(locale: appPreferences.resolvedLocale))
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundStyle(themeManager.textPrimary)
                                .lineLimit(1)

                            Text(mode.localizedSubtitle(locale: appPreferences.resolvedLocale))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(themeManager.textSecondary)
                                .lineLimit(2)

                            Text(statusText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(themeManager.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: UIConstants.Size.actionButton)
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                    .buttonStyle(.plain)
            }
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                .padding(14)

            Button {
                onOpenSettings(mode)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tintColor)
                    .frame(width: 34, height: 34)
            }
                .quizFlashButtonStyle(.surface, shape: .circle, size: 34)
                .padding(12)
        }
            .opacity(canPlay ? 1 : 0.56)
            .flashcardStyle(cornerRadius: 28, surfaceRole: .widget)
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

    @ViewBuilder
    private func actionChromeLabel(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button(action: onAdd) {
            actionChromeLabel(
                symbol: "plus",
                tint: themeManager.roleColor(.buttonDangerForeground)
            )
        }
            .quizFlashButtonStyle(.accentAlt, shape: .circle, size: UIConstants.Size.actionButton)
    }

    // MARK: - Menu Button

    private var menuButton: some View {
        Menu {
            Button {
                onStartSelection()
            } label: {
                Label(localized("Select Cards"), systemImage: "checkmark.circle")
            }
                .disabled(isSelecting)

            Button {
                onExport()
            } label: {
                Label(localized("Export Deck"), systemImage: "square.and.arrow.up")
            }

            Divider()

            Toggle(isOn: groupByTypeBinding) {
                Label(localized("Group by Card Type"), systemImage: "square.grid.2x2")
            }

            Divider()

            Picker(localized("Sort By"), selection: $sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Label(order.localizedTitle(locale: locale), systemImage: order.icon)
                        .tag(order)
                }
            }
        } label: {
            ChromeSoftCircleSymbol(
                systemName: "ellipsis",
                size: UIConstants.Size.actionButton,
                symbolSize: UIConstants.Size.iconStandard
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("More actions"))
    }

    private var groupByTypeBinding: Binding<Bool> {
        Binding(
            get: { groupingMode == .byCardType },
            set: { newValue in
                groupingMode = newValue ? .byCardType : .chronological
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
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Inputs

    /// The number of currently selected cards, displayed in the delete button label.
    let selectedCount: Int
    /// Called when the user taps "Done" to exit selection mode.
    var onDone: () -> Void
    /// Called when the user clears the current selection without leaving selection mode.
    var onClearSelection: () -> Void
    /// Called when the user taps the delete button to confirm batch deletion.
    var onDelete: () -> Void

    private var selectionSummary: String {
        if selectedCount == 0 {
            return AppLocalization.string("Tap cards", locale: appPreferences.resolvedLocale)
        }
        let format = AppLocalization.string("%d selected", locale: appPreferences.resolvedLocale)
        return String(format: format, locale: appPreferences.resolvedLocale, selectedCount)
    }

    private var summaryTint: Color {
        selectedCount == 0 ? themeManager.textSecondary : themeManager.textPrimary
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            SelectionToolbarCapsuleButton(
                action: onDone,
                accessibilityLabel: AppLocalization.string("Done selecting cards", locale: appPreferences.resolvedLocale)
            ) {
                Text(AppLocalization.string("Done", locale: appPreferences.resolvedLocale))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.textPrimary)
            }
                .layoutPriority(1)

            Text(selectionSummary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(summaryTint)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .monospacedDigit()
                .frame(width: 118, alignment: .leading)

            if selectedCount > 0 {
                SelectionToolbarTextButton(
                    title: AppLocalization.string("Clear", locale: appPreferences.resolvedLocale),
                    accessibilityLabel: AppLocalization.string("Clear selected cards", locale: appPreferences.resolvedLocale)
                ) {
                    onClearSelection()
                }
            }

            Spacer(minLength: 0)

            SelectionToolbarIconButton(
                isEnabled: selectedCount > 0,
                accessibilityLabel: String(
                    format: AppLocalization.string(
                        selectedCount == 1 ? "Delete %d selected card" : "Delete %d selected cards",
                        locale: appPreferences.resolvedLocale
                    ),
                    locale: appPreferences.resolvedLocale,
                    selectedCount
                ),
                action: onDelete
            ) {
                Image(systemName: "trash")
                    .font(.system(size: UIConstants.Size.selectionToolbarIcon, weight: .semibold))
                    .foregroundStyle(selectedCount > 0 ? themeManager.dangerPrimary : themeManager.textSecondary)
            }
        }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }
}

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

/// Compact deck-identity header showing the colour-coded icon, title, card count,
/// creation date, and an inline edit button.
///
/// Used at the top of a deck row or sheet header — not in the main `DeckView`
/// scroll canvas (which uses the larger inline hero layout instead).
struct DeckHeaderView: View {

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

    /// The app's current accent colour from `ThemeManager`.
    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    /// Deck creation date formatted as a medium-style string (e.g. "Feb 8, 2026").
    private var formattedCreationDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: deck.createdAt)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {

                // Deck colour icon badge
                ZStack {
                    Circle()
                        .fill(
                        LinearGradient(
                            colors: [deckColor.opacity(0.7), deckColor.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                        .frame(width: 56, height: 56)

                    Image(systemName: deck.icon.isEmpty ? "sparkles.rectangle.stack.fill" : deck.icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }

                // Title and subtitle
                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.title)
                        .font(.title.weight(.bold)).fontDesign(.rounded)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Label("\(deck.cardCount)", systemImage: "rectangle.stack")
                        Text("•")
                        Text(formattedCreationDate)
                    }
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                    .frame(
                        height: UIConstants.Size.heroInlineActionHeight
                    )
                    .padding(.horizontal, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
                    }
                }
                    .buttonStyle(.plain)
            }
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
            .background(Color(uiColor: .systemGroupedBackground))
    }
}

// MARK: - DeckPlayModesView

/// A horizontally scrolling carousel of deck play-mode cards.
///
/// The card width intentionally leaves part of the next card visible so the
/// section communicates that more modes are available with a horizontal swipe.
struct DeckPlayModesView: View {

    // MARK: - Inputs

    /// The deck being played — used to disable tiles when it has no cards.
    let deck: DeckModel
    /// Lightweight compatibility counts derived from the deck snapshot.
    let availability: PlayModeCardAvailability
    /// Called when the user taps a play-mode card.
    let onOpenMode: (DeckPlayModeDestination) -> Void
    /// Called when the user taps the mode-specific options button.
    let onOpenSettings: (DeckPlayModeDestination) -> Void
    /// Called when the user opens a recommended conversion from a play-mode card.
    let onOpenRecommendedConversion: (DeckPlayModeDestination) -> Void

    // MARK: - Computed Properties

    private var accentColor: Color { ThemeManager.shared.accentColor.color }
    private var deckColor: Color { Color(hex: deck.colorHex) ?? accentColor }
    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Text("PLAY MODES")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, UIConstants.Layout.heroScreenEdgeInset)

            GeometryReader { proxy in
                let availableWidth = max(0, proxy.size.width - (UIConstants.Layout.screenEdgeInset * 2))
                let widthScale = UIConstants.isPad ? 0.36 : 0.78
                let cardWidth = min(max(availableWidth * widthScale, 220), UIConstants.isPad ? 290 : 300)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: UIConstants.Spacing.standard) {
                        ForEach(DeckPlayModeDestination.allCases) { mode in
                            PlayModeCard(
                                mode: mode,
                                tintColor: mode.tintColor(
                                    deckColor: deckColor,
                                    accentColor: accentColor
                                ),
                                fallbackPrompt: mode.fallbackPrompt(in: availability),
                                compatibleCardCount: mode.compatibleCardCount(in: availability),
                                canPlay: mode.canLaunch(with: availability),
                                onOpenMode: onOpenMode,
                                onOpenSettings: onOpenSettings,
                                onOpenRecommendedConversion: onOpenRecommendedConversion
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

            if availability.totalCards == 0 {
                Text("Add cards to start a session. Settings stay available for every mode.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            } else {
                Text("Each mode only activates when this deck has compatible cards for that mode.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            }
        }
    }
}

// MARK: - DeckReadinessDiagnosticsView

/// Compact deck-level readiness summary for Match and Write authoring quality.
struct DeckReadinessDiagnosticsView: View {
    let summary: DeckReadinessSummary
    var onOpenRecommendedConversion: ((CardKind) -> Void)? = nil

    var body: some View {
        guard summary.hasContent else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                Text("READINESS")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.tertiary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: UIConstants.Spacing.small) {
                        ForEach(summary.items) { item in
                            readinessChip(for: item)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)

                Text("Match-ready and match-weak count both dedicated match cards and compact flashcard fallback pairs.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let onOpenRecommendedConversion,
                   !summary.recommendedConversions.isEmpty {
                    recommendedConversionButtons(onOpenRecommendedConversion)
                }
            }
            .padding(.horizontal, UIConstants.Layout.heroScreenEdgeInset)
        )
    }

    private func readinessChip(for item: DeckReadinessSummaryItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.kind.symbol)
            Text(item.title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(item.kind.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(item.kind.tint.opacity(0.12), in: Capsule())
    }

    private func recommendedConversionButtons(
        _ onOpenRecommendedConversion: @escaping (CardKind) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Text("Recommended conversions")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            ForEach(summary.recommendedConversions) { recommendation in
                Button {
                    onOpenRecommendedConversion(recommendation.targetKind)
                } label: {
                    HStack(spacing: UIConstants.Spacing.small) {
                        Image(systemName: recommendation.targetKind.conversionSystemImage)
                            .font(.caption.weight(.bold))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(recommendation.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)

                            Text(recommendation.detail)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: UIConstants.Spacing.small)

                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(recommendation.targetKind == .match ? .orange : accent)
                    }
                    .padding(.horizontal, UIConstants.Spacing.standard)
                    .padding(.vertical, UIConstants.Spacing.standard)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }
}

// MARK: - PlayModeCard (private)

/// A single play-mode tile inside `DeckPlayModesView`.
private struct PlayModeCard: View {

    // MARK: - Inputs

    let mode: DeckPlayModeDestination
    let tintColor: Color
    let fallbackPrompt: PlayModeFallbackPrompt?
    let compatibleCardCount: Int
    let canPlay: Bool
    let onOpenMode: (DeckPlayModeDestination) -> Void
    let onOpenSettings: (DeckPlayModeDestination) -> Void
    let onOpenRecommendedConversion: (DeckPlayModeDestination) -> Void

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                Button {
                    guard canPlay else { return }
                    onOpenMode(mode)
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
                            Text(mode.title)
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(mode.subtitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            if compatibleCardCount > 0 {
                                Text("\(compatibleCardCount) \(mode.compatibilityRequirementLabel) ready")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else if mode.isGameplayImplemented {
                                Text("No \(mode.compatibilityRequirementLabel) in this deck")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text("No \(mode.compatibilityRequirementLabel) yet")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: UIConstants.Size.actionButton)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .buttonStyle(.plain)

                if let fallbackPrompt {
                    fallbackPromptView(fallbackPrompt)
                }
            }
            .frame(maxWidth: .infinity, minHeight: fallbackPrompt == nil ? 96 : 132, alignment: .leading)
            .padding(14)

            Button {
                onOpenSettings(mode)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tintColor)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(tintColor.opacity(0.12))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
                    }
            }
                .buttonStyle(.plain)
                .padding(12)
        }
            .widgetStyle(cornerRadius: 28)
            .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
        }
    }

    private func fallbackPromptView(_ prompt: PlayModeFallbackPrompt) -> some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.title.uppercased())
                    .font(.caption.weight(.black))
                    .foregroundStyle(tintColor)
                    .lineLimit(1)

                Text(prompt.detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: UIConstants.Spacing.small)

            Button {
                onOpenRecommendedConversion(mode)
            } label: {
                Text(prompt.ctaTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tintColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(tintColor.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, UIConstants.Spacing.small)
        .padding(.vertical, UIConstants.Spacing.small)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }
}

// MARK: - DeckSectionToolbar

/// Pinned section-header toolbar that shows the card count label.
///
/// The label fades and slides away when the title pill (`DeckHeroView`) becomes visible,
/// preventing redundant text on screen.
struct DeckSectionToolbar: View {

    // MARK: - Inputs

    /// The deck whose card count is displayed.
    let deck: DeckModel
    /// When `true`, the pill is visible — fade the label to avoid redundancy.
    var pillVisible: Bool = false

    // MARK: - Body

    var body: some View {
        HStack {
            Text("CARDS(\(deck.cardCount))")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
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
/// Mirrors the visual style of the back-button overlay (top-leading):
/// each button is a standalone capsule with `ultraThinMaterial` fill and an
/// accent-tinted overlay, matching the exact padding and height of the back button.
struct DeckActionOverlay: View {

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
    /// Called when the user opens the conversion flow from the deck menu.
    let onConvert: () -> Void
    /// Called when the user taps "Export Deck" in the menu.
    let onExport: () -> Void

    // MARK: - Computed Properties

    private var accent: Color { ThemeManager.shared.accentColor.color }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            addButton
            menuButton
        }
    }

    @ViewBuilder
    private func actionChromeLabel(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
            .glassButton(shape: .circle)
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.75)
            }
            .clipShape(Circle())
            .compositingGroup()
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button(action: onAdd) {
            actionChromeLabel(symbol: "plus", tint: accent)
        }
            .buttonStyle(.plain)
    }

    // MARK: - Menu Button

    private var menuButton: some View {
        Menu {
            Button {
                onStartSelection()
            } label: {
                Label("Select Cards", systemImage: "checkmark.circle")
            }
            .disabled(isSelecting)

            Button {
                onConvert()
            } label: {
                Label("Convert Cards", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(deck.cardCount == 0)

            Button {
                onExport()
            } label: {
                Label("Export Deck", systemImage: "square.and.arrow.up")
            }

            Divider()

            Toggle(isOn: groupByTypeBinding) {
                Label("Group by Card Type", systemImage: "square.grid.2x2")
            }

            Divider()

            Picker("Sort By", selection: $sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Label(order.rawValue, systemImage: order.icon)
                        .tag(order)
                }
            }
        } label: {
            actionChromeLabel(symbol: "ellipsis", tint: isSelecting ? .white : accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More actions")
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

    // MARK: - Inputs

    /// The number of currently selected cards, displayed in the delete button label.
    let selectedCount: Int
    /// Called when the user taps "Done" to exit selection mode.
    var onDone: () -> Void
    /// Called when the user clears the current selection without leaving selection mode.
    var onClearSelection: () -> Void
    /// Called when the user opens the conversion flow for the current selection.
    var onConvert: () -> Void
    /// Called when the user taps the delete button to confirm batch deletion.
    var onDelete: () -> Void

    private var selectionSummary: String {
        if selectedCount == 0 {
            return "Tap cards"
        }
        return selectedCount == 1 ? "1 selected" : "\(selectedCount) selected"
    }

    private var summaryTint: Color {
        selectedCount == 0 ? .secondary : .primary
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            SelectionToolbarCapsuleButton(
                action: onDone,
                accessibilityLabel: "Done selecting cards"
            ) {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
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
                    title: "Convert",
                    accessibilityLabel: "Convert selected cards",
                    tint: ThemeManager.shared.accentColor.color
                ) {
                    onConvert()
                }

                SelectionToolbarTextButton(
                    title: "Clear",
                    accessibilityLabel: "Clear selected cards"
                ) {
                    onClearSelection()
                }
            }

            Spacer(minLength: 0)

            SelectionToolbarIconButton(
                isEnabled: selectedCount > 0,
                accessibilityLabel: "Delete \(selectedCount) selected card\(selectedCount == 1 ? "" : "s")",
                action: onDelete
            ) {
                Image(systemName: "trash")
                    .font(.system(size: UIConstants.Size.selectionToolbarIcon, weight: .semibold))
                    .foregroundStyle(selectedCount > 0 ? Color.red : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

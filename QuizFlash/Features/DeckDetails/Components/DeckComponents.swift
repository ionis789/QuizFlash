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
    /// Called when the user taps a play-mode card.
    let onOpenMode: (DeckPlayModeDestination) -> Void
    /// Called when the user taps the mode-specific options button.
    let onOpenSettings: (DeckPlayModeDestination) -> Void

    // MARK: - Computed Properties

    private var accentColor: Color { ThemeManager.shared.accentColor.color }
    private var deckColor: Color { Color(hex: deck.colorHex) ?? accentColor }
    /// `true` when the deck has at least one card and flashcards can launch immediately.
    private var hasCards: Bool { deck.cardCount > 0 }

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
                                canPlay: hasCards && mode.isGameplayAvailable,
                                hasCards: hasCards,
                                onOpenMode: onOpenMode,
                                onOpenSettings: onOpenSettings
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
                .frame(height: 148)

            if !hasCards {
                Text("Add cards to start a session. Settings stay available for every mode.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            }
        }
    }
}

// MARK: - PlayModeCard (private)

/// A single play-mode tile inside `DeckPlayModesView`.
private struct PlayModeCard: View {

    // MARK: - Inputs

    let mode: DeckPlayModeDestination
    let tintColor: Color
    let canPlay: Bool
    let hasCards: Bool
    let onOpenMode: (DeckPlayModeDestination) -> Void
    let onOpenSettings: (DeckPlayModeDestination) -> Void

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                guard canPlay else { return }
                onOpenMode(mode)
            } label: {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
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

                            if !mode.isGameplayAvailable {
                                Text("Gameplay coming soon")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else if !hasCards {
                                Text("Add cards to start")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: UIConstants.Size.actionButton)
                    }
                }
                    .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96, alignment: .leading)
                    .padding(14)
                    .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
                .buttonStyle(.plain)

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
///
/// The ellipsis button tracks its own frame via `onGeometryChange` so that
/// `DeckContentView` can position the `DeckMenuControls` dropdown correctly
/// relative to the button regardless of device size or orientation.
struct DeckActionOverlay: View {

    // MARK: - Inputs

    /// The deck being acted upon (passed to contextual actions).
    let deck: DeckModel
    /// `true` when the view is in multi-card selection mode.
    let isSelecting: Bool
    /// Controls the expanded/collapsed state of the context menu.
    @Binding var isMenuExpanded: Bool
    /// The global-coordinate frame of the ellipsis button; used to anchor the dropdown.
    @Binding var menuPosition: CGRect
    /// Provides the live frame of the ellipsis button before the binding is written.
    let menuTracker: MenuPositionTracker
    /// Called when the user taps the "+" button.
    let onAdd: () -> Void
    /// Called when the user taps "Select Cards" in the menu.
    let onStartSelection: () -> Void
    /// Called when the user taps "Export Deck" in the menu.
    let onExport: () -> Void

    // MARK: - Computed Properties

    private var accent: Color { ThemeManager.shared.accentColor.color }
    /// `true` when the ellipsis button should render in its active (filled) state.
    private var isMenuActive: Bool { isSelecting || isMenuExpanded }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            addButton
            menuButton
                .scaleEffect(isMenuActive ? 1.1 : 1.0)
        }
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
                .glassButton(shape: .circle)
        }
            .buttonStyle(.plain)
    }

    // MARK: - Menu Button

    /// Ellipsis button that opens the `DeckMenuControls` dropdown.
    ///
    /// `onGeometryChange` feeds `menuPosition` so the dropdown can be anchored
    /// to this button's frame without hard-coded offsets.
    private var menuButton: some View {
        Button {
            menuPosition = menuTracker.rect
            withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
                isMenuExpanded.toggle()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
            // Active: white icon on solid-accent fill.
            // Inactive: accent icon on tinted-material fill.
            .foregroundStyle(isMenuActive ? .white : accent)
                .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
                .glassButton(shape: .circle)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isMenuActive)
        }
            .buttonStyle(.plain)
            .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { newValue in
            menuTracker.rect = newValue
        }
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
    /// Called when the user taps the delete button to confirm batch deletion.
    var onDelete: () -> Void

    // MARK: - Body

    var body: some View {
        HStack(spacing: UIConstants.Spacing.medium) {

            // Done button
            Button(action: onDone) {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(height: UIConstants.Size.selectionToolbarControl)
                    .glassButton(shape: .capsule)
            }
                .buttonStyle(.plain)

            Spacer()

            // Delete button — disabled and dimmed when nothing is selected
            SelectionToolbarIconButton(
                isEnabled: selectedCount > 0,
                accessibilityLabel: "Delete \(selectedCount) selected card\(selectedCount == 1 ? "" : "s")",
                badgeCount: selectedCount,
                action: onDelete
            ) {
                Image(systemName: "trash")
                    .font(.system(size: UIConstants.Size.selectionToolbarIcon, weight: .semibold))
                    .foregroundStyle(selectedCount > 0 ? Color.red : Color.secondary)
            }
        }
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
    }
}

// MARK: - DeckCardContextMenu

/// Anchored floating menu for card-level actions such as edit, pin, and delete.
struct DeckCardContextMenu: View {
    let card: GridCardInfo
    let onEdit: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.tiny + 2) {
                HStack(spacing: UIConstants.Spacing.small) {
                    Circle()
                        .fill(card.deckStatusColor)
                        .frame(width: 8, height: 8)

                    Text(card.deckCardLabel)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer(minLength: UIConstants.Spacing.small)
                }

                Text(card.cardMenuSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider()
                .background(Color.primary.opacity(0.08))

            VStack(spacing: UIConstants.Spacing.small) {
                DeckCardContextMenuActionRow(
                    title: "Edit Card",
                    icon: "pencil",
                    tint: .primary,
                    iconBackground: Color.primary.opacity(0.07),
                    accessibilityLabel: "Edit Card"
                ) {
                    onEdit()
                }

                DeckCardContextMenuActionRow(
                    title: card.isPinned ? "Unpin Card" : "Pin Card",
                    icon: card.isPinned ? "pin.slash.fill" : "pin.fill",
                    tint: card.isPinned ? .orange : card.deckStatusColor,
                    iconBackground: (card.isPinned ? Color.orange : card.deckStatusColor).opacity(card.isPinned ? 0.20 : 0.14),
                    accessibilityLabel: card.isPinned ? "Unpin Card" : "Pin Card"
                ) {
                    onTogglePin()
                }

                DeckCardContextMenuActionRow(
                    title: "Delete Card",
                    icon: "trash",
                    tint: .red,
                    iconBackground: Color.red.opacity(0.16),
                    isDestructive: true,
                    accessibilityLabel: "Delete Card"
                ) {
                    onDelete()
                }
            }
        }
        .padding(UIConstants.Spacing.medium)
        .frame(width: UIConstants.Size.floatingContextMenuWidth, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    Color.libraryDeckRow
                        .shadow(.inner(color: Color.white.opacity(0.12), radius: 1, x: 0, y: 0))
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.85)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
    }
}

private struct DeckCardContextMenuActionRow: View {
    let title: String
    let icon: String
    let tint: Color
    let iconBackground: Color
    var isDestructive: Bool = false
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: UIConstants.Spacing.medium) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(iconBackground)

                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 36, height: 36)

                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(titleColor)

                Spacer(minLength: UIConstants.Spacing.small)
            }
            .padding(.horizontal, UIConstants.Spacing.medium - 2)
            .padding(.vertical, UIConstants.Spacing.small + 2)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var titleColor: Color {
        isDestructive ? .red : .primary
    }
}

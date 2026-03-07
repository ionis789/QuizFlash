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
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

// MARK: - DeckPlayModesView

/// A 2×2 grid of play-mode cards (Default, Quiz, Learn, Match).
///
/// Each card fires `onPlay` when tapped. The "Match" tile is always disabled
/// (coming soon). All styling is driven by `ThemeManager.shared`.
struct DeckPlayModesView: View {

    // MARK: - Inputs

    /// The deck being played — used to disable tiles when it has no cards.
    let deck: DeckModel
    /// Called when the user taps any active play-mode card.
    var onPlay: () -> Void

    // MARK: - Computed Properties

    private var accentColor: Color { ThemeManager.shared.accentColor.color }
    /// `true` when the deck has no cards; disables all play tiles.
    private var isEmpty: Bool { deck.cardCount == 0 }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PLAY MODES")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, UIConstants.Layout.heroScreenEdgeInset)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                spacing: 16
            ) {
                PlayModeCard(
                    title: "Default",
                    subtitle: "Swipe review",
                    systemImage: "play.fill",
                    color: accentColor,
                    isAvailable: !isEmpty,
                    action: onPlay
                )
                PlayModeCard(
                    title: "Quiz",
                    subtitle: "Multi choice",
                    systemImage: "questionmark.square.dashed",
                    color: .purple,
                    isAvailable: !isEmpty,
                    action: onPlay
                )
                PlayModeCard(
                    title: "Learn",
                    subtitle: "Spaced rep",
                    systemImage: "brain.head.profile",
                    color: .teal,
                    isAvailable: !isEmpty,
                    action: onPlay
                )
                PlayModeCard(
                    title: "Match",
                    subtitle: "Coming soon",
                    systemImage: "square.grid.2x2",
                    color: .gray,
                    isAvailable: false,
                    action: { }
                )
            }
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
        }
    }
}

// MARK: - PlayModeCard (private)

/// A single play-mode tile inside `DeckPlayModesView`.
private struct PlayModeCard: View {

    // MARK: - Inputs

    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    let isAvailable: Bool
    let action: () -> Void

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {

                // Icon badge
                ZStack {
                    Circle()
                        .fill(color.opacity(isAvailable ? 0.15 : 0.05))
                        .frame(width: 44, height: 44)

                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isAvailable ? color : color.opacity(0.30))
                }

                // Labels
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(isAvailable ? .primary : .tertiary)

                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(
                        Color.libraryDeckRow
                            .shadow(.inner(color: Color.white.opacity(0.15), radius: 1, x: 0, y: 0))
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1.0 : 0.5)
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
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(width: 50, height: 50)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .fill(Color.white.opacity(0.35))
                                .blur(radius: 10)
                                .mask(Circle().stroke(lineWidth: 4))
                                .blendMode(.overlay)
                        }
                }
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
                .font(.system(size: 20, weight: .bold))
                // Active: white icon on solid-accent fill.
                // Inactive: accent icon on tinted-material fill.
                .foregroundStyle(isMenuActive ? .white : accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(width: 50, height: 50)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .fill(Color.white.opacity(0.35))
                                .blur(radius: 10)
                                .mask(Circle().stroke(lineWidth: 4))
                                .blendMode(.overlay)
                        }
                }
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
        HStack(spacing: 12) {

            // Done button
            Button(action: onDone) {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            Spacer()

            // Delete button — disabled and dimmed when nothing is selected
            Button(role: .destructive, action: onDelete) {
                Text("Delete(\(selectedCount))")
                    .fontWeight(.semibold)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .disabled(selectedCount == 0)
            .opacity(selectedCount == 0 ? 0.5 : 1)
        }
        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
    }
}

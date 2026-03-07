//
//  LibraryContentViews.swift
//  QuizFlash
//
//  Contains: LibraryListView, LibraryDeckListRow,
//            LibrarySectionHeader, LibraryEmptyStateView,
//            LibrarySelectionIndicator, LibraryLoadingOverlay
//
//  Performance architecture:
//  ─────────────────────────────────────────────────────────────────────────────
//  • LibraryDeckListRow accepts only PRIMITIVES and CLOSURES — zero @Observable
//    property reads. This eliminates per-row observation registrations that leak
//    on iOS 17 during tab switches.
//  • The LazyVStack is FLAT — every row is an independent lazy item. The previous
//    nested VStack inside Section forced all rows in a section to materialize
//    simultaneously, blocking the main thread.
//  • No per-row @State animation. The jelly bounce is applied at the list level
//    in LibraryLayout for a single, lightweight animation.
//
//  Scroll-proximity effect:
//  ─────────────────────────────────────────────────────────────────────────────
//  Each row reads its own minY from the "libraryScroll" coordinate space
//  via .visualEffect. The effect fires ONLY when minY < kAbsoluteTopZone —
//  i.e. only in the final pixels before the row exits at the absolute screen top.
//  The row travels completely invisibly behind the floating header until that point.

import SwiftUI
import SwiftData

// MARK: - Scroll-Proximity Effect Constants

/// Height of the dissolve zone measured from absolute y = 0 (top of screen).
/// The effect is completely INACTIVE for any row with minY ≥ this value.
/// Rows behind the floating header (pills/title) have large positive minY —
/// they are never affected during that journey. Only the final pixels before
/// the row exits at the top of the screen trigger the dissolve.
/// Tune range: 20–80 pt.


// MARK: - Coordinate Space Name

/// Named by LibraryLayout on its ScrollView; read here by .visualEffect.
/// Origin y = 0 is the absolute top of the screen (ScrollView uses
/// .ignoresSafeArea(.container, edges: .top) so it starts behind the status bar).
let kLibraryScrollSpace = "libraryScroll"

// MARK: - List View

/// The main list view displaying grouped decks.
/// Relies purely on primitives to ensure performance.
struct LibraryListView: View {
    let groupedDecks: [DeckSection]
    let isSelecting: Bool
    let selectedDeckIDs: Set<PersistentIdentifier>
    let activeActionMenuDeckID: PersistentIdentifier?
    let onNavigate: (DeckModel) -> Void
    let onToggleSelection: (DeckModel) -> Void
    let onToggleActionMenu: (PersistentIdentifier?) -> Void
    let onEditColor: (DeckModel) -> Void
    let onDelete: (DeckModel) -> Void

    var body: some View {
        Group {
            ForEach(groupedDecks) { section in
                LibrarySectionHeader(title: section.title)
                    .scrollProximityEffect()
                    .id("header-\(section.id)")

                ForEach(section.decks) { deck in
                    LibraryDeckListRow(
                        deck: deck,
                        isSelecting: isSelecting,
                        isSelected: selectedDeckIDs.contains(deck.id),
                        showActionMenu: activeActionMenuDeckID == deck.id,
                        onNavigate: { onNavigate(deck) },
                        onToggleSelection: { onToggleSelection(deck) },
                        onToggleActionMenu: { show in onToggleActionMenu(show ? deck.id : nil) },
                        onEditColor: { onEditColor(deck) },
                        onDelete: { onDelete(deck) }
                    )
                        .padding(.horizontal, UIConstants.Layout.compactScreenEdgeInset)
                        .padding(.vertical, 5)
                        .scrollProximityEffect()
                        .id(deck.id)
                }
            }
        }
    }
}

// MARK: - Deck List Row
//
// ZERO @Observable reads — accepts only primitives and closures.
// SwiftUI re-evaluates this view ONLY when the parent passes new values.
// No observation registrations → no iOS 17 observation leak.

/// A single row representing a deck in the library.
/// Uses primitive values and closures to maintain high scroll performance without observing state.
struct LibraryDeckListRow: View {
    let deck: DeckModel
    let isSelecting: Bool
    let isSelected: Bool
    let showActionMenu: Bool
    let onNavigate: () -> Void
    let onToggleSelection: () -> Void
    let onToggleActionMenu: (Bool) -> Void
    let onEditColor: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isSelecting {
                LibrarySelectionIndicator(isSelected: isSelected) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        onToggleSelection()
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Button {
                if isSelecting {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        onToggleSelection()
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        onNavigate()
                    }
                }
            } label: {
                DeckRowView(deck: deck)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.vertical, 6)
            // ── Long-Press Action Menu ──────────────────────────────────────
            // .contextMenu is intentionally absent.
            //
            // On iOS 17, SwiftUI's .contextMenu always uses UIContextMenuInteraction
            // internally, which injects _UIReparentingView into UIHostingController.view
            // regardless of whether a custom preview: block is present. This corrupts
            // the scroll view's UIKit hierarchy and is explicitly unsupported by UIKit.
            // Replaced with a pure-SwiftUI long-press + overlay menu.
            .onLongPressGesture(minimumDuration: 0.4) {
                guard !isSelecting else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    onToggleActionMenu(true)
                }
            }
        }
        .scaleEffect(isSelecting && isSelected ? 0.9 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelecting)
        // The overlay menu is anchored to the row itself so it always positions
        // correctly relative to the card, even when the list is scrolled.
        .overlay(alignment: .bottom) {
            if showActionMenu {
                DeckActionMenu(
                    onEditColor: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            onToggleActionMenu(false)
                        }
                        // Slight delay lets the dismiss animation complete before
                        // presenting the color picker sheet.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            onEditColor()
                        }
                    },
                    onDelete: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            onToggleActionMenu(false)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            onDelete()
                        }
                    },
                    onDismiss: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            onToggleActionMenu(false)
                        }
                    }
                )
                .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
        // Tap outside the menu to dismiss it.
        .background {
            if showActionMenu {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            onToggleActionMenu(false)
                        }
                    }
                    .ignoresSafeArea()
                    .zIndex(99)
            }
        }
    }
}

// MARK: - Deck Action Menu
//
// Pure SwiftUI replacement for UIContextMenuInteraction.
// Renders as a floating pill anchored below the long-pressed row.
// No UIKit interaction machinery — zero risk of _UIReparentingView injection.

private struct DeckActionMenu: View {
    let onEditColor: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onEditColor) {
                Label("Change Color", systemImage: "paintpalette")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
            }

            Divider()
                .padding(.horizontal, 12)

            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .frame(width: 220)
        .offset(y: 8)
        .allowsHitTesting(true)
    }
}

// MARK: - Section Header

/// Header for grouped library sections.
struct LibrarySectionHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 0.5)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 0.5)
        }
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .padding(.vertical, 14)
    }
}

// MARK: - Empty State

/// View shown when there are no decks available in the library yet.
struct LibraryEmptyStateView: View {
    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(accent.opacity(0.8))
            }

            VStack(spacing: 8) {
                Text("No Decks Yet")
                    .font(.title3.weight(.semibold))
                Text("Tap Create to make your first deck\nand start learning.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 90)
            .padding(.horizontal, 40)
    }
}

// MARK: - Selection Indicator

/// Circle checkmark indicator for deck selection mode.
struct LibrarySelectionIndicator: View {
    let isSelected: Bool
    let onToggle: () -> Void

    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                Circle()
                    .fill(isSelected ? accent : Color.primary.opacity(0.08))
                    .frame(width: 26, height: 26)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 26, height: 26)
                }
            }
        }
            .buttonStyle(ScaleButtonStyle())
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Loading Overlay

/// Semi-transparent loading overlay with spinner used for operations like import and export.
struct LibraryLoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.primary)
                Text(message)
                    .font(.subheadline.weight(.medium))
            }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
                .shadow(color: .black.opacity(0.2), radius: 20)
        }
            .transition(.opacity)
    }
}

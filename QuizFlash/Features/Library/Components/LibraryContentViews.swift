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
        ForEach(groupedDecks) { section in
            Section {
                ForEach(Array(section.decks.enumerated()), id: \.element.id) { index, deck in
                    LibraryDeckListRow(
                        deck: deck,
                        isFirstInSection: index == 0,
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
                    .padding(.top, index == 0 ? 0 : 2)
                    .padding(.bottom, 2)
                    .id(deck.id)
                }
            } header: {
                LibrarySectionHeader(
                    title: section.title
                )
                    .id("header-\(section.id)")
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
    let isFirstInSection: Bool
    let isSelecting: Bool
    let isSelected: Bool
    let showActionMenu: Bool
    let onNavigate: () -> Void
    let onToggleSelection: () -> Void
    let onToggleActionMenu: (Bool) -> Void
    let onEditColor: () -> Void
    let onDelete: () -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var deckTint: Color {
        Color(hex: deck.colorHex) ?? ThemeManager.shared.accentColor.color
    }

    private var timeAgoString: String {
        Self.relativeFormatter.localizedString(for: deck.editedAt, relativeTo: Date())
    }

    private var topContentPadding: CGFloat {
        isFirstInSection
            ? LibrarySectionHeaderMetrics.firstDeckTopPadding
            : LibrarySectionHeaderMetrics.regularDeckTopPadding
    }

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
                    onNavigate()
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(deck.title)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 12) {
                            LibraryDeckMetaLabel(
                                systemImage: "rectangle.stack.fill",
                                text: "\(deck.cardCount) card\(deck.cardCount == 1 ? "" : "s")"
                            )

                            LibraryDeckMetaLabel(
                                systemImage: "clock",
                                text: timeAgoString
                            )

                            if let folder = deck.folder {
                                LibraryDeckMetaLabel(
                                    systemImage: "folder",
                                    text: folder.title
                                )
                            }

                            Spacer(minLength: 0)
                        }
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 4)
                .padding(.top, topContentPadding)
                .padding(.bottom, 14)
                .overlay(alignment: .bottom) {
                    LibraryRowSeparator(tint: deckTint)
                        .padding(.top, 10)
                }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            // ── Long-Press Action Menu ──────────────────────────────────────
            // NOT WORKING NOW 
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

struct LibraryDeckMetaLabel: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
    }
}

struct LibraryRowSeparator: View {
    let tint: Color

    var body: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: tint.opacity(0.20), location: 0.0),
                        .init(color: Color.white.opacity(0.145), location: 0.18),
                        .init(color: Color.white.opacity(0.12), location: 0.42),
                        .init(color: Color.white.opacity(0.085), location: 0.68),
                        .init(color: Color.white.opacity(0.045), location: 0.88),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: tint.opacity(0.11), location: 0.0),
                                .init(color: Color.white.opacity(0.075), location: 0.45),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(maxWidth: 168)
                    .blur(radius: 1.6)
            }
        .frame(height: 2)
        .clipShape(Capsule(style: .continuous))
        .opacity(0.88)
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
        LibrarySectionHeaderLabel(title: title)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, LibrarySectionHeaderMetrics.inlineOuterVerticalPadding)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .textCase(nil)
            .visualEffect { content, proxy in
                content.opacity(Self.stickyVisibilityOpacity(for: proxy.frame(in: .named("libraryScroll")).minY))
            }
    }

    private nonisolated static func stickyVisibilityOpacity(for minY: CGFloat) -> CGFloat {
        let fadeStart: CGFloat = -2
        let fadeEnd: CGFloat = -18

        guard minY < fadeStart else { return 1 }
        guard minY > fadeEnd else { return 0 }

        let progress = (minY - fadeEnd) / (fadeStart - fadeEnd)
        let eased = progress * progress * (3 - 2 * progress)
        return eased
    }
}

struct LibrarySectionHeaderLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.76))
            .lineLimit(1)
            .minimumScaleFactor(0.88)
            .padding(.horizontal, 8)
            .padding(.vertical, LibrarySectionHeaderMetrics.labelVerticalPadding)
            .shadow(color: .black.opacity(0.92), radius: 18, x: 0, y: 0)
            .shadow(color: .black.opacity(0.85), radius: 7, x: 0, y: 1)
            .shadow(color: .black.opacity(0.7), radius: 1.5, x: 0, y: 0)
    }
}

enum LibrarySectionHeaderMetrics {
    static let defaultHeight: CGFloat = 24
    static let inlineOuterVerticalPadding: CGFloat = 16
    static let labelVerticalPadding: CGFloat = 2
    static let firstDeckTopPadding: CGFloat = 0
    static let regularDeckTopPadding: CGFloat = 14
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

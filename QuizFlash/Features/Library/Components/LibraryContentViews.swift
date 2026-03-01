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

import SwiftUI
import SwiftData

// MARK: - List View

struct LibraryListView: View {
    let groupedDecks: [DeckSection]
    let isSelecting: Bool
    let selectedDeckIDs: Set<PersistentIdentifier>
    let onNavigate: (DeckModel) -> Void
    let onToggleSelection: (DeckModel) -> Void
    let onEditColor: (DeckModel) -> Void
    let onDelete: (DeckModel) -> Void

    var body: some View {
        Group {
            ForEach(groupedDecks) { section in
                LibrarySectionHeader(title: section.title)
                // ✅ FIX: Ancoră pentru restaurarea corectă a scroll-ului pe iOS 17
                .id("header-\(section.id)")

                ForEach(section.decks) { deck in
                    LibraryDeckListRow(
                        deck: deck,
                        isSelecting: isSelecting,
                        isSelected: selectedDeckIDs.contains(deck.id),
                        onNavigate: { onNavigate(deck) },
                        onToggleSelection: { onToggleSelection(deck) },
                        onEditColor: { onEditColor(deck) },
                        onDelete: { onDelete(deck) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 5)
                    // ✅ FIX CRITIC: ID explicit. Oferă SwiftUI-ului o țintă fixă
                    // de care să agațe scroll-ul când se întoarce dintr-un NavigationLink.
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

struct LibraryDeckListRow: View {
    let deck: DeckModel
    let isSelecting: Bool
    let isSelected: Bool
    let onNavigate: () -> Void
    let onToggleSelection: () -> Void
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
                .contextMenu {
                if !isSelecting {
                    Button(action: onEditColor) {
                        Label("Change Color", systemImage: "paintpalette")
                    }
                    Divider()
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
                .padding(.vertical, 6)
        }
            .scaleEffect(isSelecting && isSelected ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelecting)
    }
}

// MARK: - Section Header

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
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
    }
}

// MARK: - Empty State

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

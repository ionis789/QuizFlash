//
//  LibraryDeckListViews.swift
//  QuizFlash
//
//  Deck list rendering for the Library domain:
//  - grouped list wiring
//  - deck rows
//  - row metadata
//  - row separator
//  - long-press action menu
//

import SwiftUI
import SwiftData

// MARK: - Coordinate Space Name

/// Named by LibraryLayout on its ScrollView; read here by row-level visual effects.
let kLibraryScrollSpace = "libraryScroll"

// MARK: - List View

/// The main list view displaying grouped decks.
/// Relies purely on primitives to ensure performance.
struct LibraryListView: View {
    let groupedDecks: [DeckSection]
    let isSelecting: Bool
    let selectedDeckIDs: Set<PersistentIdentifier>
    let activeActionMenuDeckID: PersistentIdentifier?
    let onNavigate: (PersistentIdentifier) -> Void
    let onToggleSelection: (PersistentIdentifier) -> Void
    let onToggleActionMenu: (PersistentIdentifier?) -> Void
    let onEditColor: (LibraryDeckActionTarget) -> Void
    let onDelete: (LibraryDeckActionTarget) -> Void

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
                        onNavigate: { onNavigate(deck.id) },
                        onToggleSelection: { onToggleSelection(deck.id) },
                        onToggleActionMenu: { show in onToggleActionMenu(show ? deck.id : nil) },
                        onEditColor: { onEditColor(LibraryDeckActionTarget(id: deck.id, title: deck.title)) },
                        onDelete: { onDelete(LibraryDeckActionTarget(id: deck.id, title: deck.title)) }
                    )
                    .equatable()
                    .padding(.horizontal, UIConstants.Layout.compactScreenEdgeInset)
                    .padding(.top, index == 0 ? 0 : 2)
                    .padding(.bottom, 2)
                    .id(deck.id)
                }
            } header: {
                LibrarySectionHeader(title: section.title)
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
struct LibraryDeckListRow: View, Equatable {
    let deck: LibraryDeckRowSnapshot
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

    static func == (lhs: LibraryDeckListRow, rhs: LibraryDeckListRow) -> Bool {
        lhs.deck == rhs.deck &&
        lhs.isFirstInSection == rhs.isFirstInSection &&
        lhs.isSelecting == rhs.isSelecting &&
        lhs.isSelected == rhs.isSelected &&
        lhs.showActionMenu == rhs.showActionMenu
    }

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

                            if let folderTitle = deck.folderTitle {
                                LibraryDeckMetaLabel(
                                    systemImage: "folder",
                                    text: folderTitle
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
        .overlay(alignment: .bottom) {
            if showActionMenu {
                DeckActionMenu(
                    onEditColor: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            onToggleActionMenu(false)
                        }
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

private struct DeckActionMenu: View {
    let onEditColor: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

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

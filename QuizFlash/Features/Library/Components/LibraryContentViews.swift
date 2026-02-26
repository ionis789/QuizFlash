//
//  LibraryContentViews.swift
//  QuizFlash
//
//  Contains: LibraryListView, LibraryDeckListRow,
//            LibrarySectionHeader, LibraryEmptyStateView,
//            LibrarySelectionIndicator, LibraryLoadingOverlay
//

import SwiftUI
import SwiftData

// MARK: - List View

struct LibraryListView: View {
    let groupedDecks: [DeckSection]
    @Bindable var viewModel: LibraryViewModel
    let onNavigate: (DeckModel) -> Void

    var body: some View {
        LazyVStack(spacing: 0, pinnedViews: []) {
            ForEach(groupedDecks) { section in
                Section {
                    VStack(spacing: 10) {
                        ForEach(section.decks) { deck in
                            LibraryDeckListRow(
                                deck: deck,
                                viewModel: viewModel,
                                onNavigate: onNavigate
                            )
                        }
                    }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                } header: {
                    LibrarySectionHeader(title: section.title)
                }
            }
        }
    }
}

// MARK: - Deck List Row

struct LibraryDeckListRow: View {
    let deck: DeckModel
    @Bindable var viewModel: LibraryViewModel
    let onNavigate: (DeckModel) -> Void

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var isSelected: Bool { viewModel.selectedDecks.contains(deck.id) }

    var body: some View {
        HStack(spacing: 10) {
            if viewModel.isSelecting {
                LibrarySelectionIndicator(isSelected: isSelected) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        viewModel.toggleSelection(for: deck)
                    }
                }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Button {
                if viewModel.isSelecting {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        viewModel.toggleSelection(for: deck)
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        onNavigate(deck)
                    }
                }
            } label: {
                DeckRowView(deck: deck)
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(ScaleButtonStyle())
                .contextMenu {
                if !viewModel.isSelecting {
                    Button { viewModel.deckToEditColor = deck } label: {
                        Label("Change Color", systemImage: "paintpalette")
                    }
                    Divider()
                    Button(role: .destructive) { viewModel.deckToDelete = deck } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
                .padding(.vertical, 6)
        }

            .scaleEffect(viewModel.isSelecting && isSelected ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.isSelecting)
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

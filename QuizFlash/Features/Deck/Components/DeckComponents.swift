//
//  DeckComponents.swift
//  QuizFlash
//
//  Created by Ion Socol on 08.02.2026.
//

import SwiftUI

// MARK: - 1. Deck Header View
struct DeckHeaderView: View {
    let deck: DeckModel
    var onEdit: () -> Void

    private var deckColor: Color {
        Color(hex: deck.colorHex) ?? .blue
    }

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }


    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: deck.createdAt)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {

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

                // Title & Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Label("\(deck.cardCount)", systemImage: "rectangle.stack")
                        Text("•")
                        Text(formattedDate)
                    }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Edit Button (Deck details)
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
            .background(Color(uiColor: .systemGroupedBackground))
    }
}

// MARK: - 2. Play Modes View (Premium 2×2 Grid)
struct DeckPlayModesView: View {
    let deck: DeckModel
    var onPlay: () -> Void

    private var accentColor: Color { ThemeManager.shared.accentColor.color }
    private var isEmpty: Bool { deck.cardCount == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PLAY MODES")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                PlayModeCard(
                    title: "Default",
                    subtitle: "Swipe to review",
                    systemImage: "play.fill",
                    color: accentColor,
                    isAvailable: !isEmpty,
                    action: onPlay
                )
                PlayModeCard(
                    title: "Quiz",
                    subtitle: "Multiple choice",
                    systemImage: "questionmark.square.dashed",
                    color: .purple,
                    isAvailable: !isEmpty,
                    action: onPlay
                )
                PlayModeCard(
                    title: "Learn",
                    subtitle: "Spaced repetition",
                    systemImage: "book.and.wrench",
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
                .padding(.horizontal, 20)
        }
    }
}

private struct PlayModeCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(color.opacity(isAvailable ? 0.15 : 0.06))
                        .frame(width: 34, height: 34)
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isAvailable ? color : color.opacity(0.30))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isAvailable ? .primary : .tertiary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
                .padding(10)
                .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
                .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isAvailable ? color.opacity(0.12) : Color.clear, lineWidth: 0.5)
            )
        }
            .buttonStyle(.plain)
            .disabled(!isAvailable)
            .opacity(isAvailable ? 1.0 : 0.45)
    }
}

struct DeckSectionToolbar: View {
    let deck: DeckModel
    let isSelecting: Bool
    @Binding var sortOrder: SortOrder
    @Binding var isMenuExpanded: Bool
    @Binding var menuPosition: CGRect // The final @State to actually render
    let menuTracker: MenuPositionTracker // The silent tracker

    var onAdd: () -> Void
    var onStartSelection: () -> Void
    var onExport: (() -> Void)? = nil

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("CARDS(\(deck.cardCount))")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onAdd) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "plus")
                        .font(.headline.bold())
                        .foregroundStyle(accent)
                }
            }


            if deck.cardCount > 0 {
                Button {
                    // Update state ONLY ONCE when clicked, triggering the UI redraw
                    menuPosition = menuTracker.rect
                    withAnimation(.smooth) { isMenuExpanded.toggle() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(isSelecting || isMenuExpanded ? 1.0 : 0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: "ellipsis")
                            .font(.headline.bold())
                            .foregroundStyle(isSelecting || isMenuExpanded ? .white : accent)
                    }
                }
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { newValue in
                    // Silently track without triggering 120Hz @State redraws
                    menuTracker.rect = newValue
                }
            }


        }
            .padding(.horizontal, 20)
    }
}

// MARK: - 4. Selection Bottom Bar (Floating)
struct DeckSelectionBottomBar: View {
    let selectedCount: Int
    var onDone: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onDone) {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            Spacer()

            Button(role: .destructive, action: onDelete) {
                HStack(spacing: 8) {
                    Text("Delete(\(selectedCount))")
                        .fontWeight(.semibold)
                }
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
                .disabled(selectedCount == 0)
                .opacity(selectedCount == 0 ? 0.5 : 1)
        }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.horizontal, 20)
    }
}

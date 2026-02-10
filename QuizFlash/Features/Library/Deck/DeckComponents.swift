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
                        Label("\(deck.cards.count)", systemImage: "rectangle.stack")
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

// MARK: - 2. Play Modes View
struct DeckPlayModesView: View {
    let deck: DeckModel
    var onPlay: () -> Void

    private var accentColor: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PLAY MODES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ModeButton(title: "Default", systemImage: "play.fill", color: accentColor, isActive: true, action: onPlay)
                        .disabled(deck.cards.isEmpty)
                        .opacity(deck.cards.isEmpty ? 0.5 : 1)

                    ModeButton(title: "Timed", systemImage: "timer", color: accentColor, isActive: false, action: { })
                        .disabled(true)
                        .opacity(0.4)

                    ModeButton(title: "Match", systemImage: "square.grid.2x2", color: accentColor, isActive: false, action: { })
                        .disabled(true)
                        .opacity(0.4)
                }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
            }
        }
    }
}

private struct ModeButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isActive ? color.opacity(0.15) : Color(uiColor: .secondarySystemGroupedBackground))
            )
                .foregroundStyle(isActive ? color : .secondary)
        }
    }
}

struct DeckSectionToolbar: View {
    let deck: DeckModel
    let isSelecting: Bool
    @Binding var sortOrder: SortOrder

    var onAdd: () -> Void
    var onStartSelection: () -> Void

    private var accentColor: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        HStack(spacing: 12) {
            Text("CARDS(\(deck.cards.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()



      
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
                .disabled(isSelecting)


            if !deck.cards.isEmpty {
           
                Menu {
               
                    Button(action: onStartSelection) {
                        Label("Select Cards", systemImage: "checkmark.circle")
                    }
                        .disabled(isSelecting)

               
                    Menu {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    sortOrder = order
                                }
                            } label: {
                                if sortOrder == order {
                                    Label(order.rawValue, systemImage: "checkmark")
                                } else {
                                    Label(order.rawValue, systemImage: order.icon)
                                }
                            }
                        }
                    } label: {
                        Label("Sort By", systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3.weight(.semibold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                        .foregroundStyle(accentColor)
                }
                    .disabled(isSelecting)
                .opacity(isSelecting ? 0.5 : 1)
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

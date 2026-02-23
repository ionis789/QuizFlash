//
//  LibraryTopBarView.swift
//  QuizFlash
//

import SwiftUI

struct LibraryTopBarView: View {

    @Bindable var viewModel: LibraryViewModel
    let deckCount: Int

    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Library")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(deckCount == 0 ? "No Decks" : "\(deckCount) Deck\(deckCount == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Menu { menuContent } label: {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accent)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .background(
            // The glass extends 60pt below the bar to create a fade.
            // allowsHitTesting(false) ensures that invisible zone never
            // steals taps from deck rows scrolling underneath it.
            Color.clear
                .glassEffect(cornerRadius: 0, showSpecular: false)
                .padding(.bottom, -60)
                .ignoresSafeArea(edges: .top)
                .mask(
                    VStack(spacing: 0) {
                        Color.black
                        Color.black
                            .frame(height: 60)
                            .mask(
                                LinearGradient(
                                    colors: [.black, .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .ignoresSafeArea(edges: .top)
                    .padding(.bottom, -60)
                )
                .allowsHitTesting(false) // ← critical: fade zone must never eat touches
        )
    }

    @ViewBuilder
    private var menuContent: some View {
        Button { viewModel.showFileImporter = true } label: {
            Label("Import Deck", systemImage: "square.and.arrow.down")
        }

        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                viewModel.isSelecting = true
            }
        } label: {
            Label("Select", systemImage: "checkmark.circle")
        }
        .disabled(viewModel.isSelecting || viewModel.isSearching)

        Divider()

        Menu {
            ForEach(SortOrder.allCases, id: \.self) { order in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        viewModel.sortOrder = order
                    }
                } label: {
                    if viewModel.sortOrder == order {
                        Label(order.rawValue, systemImage: "checkmark")
                    } else {
                        Label(order.rawValue, systemImage: order.icon)
                    }
                }
            }
        } label: {
            Label("Sort By", systemImage: "arrow.up.arrow.down")
        }
    }
}

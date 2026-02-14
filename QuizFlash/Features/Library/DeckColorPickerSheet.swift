//
//  DeckColorPickerSheet.swift
//  QuizFlash
//
//  UI-only: sheet to pick deck accent color.
//

import SwiftUI
import SwiftData

// MARK: - Deck Color Picker Sheet

struct DeckColorPickerSheet: View {
    @Bindable var deck: DeckModel
    @Environment(\.dismiss) var dismiss

    private let colors: [Color] = [
        .blue, .purple, .pink, .red, .orange,
        .yellow, .green, .mint, .teal, .cyan
    ]

    private let columns = [
        GridItem(.adaptive(minimum: 60, maximum: 80), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [deckColor.opacity(0.7), deckColor.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    Image(systemName: deck.icon.isEmpty ? "sparkles.rectangle.stack.fill" : deck.icon)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 20)

                Text(deck.title)
                    .font(.title3.weight(.semibold))

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(colors, id: \.self) { color in
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                deck.colorHex = color.toHex()!
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(color)
                                    .frame(width: 50, height: 50)
                                    .shadow(color: color.opacity(0.4), radius: 6, y: 3)

                                if deckColor.toHex() == color.toHex() {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)

                Spacer()
            }
            .navigationTitle("Deck Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var deckColor: Color {
        Color(hex: deck.colorHex) ?? .blue
    }
}

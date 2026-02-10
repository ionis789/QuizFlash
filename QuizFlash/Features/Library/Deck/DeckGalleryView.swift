//
//  DeckRowView.swift
//  QuizFlash
//
//  Created by Ion Socol on 07.01.2026.
//

import SwiftUI
import SwiftData
struct DeckGalleryView: View {
    let deck: DeckModel

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: deck.createdAt, relativeTo: Date())
    }

    private var deckColor: Color {
        Color(hex: deck.colorHex) ?? .blue
    }

    var body: some View {
        VStack {
            HStack(spacing: 14) {
                // Icon with deck color
                ZStack {
                    Circle()
                        .fill(
                        LinearGradient(
                            colors: [deckColor.opacity(0.7), deckColor.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                        .frame(width: 48, height: 48)

                    Image(systemName: deck.icon.isEmpty ? "sparkles.rectangle.stack.fill" : deck.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 12) {
                        // Cards count
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.stack")
                                .font(.caption2)
                            Text("\(deck.cards.count)")
                                .font(.caption.weight(.medium))
                        }
                            .foregroundStyle(.secondary)

                        // Date
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(formattedDate)
                                .font(.caption.weight(.medium))
                        }
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            ForEach(deck.cards) { deck in
                HStack {
                    Image(systemName: "dot.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(
                        deck.frontText.count > 30 ? deck.frontText.prefix(30) + "..." : deck.frontText
                    )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }


            }


        }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}


#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: DeckModel.self, CardModel.self, configurations: config)

  
    let demoDeck = DeckModel(
        title: "SwiftUI Learning",
        icon: "swift",
        colorHex: "#FF5733"
    )
    container.mainContext.insert(demoDeck)

 
    let demoCards = [
        CardModel(
            frontText: "Ce wrapper folosim pentru a observa obiecte în SwiftData?",
            backText: "@Query"
        ),
        CardModel(
            frontText: "Ce wrapper folosim pentru a observa obiecte în SwiftData?",
            backText: "@Query"
        ),
        CardModel(
            frontText: "Ce wrapper folosim pentru a observa obiecte în SwiftData?",
            backText: "@Query"
        )
    ]

    demoDeck.cards.append(contentsOf: demoCards)

    return ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

        DeckGalleryView(deck: demoDeck)
            .frame(width: 250)
    }
        .modelContainer(container)
}

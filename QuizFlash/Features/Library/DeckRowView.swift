//
//  DeckRowView.swift
//  QuizFlash
//
//  Created by Ion Socol on 07.01.2026.
//

import SwiftUI

struct DeckRowView: View {
    let deck: DeckModel

    var deckColor: Color {
            .accent
    }

    var body: some View {
        ZStack {

            if !deck.cards.isEmpty {
                RoundedRectangle(cornerRadius: 20)
                    .fill(deckColor.opacity(0.1))
                    .frame(height: 70)
                .offset(y: 8)
                .padding(.horizontal, 24)
                .blur(radius: 4)
            }

            VStack(alignment: .leading) {
                HStack(spacing: 16) {

                    ZStack {
                        Circle()
                            .fill(
                            LinearGradient(
                                colors: [deckColor.opacity(0.6), deckColor.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                            .frame(width: 50, height: 50)
                            .shadow(color: deckColor.opacity(0.5), radius: 8, x: 0, y: 4)

                        Image(systemName: deck.icon.isEmpty ? "sparkles.rectangle.stack.fill" : deck.icon)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    }

                    // INFO
                    VStack(alignment: .leading, spacing: 4) {
                        Text(deck.title)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        .lineLimit(1)

                        HStack(spacing: 6) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Text("\(deck.cards.count) cards")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

           
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.3))
                        .padding(.trailing, 4)
                }

                if !deck.cards.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                   
                        ForEach(deck.cards.prefix(3)) { card in
                            HStack(alignment: .center, spacing: 10) {
                           
                                Circle()
                                    .fill(deckColor.opacity(0.6))
                                    .frame(width: 6, height: 6)

                                Text(card.fronText)
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                 
                        if deck.cards.count > 3 {
                            Text("+ încă \(deck.cards.count - 3) carduri")
                                .font(.caption.bold())
                                .italic()
                                .foregroundStyle(.secondary.opacity(0.7))
                                .padding(.leading, 16)
                                .padding(.top, 2)
                        }
                    }
                        .padding(.top, 4)
                        .padding(.leading, 4)
                } else {
                    Text("No cards added yet")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary.opacity(0.5))
                        .padding(.leading, 4)
                }

            }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
         
            .modifier(LiquidGlassModifier(cornerRadius: 24))
        
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(deckColor.opacity(0.08))
            )
        }
        .padding(.horizontal, 16)
            .padding(.vertical, 6)
    }
}

// MARK: - Helper

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0

        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0

        } else {
            return nil
        }

        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

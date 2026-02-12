//
//  CardRowView.swift
//  QuizFlash
//
//  Created by Ion Socol on 04.01.2026.
//

import SwiftUI

struct CardRowView: View {
    let card: DraftCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 24, height: 24)

                    Text("Q")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.blue)
                }
                Text(card.front)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 24, height: 24)

                    Text("A")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }

                Text(card.back)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

#Preview {
    ZStack {
        Color(uiColor: .systemGroupedBackground)
        CardRowView(card: DraftCard(front: "What represents the powerhouse of the cell?", back: "Mitochondria is the powerhouse of the cell."))
            .padding()
    }
}

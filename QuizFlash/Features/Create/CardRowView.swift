//
//  CardRowView.swift
//  QuizFlash
//
//  Created by Ion Socol on 12.02.2026.
//
//  Card row view for the create deck list.
//

import SwiftUI

struct CardRowView: View {
    let card: DraftCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: Question
            contentRow(
                label: "Q",
                color: .blue,
                content: card.frontContent,
                type: card.frontType
            )

            Divider().opacity(0.3)

            // Row 2: Answer
            contentRow(
                label: "A",
                color: .green,
                content: card.backContent,
                type: card.backType
            )
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
    
    @ViewBuilder
    private func contentRow(label: String, color: Color, content: CardSideContent, type: CardContentType) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Label badge
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 24, height: 24)
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
            }
            
            if type == .text {
                let text = content.combinedText
                let hasImages = !content.allImages.isEmpty
                let hasSketch = content.blocks.contains { $0.type == .sketch }
                
                if text.isEmpty && hasImages {
                    Label("Image", systemImage: "photo")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if text.isEmpty && hasSketch {
                    Label("Sketch", systemImage: "scribble.variable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(text.isEmpty ? "Empty" : text)
                        .font(.subheadline)
                        .foregroundStyle(text.isEmpty ? Color.secondary.opacity(0.5) : Color.primary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Attachment indicators
                HStack(spacing: 4) {
                    if hasImages {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if hasSketch {
                        Image(systemName: "scribble.variable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Canvas/Sketch type
                HStack(spacing: 4) {
                    Image(systemName: "scribble.variable")
                    Text("Sketch")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                
                Spacer()
            }
        }
    }
}

//
//  CardRowView.swift
//  QuizFlash
//
//  Informative premium card row for CreateView: index, question/answer preview, and thumbnails.
//

import SwiftUI

struct DetailedCardRowView: View {
    let card: DraftCard
    var index: Int

    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // MARK: - Header (Index, Media Icons, Last Edit)
            HStack(alignment: .center) {
                // Index Badge
                Text("CARD \(index)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(accent)

                Spacer()

                // Media Indicators (Count + Icon)
                let totalImages = imageCount(in: card.frontZone) + imageCount(in: card.backZone)
                let totalSketches = sketchCount(in: card.frontZone) + sketchCount(in: card.backZone)

                HStack(spacing: 12) {
                    if totalImages > 0 {
                        HStack(spacing: 3) {
                            Text("\(totalImages)")
                            Image(systemName: "photo")
                        }
                    }
                    if totalSketches > 0 {
                        HStack(spacing: 3) {
                            Text("\(totalSketches)")
                            Image(systemName: "scribble.variable")
                        }
                    }
                }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }

            // MARK: - Q & A Previews
            VStack(alignment: .leading, spacing: 10) {
                previewTextRow(label: "Q", text: card.frontZone.previewText(maxLength: 80), color: .gray)

                Divider().opacity(0.4)

                previewTextRow(label: "A", text: card.backZone.previewText(maxLength: 80), color: .gray)
            }

            // MARK: - Thumbnails Gallery
            let allThumbnails = (card.frontZone.thumbnails + card.backZone.thumbnails).prefix(4)
            if !allThumbnails.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(allThumbnails.enumerated()), id: \.offset) { _, img in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    }
                }
                    .padding(.top, 4)
            }

            // MARK: - Footer (Info)
            HStack {
                Text("\(zoneCount(card.frontZone) + zoneCount(card.backZone)) Zones")
                Spacer()
                if let date = card.lastEditDate {
                    Text("Edited: \(date.formatted(date: .omitted, time: .shortened))")
                }
            }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

        }
            .padding(16)
            .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
            .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func previewTextRow(label: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .leading)

            Text(text == "Empty" ? "No text added" : text)
                .font(.subheadline)
                .foregroundStyle(text == "Empty" ? Color.gray.opacity(0.5) : color)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    // MARK: - Logic Helpers

    private func zoneCount(_ zone: ZoneModel) -> Int {
        1 + (zone.children?.reduce(0) { $0 + zoneCount($1) } ?? 0)
    }

    /// Recursively numără câte imagini valide există în zone
    private func imageCount(in zone: ZoneModel) -> Int {
        if zone.isLeaf {
            return (zone.contentType == .image && zone.hasContent) ? 1 : 0
        }
        return zone.children?.reduce(0) { $0 + imageCount(in: $1) } ?? 0
    }

    /// Recursively numără câte schițe valide există în zone
    private func sketchCount(in zone: ZoneModel) -> Int {
        if zone.isLeaf {
            return (zone.contentType == .sketch && zone.hasContent) ? 1 : 0
        }
        return zone.children?.reduce(0) { $0 + sketchCount(in: $1) } ?? 0
    }
}

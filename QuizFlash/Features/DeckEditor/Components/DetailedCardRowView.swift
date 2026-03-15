//
//  CardRowView.swift
//  QuizFlash
//
//  Informative premium card row for CreateView: index, question/answer preview, and thumbnails.
//

import SwiftUI

private let kDraftCardThumbnailSize = CGSize(width: 46, height: 46)

struct DetailedCardRowView: View {
    let card: DraftCard
    var index: Int
    var fixedHeight: CGFloat? = nil

    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        Group {
            if let fixedHeight {
                cardContent
                    .padding(18)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: fixedHeight,
                        maxHeight: fixedHeight,
                        alignment: .topLeading
                    )
            } else {
                cardContent
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            VStack(alignment: .leading, spacing: 12) {
                previewTextRow(label: "Q", text: card.frontZone.previewText(maxLength: 96))

                Rectangle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 1)

                previewTextRow(label: "A", text: card.backZone.previewText(maxLength: 96))
            }

            let allThumbnailData = (card.frontZone.thumbnailDataList + card.backZone.thumbnailDataList).prefix(4)
            if !allThumbnailData.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(allThumbnailData.enumerated()), id: \.offset) { _, data in
                        DraftCardThumbnailView(data: data)
                    }
                }
            }

            footer
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
            Text("Card \(index)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 8) {
                let totalImages = imageCount(in: card.frontZone) + imageCount(in: card.backZone)
                let totalSketches = sketchCount(in: card.frontZone) + sketchCount(in: card.backZone)

                if totalImages > 0 {
                    metadataBadge(text: "\(totalImages)", symbol: "photo")
                }

                if totalSketches > 0 {
                    metadataBadge(text: "\(totalSketches)", symbol: "scribble.variable")
                }
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center) {
            Text("\(zoneCount(card.frontZone) + zoneCount(card.backZone)) zones")

            Spacer()

            if let date = card.lastEditDate {
                Text("Edited \(date.formatted(date: .omitted, time: .shortened))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func previewTextRow(label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .frame(width: 18, alignment: .leading)

            Text(text == "Empty" ? "No text added" : text)
                .font(.subheadline)
                .foregroundStyle(text == "Empty" ? .secondary : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    @ViewBuilder
    private func metadataBadge(text: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: symbol)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }

    private func zoneCount(_ zone: ZoneModel) -> Int {
        1 + (zone.children?.reduce(0) { $0 + zoneCount($1) } ?? 0)
    }

    /// Recursively counts the number of valid image zones in the subtree.
    private func imageCount(in zone: ZoneModel) -> Int {
        if zone.isLeaf {
            return (zone.contentType == .image && zone.hasContent) ? 1 : 0
        }
        return zone.children?.reduce(0) { $0 + imageCount(in: $1) } ?? 0
    }

    /// Recursively counts the number of valid sketch zones in the subtree.
    private func sketchCount(in zone: ZoneModel) -> Int {
        if zone.isLeaf {
            return (zone.contentType == .sketch && zone.hasContent) ? 1 : 0
        }
        return zone.children?.reduce(0) { $0 + sketchCount(in: $1) } ?? 0
    }
}

private struct DraftCardThumbnailView: View {
    let data: Data

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
        .onAppear {
            guard image == nil else { return }
            let cacheID = "draft-card-thumb-\(data.hashValue)"
            image = ImageCache.shared.image(
                for: data,
                id: cacheID,
                targetSize: kDraftCardThumbnailSize
            )
        }
    }
}

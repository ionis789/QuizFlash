//
//  CardRowView.swift
//  QuizFlash
//
//  Informative card row for CreateView: index, question/answer preview from zones.
//

import SwiftUI

struct CardRowView: View {
    let card: DraftCard
    var index: Int = 0

    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            indexBadge
            VStack(alignment: .leading, spacing: 10) {
                previewRow(label: "Q", zone: card.frontZone, color: .blue)
                Divider().opacity(0.35)
                previewRow(label: "A", zone: card.backZone, color: .green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.15), lineWidth: 1)
        )
    }

    private var indexBadge: some View {
        Text("\(index)")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(accent)
            .frame(width: 28, height: 28)
            .background(accent.opacity(0.12), in: Circle())
    }

    @ViewBuilder
    private func previewRow(label: String, zone: ZoneModel, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 18, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(zone.previewText(maxLength: 50))
                    .font(.subheadline)
                    .foregroundStyle(zone.hasContent ? Color.primary : Color.secondary)
                    .lineLimit(2)
                if zone.hasContent && (zone.contentType == .image || zone.contentType == .sketch || zoneHasImageOrSketch(zone)) {
                    HStack(spacing: 6) {
                        if zoneHasImage(zone) {
                            Label("Image", systemImage: "photo")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if zoneHasSketch(zone) {
                            Label("Sketch", systemImage: "scribble.variable")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func zoneHasImage(_ zone: ZoneModel) -> Bool {
        if zone.isLeaf { return zone.contentType == .image }
        return zone.children?.contains(where: zoneHasImage) ?? false
    }

    private func zoneHasSketch(_ zone: ZoneModel) -> Bool {
        if zone.isLeaf { return zone.contentType == .sketch }
        return zone.children?.contains(where: zoneHasSketch) ?? false
    }

    private func zoneHasImageOrSketch(_ zone: ZoneModel) -> Bool {
        zoneHasImage(zone) || zoneHasSketch(zone)
    }
}

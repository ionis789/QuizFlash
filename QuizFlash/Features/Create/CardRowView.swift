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
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                indexBadge
                VStack(alignment: .leading, spacing: 10) {
                    previewRow(label: "Q", zone: card.frontZone, color: .blue)
                    Divider().opacity(0.25)
                    previewRow(label: "A", zone: card.backZone, color: .green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(accent.opacity(0.18), lineWidth: 1.2)
            )
            infoRow
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    private var indexBadge: some View {
        Text("\(index)")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(accent.gradient.opacity(0.8), in: Circle())
            .shadow(color: accent.opacity(0.18), radius: 4, x: 0, y: 2)
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
                // Thumbnail preview pentru imagini/sketch
                let thumbnails = zone.thumbnails
                if !thumbnails.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(thumbnails.prefix(3), id: \ .self) { img in
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(radius: 2)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var infoRow: some View {
        HStack(spacing: 16) {
            Label(card.frontType.rawValue.capitalized, systemImage: iconForType(card.frontType))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Zone Count: \(zoneCount(card.frontZone) + zoneCount(card.backZone))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let date = card.lastEditDate {
                Label("Last Edit: \(dateString(date))", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.8))
        )
        .padding(.top, 4)
    }

    private func iconForType(_ type: CardContentType) -> String {
        switch type {
        case .text: return "character.cursor.ibeam"
        case .canvas: return "scribble"
        }
    }

    private func zoneCount(_ zone: ZoneModel) -> Int {
        1 + (zone.children?.reduce(0) { $0 + zoneCount($1) } ?? 0)
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

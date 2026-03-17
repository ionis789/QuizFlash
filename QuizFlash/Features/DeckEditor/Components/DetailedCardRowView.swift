//
//  DetailedCardRowView.swift
//  QuizFlash
//
//  Rich draft-card preview used by the deck editor list.
//

import SwiftUI

struct DetailedCardRowView: View {
    let card: DraftCard
    var index: Int
    var fixedHeight: CGFloat? = nil
    var isSelecting: Bool = false
    var isSelected: Bool = false

    var onPrimaryTap: (() -> Void)? = nil

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var isCompactPreview: Bool { fixedHeight != nil }
    private var trailingAccessorySize: CGFloat { 34 }
    private var displayCardNumber: Int { card.cardNumber > 0 ? card.cardNumber : index }

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
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .widgetStyle(cornerRadius: 30)
        .scaleEffect(isSelected ? 0.9 : 1, anchor: .center)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            onPrimaryTap?()
        }
    }

    private var cardContent: some View {
        let summary = DraftCardContentSummary(card: card)

        return VStack(alignment: .leading, spacing: isCompactPreview ? 14 : 18) {
            header

            if !isCompactPreview {
                metricsStrip(summary: summary)
            }

            previewSurface(summary: summary)
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
            Text("Card \(displayCardNumber)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.92))

            if card.isPinned && !isCompactPreview {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: UIConstants.Spacing.small)

            trailingAccessory
        }
        .frame(minHeight: trailingAccessorySize, alignment: .center)
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        Group {
            if isSelecting {
                selectionIndicator
            } else {
                Color.clear
            }
        }
        .frame(width: isSelecting ? trailingAccessorySize : 0, height: trailingAccessorySize)
    }

    private func metricsStrip(summary: DraftCardContentSummary) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(text: "\(summary.front.displayZoneCount) Q zones", symbol: "q.circle")
                chip(text: "\(summary.back.displayZoneCount) A zones", symbol: "a.circle")
                chip(text: "\(summary.total.textCharacterCount) chars", symbol: "textformat")
                chip(text: "\(summary.total.imageCount) photos", symbol: "photo")
                chip(text: "\(summary.total.sketchCount) sketches", symbol: "pencil.and.outline")
                chip(
                    text: card.creationSource == .ai ? "AI" : "Manual",
                    symbol: card.creationSource == .ai ? "sparkles" : "hand.tap",
                    tint: card.creationSource == .ai ? accent : .secondary
                )
            }
        }
        .scrollIndicators(.hidden)
    }

    private func previewSurface(summary: DraftCardContentSummary) -> some View {
        VStack(alignment: .leading, spacing: isCompactPreview ? 10 : 14) {
            previewBlock(
                text: previewText(for: card.frontZone, maxLength: isCompactPreview ? 140 : 360),
                hasContent: summary.front.hasContent,
                lineLimit: isCompactPreview ? 2 : 5
            )

            Divider()
                .overlay(Color.white.opacity(0.05))

            previewBlock(
                text: previewText(for: card.backZone, maxLength: isCompactPreview ? 180 : 460),
                hasContent: summary.back.hasContent,
                lineLimit: isCompactPreview ? 3 : 7
            )
        }
        .padding(isCompactPreview ? 0 : 18)
        .background {
            if !isCompactPreview {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            }
        }
    }

    private func previewBlock(
        text: String,
        hasContent: Bool,
        lineLimit: Int
    ) -> some View {
        Text(text)
            .font(isCompactPreview ? .subheadline : .system(size: 19, weight: .medium, design: .rounded))
            .foregroundStyle(hasContent ? .primary : .secondary)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: !isCompactPreview)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.standard) {
            if let createdAt = card.createdAt {
                Text("Created \(createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: UIConstants.Spacing.small)

            if shouldShowEditedDate, let editedAt = card.editedAt {
                Text("Edited \(editedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(isSelected ? 0.08 : 0.05))

            Circle()
                .stroke(
                    isSelected ? accent.opacity(0.85) : Color.white.opacity(0.22),
                    lineWidth: isSelected ? 1.8 : 1.4
                )

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .transition(.opacity)
            }
        }
        .frame(width: trailingAccessorySize, height: trailingAccessorySize)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func chip(text: String, symbol: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.05), in: Capsule())
    }

    private var shouldShowEditedDate: Bool {
        guard let createdAt = card.createdAt, let editedAt = card.editedAt else { return false }
        return abs(editedAt.timeIntervalSince(createdAt)) > 1
    }

    private func previewText(for zone: ZoneModel, maxLength: Int) -> String {
        let separator = isCompactPreview ? " • " : "\n\n"
        let combined = previewFragments(in: zone).joined(separator: separator)
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return "No content added" }
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func previewFragments(in zone: ZoneModel) -> [String] {
        if zone.isLeaf {
            switch zone.contentType {
            case .text:
                return normalizedTextFragments(from: zone.text)
            case .code:
                let fragments = normalizedTextFragments(from: zone.text)
                if fragments.isEmpty {
                    if let language = zone.codeLanguage?.uppercased() {
                        return ["\(language) code"]
                    }
                    return ["Code"]
                }

                let joined = fragments.joined(separator: " ")
                if let language = zone.codeLanguage?.uppercased() {
                    return ["\(language) code: \(joined)"]
                }
                return ["Code: \(joined)"]
            case .image:
                return zone.imageData == nil ? [] : ["Image"]
            case .sketch:
                return zone.imageData == nil ? [] : ["Sketch"]
            case .empty:
                return []
            }
        }

        return zone.children?.flatMap { previewFragments(in: $0) } ?? []
    }

    private func normalizedTextFragments(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

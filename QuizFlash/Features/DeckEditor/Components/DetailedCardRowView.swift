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

    var onEdit: (() -> Void)? = nil
    var onTogglePin: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isShowingMenu = false

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var isCompactPreview: Bool { fixedHeight != nil }
    private var showsOverflowMenu: Bool {
        !isSelecting && onEdit != nil && onTogglePin != nil && onDelete != nil && !isCompactPreview
    }

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
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isSelected)
    }

    private var cardContent: some View {
        let summary = DraftCardContentSummary(card: card)

        return VStack(alignment: .leading, spacing: isCompactPreview ? 14 : 18) {
            header(summary: summary)

            if !isCompactPreview {
                metricsStrip(summary: summary)
            }

            previewSurface(summary: summary)
            footer
        }
    }

    private func header(summary: DraftCardContentSummary) -> some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
            Text("Card \(index)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.92))

            if card.isPinned && !isCompactPreview {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: UIConstants.Spacing.small)

            if isSelecting {
                selectionIndicator
            } else if showsOverflowMenu {
                overflowMenuButton(summary: summary)
            }
        }
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
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .accessibilityHidden(true)
    }

    private func overflowMenuButton(summary: DraftCardContentSummary) -> some View {
        Button {
            isShowingMenu = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.05), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Card actions")
        .popover(isPresented: $isShowingMenu, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            CreateDeckCardContextMenu(
                title: "Card \(index)",
                summary: menuSummary(summary: summary),
                isPinned: card.isPinned,
                tint: menuTint,
                onEdit: {
                    isShowingMenu = false
                    onEdit?()
                },
                onTogglePin: {
                    isShowingMenu = false
                    onTogglePin?()
                },
                onDelete: {
                    isShowingMenu = false
                    onDelete?()
                }
            )
            .presentationCompactAdaptation(.popover)
        }
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

    private func menuSummary(summary: DraftCardContentSummary) -> String {
        var parts = [
            card.creationSource == .ai ? "AI generated" : "Manual",
            "\(summary.front.displayZoneCount) Q",
            "\(summary.back.displayZoneCount) A",
            "\(summary.total.textCharacterCount) chars"
        ]

        if card.isPinned {
            parts.append("Pinned")
        }

        return parts.joined(separator: " • ")
    }

    private var menuTint: Color {
        if card.isPinned {
            return .orange
        }
        return card.creationSource == .ai ? accent : .secondary
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

private struct CreateDeckCardContextMenu: View {
    let title: String
    let summary: String
    let isPinned: Bool
    let tint: Color
    let onEdit: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.tiny + 2) {
                HStack(spacing: UIConstants.Spacing.small) {
                    Circle()
                        .fill(tint.opacity(0.9))
                        .frame(width: 8, height: 8)

                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer(minLength: UIConstants.Spacing.small)
                }

                Text(summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider()
                .background(Color.primary.opacity(0.08))

            VStack(spacing: UIConstants.Spacing.small) {
                CreateDeckCardContextMenuActionRow(
                    title: "Edit Card",
                    icon: "pencil",
                    tint: .primary,
                    iconBackground: Color.primary.opacity(0.07),
                    accessibilityLabel: "Edit Card",
                    action: onEdit
                )

                CreateDeckCardContextMenuActionRow(
                    title: isPinned ? "Unpin Card" : "Pin Card",
                    icon: isPinned ? "pin.slash.fill" : "pin.fill",
                    tint: isPinned ? .orange : tint,
                    iconBackground: (isPinned ? Color.orange : tint).opacity(isPinned ? 0.20 : 0.14),
                    accessibilityLabel: isPinned ? "Unpin Card" : "Pin Card",
                    action: onTogglePin
                )

                CreateDeckCardContextMenuActionRow(
                    title: "Delete Card",
                    icon: "trash",
                    tint: .red,
                    iconBackground: Color.red.opacity(0.16),
                    isDestructive: true,
                    accessibilityLabel: "Delete Card",
                    action: onDelete
                )
            }
        }
        .padding(UIConstants.Spacing.medium)
        .frame(width: UIConstants.Size.floatingContextMenuWidth, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    Color.libraryDeckRow
                        .shadow(.inner(color: Color.white.opacity(0.12), radius: 1, x: 0, y: 0))
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.85)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
    }
}

private struct CreateDeckCardContextMenuActionRow: View {
    let title: String
    let icon: String
    let tint: Color
    let iconBackground: Color
    var isDestructive: Bool = false
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: UIConstants.Spacing.medium) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(iconBackground)

                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 36, height: 36)

                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(isDestructive ? .red : .primary)

                Spacer(minLength: UIConstants.Spacing.small)
            }
            .padding(.horizontal, UIConstants.Spacing.medium - 2)
            .padding(.vertical, UIConstants.Spacing.small + 2)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

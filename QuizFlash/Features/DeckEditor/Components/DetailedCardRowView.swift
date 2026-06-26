//
//  DetailedCardRowView.swift
//  QuizFlash
//
//  Rich draft-card preview used by the deck editor list.
//

import SwiftUI

struct DetailedCardRowView: View, Equatable {
    @Environment(AppPreferences.self) private var appPreferences
    let card: DraftCard
    var index: Int
    var fixedHeight: CGFloat? = nil
    var isSelecting: Bool = false
    var isSelected: Bool = false

    var onPrimaryTap: (() -> Void)? = nil
    var onToggleSelection: (() -> Void)? = nil

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var isCompactPreview: Bool { fixedHeight != nil }
    private var displayCardNumber: Int { card.cardNumber > 0 ? card.cardNumber : index }
    private var locale: Locale { appPreferences.resolvedLocale }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private func localizedFormat(_ value: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = AppLocalization.string(value, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    static func == (lhs: DetailedCardRowView, rhs: DetailedCardRowView) -> Bool {
        lhs.card == rhs.card
            && lhs.index == rhs.index
            && lhs.fixedHeight == rhs.fixedHeight
            && lhs.isSelecting == rhs.isSelecting
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Group {
            if let fixedHeight {
                cardContent
                    .padding(.vertical, 10)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: fixedHeight,
                        maxHeight: fixedHeight,
                        alignment: .topLeading
                    )
            } else {
                cardContent
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .scaleEffect(isSelected ? 0.9 : 1, anchor: .center)
        .animation(.spring(response: 0.46, dampingFraction: 0.8, blendDuration: 0.08), value: isCompactPreview)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            handlePrimaryTap()
        }
    }

    private func handlePrimaryTap() {
        if isSelecting {
            onToggleSelection?()
        } else {
            onPrimaryTap?()
        }
    }

    private var cardContent: some View {
        let summary = DraftCardContentSummary(card: card)

        return previewSurface(summary: summary)
    }

    private func previewSurface(summary: DraftCardContentSummary) -> some View {
        let panels = previewPanels(summary: summary)

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(panels.enumerated()), id: \.offset) { index, panel in
                if index > 0 {
                    separator
                        .padding(.horizontal, isCompactPreview ? 12 : 14)
                }

                previewBlock(
                    text: panel.text,
                    hasContent: panel.hasContent,
                    lineLimit: panel.lineLimit,
                    reservesCardNumberSpace: index == 0
                )
            }
        }
        .duoSurface(cornerRadius: 26)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(accent.opacity(0.70), lineWidth: 1.4)
            }
        }
        .overlay(alignment: .topTrailing) {
            cardNumberBadge
                .padding(.top, isCompactPreview ? 8 : 10)
                .padding(.trailing, isCompactPreview ? 8 : 10)
        }
    }

    private func previewBlock(
        text: String,
        hasContent: Bool,
        lineLimit: Int,
        reservesCardNumberSpace: Bool = false
    ) -> some View {
        Text(text)
            .font(
                isCompactPreview
                    ? .system(size: 15, weight: .medium, design: .rounded)
                    : .system(size: 17, weight: .medium, design: .rounded)
            )
            .foregroundStyle(hasContent ? .primary : .secondary)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: !isCompactPreview)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, isCompactPreview ? 12 : 14)
        .padding(.trailing, reservesCardNumberSpace ? (isCompactPreview ? 48 : 54) : (isCompactPreview ? 12 : 14))
        .padding(.vertical, isCompactPreview ? 10 : 12)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }

    private var cardNumberBadge: some View {
        Text("\(displayCardNumber)")
            .font(.system(size: isCompactPreview ? 12 : 13, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(isSelected ? accent : .secondary)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, isCompactPreview ? 8 : 9)
            .frame(minWidth: isCompactPreview ? 28 : 30, minHeight: isCompactPreview ? 24 : 26)
            .duoMetricPill(tint: isSelected ? accent : nil)
            .accessibilityLabel(localizedFormat("Card %d", displayCardNumber))
    }

    private func previewPanels(summary: DraftCardContentSummary) -> [PreviewPanel] {
        switch card.content {
        case .flashcard(let content):
            return [
                PreviewPanel(
                    text: previewText(for: content.frontZone, maxLength: isCompactPreview ? 180 : 360),
                    hasContent: summary.sections[safe: 0]?.metrics.hasContent ?? false,
                    lineLimit: isCompactPreview ? 3 : 3
                ),
                PreviewPanel(
                    text: previewText(for: content.backZone, maxLength: isCompactPreview ? 220 : 460),
                    hasContent: summary.sections[safe: 1]?.metrics.hasContent ?? false,
                    lineLimit: isCompactPreview ? 4 : 4
                )
            ]
        case .quiz(let content):
            var panels = [
                PreviewPanel(
                    text: previewText(for: content.questionZone, maxLength: isCompactPreview ? 160 : 320),
                    hasContent: summary.sections.first?.metrics.hasContent ?? false,
                    lineLimit: isCompactPreview ? 2 : 3
                ),
                PreviewPanel(
                    text: joinedChoicePreview(for: content),
                    hasContent: !content.choices.isEmpty,
                    lineLimit: isCompactPreview ? 3 : 4
                )
            ]

            if let explanationZone = content.explanationZone {
                panels.append(
                    PreviewPanel(
                        text: previewText(for: explanationZone, maxLength: isCompactPreview ? 120 : 260),
                        hasContent: !previewFragments(in: explanationZone).isEmpty,
                        lineLimit: isCompactPreview ? 2 : 3
                    )
                )
            }

            return panels
        }
    }

    private func joinedChoicePreview(for content: QuizCardContent) -> String {
        let choices = content.choices.enumerated().map { index, choice in
            let prefix = choice.isCorrect ? "\(index + 1).* " : "\(index + 1). "
            return prefix + previewText(for: choice.contentZone, maxLength: isCompactPreview ? 70 : 120)
        }

        let joined = choices.joined(separator: isCompactPreview ? " • " : "\n")
        return joined.isEmpty ? localized("No choices added") : joined
    }

    private func previewText(for zone: ZoneModel, maxLength: Int) -> String {
        let separator = isCompactPreview ? " • " : "\n\n"
        let combined = previewFragments(in: zone).joined(separator: separator)
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return localized("No content added") }
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
                        return [localizedFormat("%@ code", language)]
                    }
                    return [localized("Code")]
                }

                let joined = fragments.joined(separator: " ")
                if let language = zone.codeLanguage?.uppercased() {
                    return [localizedFormat("%@ code: %@", language, joined)]
                }
                return [localizedFormat("Code: %@", joined)]
            case .image:
                return zone.imageData == nil ? [] : [localized("Image")]
            case .sketch:
                return zone.imageData == nil ? [] : [localized("Sketch")]
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

    private func normalizedSingleLine(_ text: String, fallback: String) -> String {
        let trimmed = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(isCompactPreview ? 160 : 260))
    }
}

private struct PreviewPanel {
    let text: String
    let hasContent: Bool
    let lineLimit: Int
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

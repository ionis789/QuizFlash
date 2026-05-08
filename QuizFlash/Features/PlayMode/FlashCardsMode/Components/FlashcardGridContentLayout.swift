//
//  FlashcardGridContentLayout.swift
//  QuizFlash
//
//  Layout helpers for the centered flashcard text-block alignment used by
//  flashcard play mode.
//

import Foundation
import SwiftUI

// MARK: - Flashcard Grid Layout Debug

struct FlashcardGridLayoutDebugSnapshot: Equatable {
    let face: String
    let containerSize: CGSize
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let availableContentSize: CGSize
    let estimatedContentSize: CGSize
    let measuredContentSize: CGSize
    let contentBodyHeight: CGFloat
    let contentFitsVertically: Bool
    let centeredTopInset: CGFloat
    let scrollContentHeight: CGFloat
    let leafSnapshots: [FlashcardGridLeafLayoutDebugSnapshot]
}

struct FlashcardGridLeafLayoutDebugSnapshot: Equatable {
    let path: String
    let zoneID: UUID
    let contentType: ZoneContentType
    let hasContent: Bool
    let availableWidth: CGFloat
    let estimatedSize: CGSize
    let renderedContentSize: CGSize
    let blockSize: CGSize
    let leadingInset: CGFloat
    let contentLayoutWidth: CGFloat
    let textWidthLimit: CGFloat?
    let textHorizontalInsets: CGFloat
    let bulletHorizontalInset: CGFloat
    let usesIntrinsicTextMeasurement: Bool
    let zoneSizeMode: ZoneSizeMode
    let zoneBlockAlignment: ZoneBlockAlignment
    let zoneTextAlignment: TextBlockAlignment
    let usesNaturalBlockCentering: Bool
    let textStyle: TextBlockStyle
    let fontFamily: FontFamily
    let isBold: Bool
    let isItalic: Bool
    let hasBullet: Bool
    let highlightColor: HighlightColor
    let containsMath: Bool
    let containsInlineCode: Bool
    let textCharacterCount: Int
    let textLineCount: Int
    let estimatedLineWidths: [CGFloat]
    let renderedLineTexts: [String]
    let renderedLineWidths: [CGFloat]
    let textPreview: String
    let fullText: String
}

struct FlashcardGridLeafDebugPreferenceKey: PreferenceKey {
    static var defaultValue: [FlashcardGridLeafLayoutDebugSnapshot] { [] }

    static func reduce(
        value: inout [FlashcardGridLeafLayoutDebugSnapshot],
        nextValue: () -> [FlashcardGridLeafLayoutDebugSnapshot]
    ) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - Flashcard Grid Content Layout

struct FlashcardGridContentLayout {
    let containerSize: CGSize
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let estimatedContentSize: CGSize
    let measuredContentSize: CGSize
    let verticalAlignment: ZoneVerticalAlignment

    var availableContentWidth: CGFloat {
        max(containerSize.width - (horizontalPadding * 2), 1)
    }

    var availableContentHeight: CGFloat {
        max(containerSize.height - (verticalPadding * 2), 1)
    }

    var contentBodyHeight: CGFloat {
        if measuredContentSize.height > 0 {
            return ceil(measuredContentSize.height)
        }

        return max(ceil(estimatedContentSize.height), 1)
    }

    var contentFitsVertically: Bool {
        contentBodyHeight + (verticalPadding * 2) <= containerSize.height
    }

    var centeredTopInset: CGFloat {
        guard effectiveVerticalAlignment == .center else { return 0 }
        return contentTopInset
    }

    var contentTopInset: CGFloat {
        guard contentFitsVertically else { return 0 }
        let extraHeight = max(availableContentHeight - contentBodyHeight, 0)
        switch effectiveVerticalAlignment {
        case .auto, .top:
            return 0
        case .center:
            return extraHeight / 2
        case .bottom:
            return extraHeight
        }
    }

    var contentBottomInset: CGFloat {
        guard contentFitsVertically else { return 0 }
        let extraHeight = max(availableContentHeight - contentBodyHeight, 0)
        switch effectiveVerticalAlignment {
        case .auto, .top:
            return extraHeight
        case .center:
            return extraHeight / 2
        case .bottom:
            return 0
        }
    }

    var scrollContentHeight: CGFloat {
        max(
            containerSize.height,
            verticalPadding + contentTopInset + contentBodyHeight + verticalPadding + contentBottomInset
        )
    }

    var debugAvailableFrame: CGSize {
        CGSize(width: availableContentWidth, height: availableContentHeight)
    }

    private var effectiveVerticalAlignment: ZoneVerticalAlignment {
        verticalAlignment.resolved(fallback: .center)
    }
}

// MARK: - Flashcard Grid Face View

struct FlashcardGridFaceView: View {
    let zone: ZoneModel
    let fontScale: CGFloat
    let availableWidth: CGFloat
    let centersLeafBlocks: Bool
    let showsDebugGuides: Bool
    let collectsDebugMetrics: Bool
    var onTap: (() -> Void)?

    var body: some View {
        FlashcardGridZonePreview(
            zone: zone,
            path: "root",
            fontScale: fontScale,
            availableWidth: max(availableWidth, 1),
            centersLeafBlocks: centersLeafBlocks,
            showsDebugGuides: showsDebugGuides,
            collectsDebugMetrics: collectsDebugMetrics,
            onTap: onTap
        )
        .frame(width: max(availableWidth, 1), alignment: .topLeading)
    }
}

// MARK: - Flashcard Grid Zone Preview

private struct FlashcardGridZonePreview: View {
    let zone: ZoneModel
    let path: String
    let fontScale: CGFloat
    let availableWidth: CGFloat
    let centersLeafBlocks: Bool
    let showsDebugGuides: Bool
    let collectsDebugMetrics: Bool
    var onTap: (() -> Void)?

    var body: some View {
        if zone.isLeaf {
            FlashcardGridLeafPreview(
                zone: zone,
                path: path,
                fontScale: fontScale,
                availableWidth: availableWidth,
                centersLeafBlocks: centersLeafBlocks,
                showsDebugGuides: showsDebugGuides,
                collectsDebugMetrics: collectsDebugMetrics,
                onTap: onTap
            )
        } else {
            containerPreview
        }
    }

    @ViewBuilder
    private var containerPreview: some View {
        let children = zone.children?.filter(\.hasContent) ?? []

        if children.isEmpty {
            Color.clear.frame(width: availableWidth, height: 1)
        } else if zone.direction == .horizontal {
            let spacingTotal = CGFloat(max(children.count - 1, 0)) * FlashcardGridContentMetrics.childSpacing
            let childWidth = max((availableWidth - spacingTotal) / CGFloat(max(children.count, 1)), 1)

            HStack(alignment: .top, spacing: FlashcardGridContentMetrics.childSpacing) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                    FlashcardGridZonePreview(
                        zone: child,
                        path: "\(path).\(index)",
                        fontScale: fontScale,
                        availableWidth: childWidth,
                        centersLeafBlocks: centersLeafBlocks,
                        showsDebugGuides: showsDebugGuides,
                        collectsDebugMetrics: collectsDebugMetrics,
                        onTap: onTap
                    )
                    .frame(width: childWidth, alignment: .topLeading)
                }
            }
            .frame(width: availableWidth, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: FlashcardGridContentMetrics.childSpacing) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                    FlashcardGridZonePreview(
                        zone: child,
                        path: "\(path).\(index)",
                        fontScale: fontScale,
                        availableWidth: availableWidth,
                        centersLeafBlocks: centersLeafBlocks,
                        showsDebugGuides: showsDebugGuides,
                        collectsDebugMetrics: collectsDebugMetrics,
                        onTap: onTap
                    )
                    .frame(width: availableWidth, alignment: .topLeading)
                }
            }
            .frame(width: availableWidth, alignment: .topLeading)
        }
    }
}

// MARK: - Flashcard Grid Leaf Preview

private struct FlashcardGridLeafPreview: View {
    let zone: ZoneModel
    let path: String
    let fontScale: CGFloat
    let availableWidth: CGFloat
    let centersLeafBlocks: Bool
    let showsDebugGuides: Bool
    let collectsDebugMetrics: Bool
    var onTap: (() -> Void)?

    @State private var renderedContentSize: CGSize = .zero

    var body: some View {
        let layout = CardZoneLayoutEngine.leafLayout(
            for: zone,
            spec: CardZoneLayoutSpec(
                availableWidth: availableWidth,
                fontScale: fontScale
            ),
            measuredContentSize: renderedContentSize
        )

        ZStack(alignment: .topLeading) {
            if showsDebugGuides {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        Color.orange.opacity(0.95),
                        style: StrokeStyle(lineWidth: 1.6, dash: [5, 4])
                    )
                    .frame(width: layout.blockSize.width, height: layout.blockSize.height)
                    .offset(x: layout.leadingInset)
                    .allowsHitTesting(false)
            }

            leafContent(layout: layout)
                .frame(width: layout.contentLayoutWidth, alignment: .topLeading)
                .offset(x: layout.leadingInset)
                .onGeometryChange(for: CGSize.self) { proxy in
                    CGSize(width: ceil(proxy.size.width), height: ceil(proxy.size.height))
                } action: { newSize in
                    if layout.usesIntrinsicTextMeasurement {
                        updateRenderedContentHeight(newSize.height)
                    } else {
                        updateRenderedContentSize(newSize)
                    }
                }
        }
        .frame(width: availableWidth, height: layout.blockSize.height, alignment: .topLeading)
        .preference(
            key: FlashcardGridLeafDebugPreferenceKey.self,
            value: collectsDebugMetrics
                ? [debugSnapshot(layout: layout)]
                : []
        )
    }

    @ViewBuilder
    private func leafContent(layout: CardZoneLayoutResult) -> some View {
        switch zone.contentType {
        case .empty:
            Color.clear.frame(height: 28).padding(.vertical, 4)

        case .text, .code:
            let previewText = displayText(for: zone)
            if !previewText.isEmpty {
                if zone.contentType == .code || previewText.hasPrefix("```") {
                    CodeSnippetView(rawText: previewText)
                        .padding(.vertical, 4)
                } else {
                    textLeafContent(
                        previewText,
                        layout: layout
                    )
                }
            }

        case .image:
            if let data = zone.imageData {
                CachedImageView(
                    data: data,
                    scale: zone.imageScale,
                    alignment: .leading,
                    cornerRadius: 10
                )
            }

        case .sketch:
            if let data = zone.imageData {
                CachedImageView(
                    data: data,
                    scale: zone.imageScale,
                    alignment: .leading,
                    cornerRadius: 10,
                    isSketch: true
                )
            }
        }
    }

    private func textLeafContent(
        _ previewText: String,
        layout: CardZoneLayoutResult
    ) -> some View {
        let healedText = MathTextSanitizer.heal(previewText)
        let usesMathRenderer = MathTextSanitizer.containsMath(healedText)
            || MathTextSanitizer.containsInlineCode(healedText)
        let textWidthLimit = layout.textWidthLimit ?? max(layout.contentLayoutWidth, 1)

        return HStack(alignment: .top, spacing: zone.hasBullet ? FlashcardGridContentMetrics.bulletSpacing : 0) {
            if zone.hasBullet {
                Circle()
                    .fill(zone.textColor.color)
                    .frame(
                        width: FlashcardGridContentMetrics.bulletWidth,
                        height: FlashcardGridContentMetrics.bulletWidth
                    )
                    .padding(.top, 8)
            }

            if usesMathRenderer {
                MixedMathTextView(
                    text: previewText,
                    fontSize: fontSizeFor(zone),
                    textColor: zone.textColor.color,
                    alignment: layout.resolvedTextAlignment.horizontalAlignment,
                    isBold: zone.isBold,
                    isItalic: zone.isItalic,
                    isInteractive: false,
                    allowsReadOnlyOverflowScrolling: true,
                    intrinsicWidthLimit: textWidthLimit,
                    onIntrinsicContentSizeChange: { size in
                        updateRenderedContentSize(
                            CGSize(
                                width: ceil(size.width + layout.textHorizontalInsets + layout.bulletHorizontalInset),
                                height: ceil(size.height + FlashcardGridContentMetrics.textVerticalPadding)
                            )
                        )
                    },
                    onTap: onTap
                )
                .padding(.vertical, FlashcardGridContentMetrics.textVerticalPadding / 2)
                .padding(.horizontal, layout.textHorizontalInsets / 2)
                .background(
                    zone.highlightColor.color.map { color in
                        RoundedRectangle(cornerRadius: 4).fill(color)
                    }
                )
            } else {
                FlashcardPlainTextBlockView(
                    text: healedText,
                    zone: zone,
                    fontScale: fontScale,
                    availableWidth: textWidthLimit,
                    textAlignment: layout.resolvedTextAlignment,
                    onIntrinsicContentSizeChange: { size in
                        updateRenderedContentSize(
                            CGSize(
                                width: ceil(size.width + layout.textHorizontalInsets + layout.bulletHorizontalInset),
                                height: ceil(size.height + FlashcardGridContentMetrics.textVerticalPadding)
                            )
                        )
                    },
                    onTap: onTap
                )
                .padding(.vertical, FlashcardGridContentMetrics.textVerticalPadding / 2)
                .padding(.horizontal, layout.textHorizontalInsets / 2)
                .background(
                    zone.highlightColor.color.map { color in
                        RoundedRectangle(cornerRadius: 4).fill(color)
                    }
                )
            }
        }
        .frame(width: layout.contentLayoutWidth, alignment: .topLeading)
    }

    private func updateRenderedContentSize(_ newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        let clampedSize = CGSize(
            width: min(max(ceil(newSize.width), 1), availableWidth),
            height: max(ceil(newSize.height), 1)
        )

        if abs(renderedContentSize.width - clampedSize.width) > 0.5
            || abs(renderedContentSize.height - clampedSize.height) > 0.5 {
            renderedContentSize = clampedSize
        }
    }

    private func updateRenderedContentHeight(_ newHeight: CGFloat) {
        guard newHeight > 0 else { return }
        let clampedHeight = max(ceil(newHeight), 1)
        if abs(renderedContentSize.height - clampedHeight) > 0.5 {
            renderedContentSize = CGSize(
                width: renderedContentSize.width,
                height: clampedHeight
            )
        }
    }

    private func debugSnapshot(layout: CardZoneLayoutResult) -> FlashcardGridLeafLayoutDebugSnapshot {
        let displayText = zone.contentType == .text ? displayText(for: zone) : zone.text
        let healedText = MathTextSanitizer.heal(displayText)
        let containsMath = MathTextSanitizer.containsMath(healedText)
        let containsInlineCode = MathTextSanitizer.containsInlineCode(healedText)
        let effectiveTextWidthLimit = layout.textWidthLimit ?? max(layout.contentLayoutWidth, 1)
        let estimatedLineWidths = zone.contentType == .text
            ? FlashcardGridContentEstimator.debugLineWidths(
                for: zone,
                fontScale: fontScale,
                availableWidth: effectiveTextWidthLimit
            )
            : []
        let renderedLineLayout = zone.contentType == .text && !containsMath && !containsInlineCode
            ? FlashcardPlainTextLayoutMeasurer.layout(
                text: healedText,
                zone: zone,
                fontScale: fontScale,
                availableWidth: effectiveTextWidthLimit
            )
            : .empty

        return FlashcardGridLeafLayoutDebugSnapshot(
            path: path,
            zoneID: zone.id,
            contentType: zone.contentType,
            hasContent: zone.hasContent,
            availableWidth: ceil(availableWidth),
            estimatedSize: layout.estimatedContentSize,
            renderedContentSize: roundedSize(renderedContentSize),
            blockSize: layout.blockSize,
            leadingInset: layout.leadingInset,
            contentLayoutWidth: layout.contentLayoutWidth,
            textWidthLimit: layout.textWidthLimit,
            textHorizontalInsets: layout.textHorizontalInsets,
            bulletHorizontalInset: layout.bulletHorizontalInset,
            usesIntrinsicTextMeasurement: layout.usesIntrinsicTextMeasurement,
            zoneSizeMode: zone.sizeMode,
            zoneBlockAlignment: zone.blockAlignment,
            zoneTextAlignment: zone.textAlignment,
            usesNaturalBlockCentering: layout.usesAutoBlockCentering,
            textStyle: zone.textStyle,
            fontFamily: zone.fontFamily,
            isBold: zone.isBold,
            isItalic: zone.isItalic,
            hasBullet: zone.hasBullet,
            highlightColor: zone.highlightColor,
            containsMath: containsMath,
            containsInlineCode: containsInlineCode,
            textCharacterCount: displayText.count,
            textLineCount: max(displayText.components(separatedBy: .newlines).count, 1),
            estimatedLineWidths: estimatedLineWidths.map(ceil),
            renderedLineTexts: renderedLineLayout.lines.map(\.plainText),
            renderedLineWidths: renderedLineLayout.lines.map { ceil($0.width) },
            textPreview: Self.preview(displayText),
            fullText: displayText
        )
    }

    private func roundedSize(_ size: CGSize) -> CGSize {
        CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    private static func preview(_ value: String) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 160 else { return collapsed }
        return String(collapsed.prefix(160)) + "..."
    }

    private func displayText(for zone: ZoneModel) -> String {
        switch zone.contentType {
        case .text:
            return MathTextSanitizer.stripTerminalZonePeriod(zone.text)
        default:
            return zone.text
        }
    }

    private func fontSizeFor(_ zone: ZoneModel) -> CGFloat {
        switch zone.textStyle {
        case .caption: return 16 * fontScale
        case .body: return 22 * fontScale
        case .headline: return 26 * fontScale
        case .title: return 32 * fontScale
        }
    }
}

// MARK: - Card Zone Content Metrics

enum CardZoneContentMetrics {
    static let childSpacing: CGFloat = 12
    static let textVerticalPadding: CGFloat = 8
    static let highlightedHorizontalPadding: CGFloat = 12
    static let bulletWidth: CGFloat = 6
    static let bulletSpacing: CGFloat = 8
}

typealias FlashcardGridContentMetrics = CardZoneContentMetrics

// MARK: - Plain Text Grid Layout

private struct FlashcardPlainTextBlockView: View {
    let text: String
    let zone: ZoneModel
    let fontScale: CGFloat
    let availableWidth: CGFloat
    let textAlignment: TextBlockAlignment
    var onIntrinsicContentSizeChange: ((CGSize) -> Void)?
    var onTap: (() -> Void)?

    private var layout: FlashcardPlainTextLineLayout {
        FlashcardPlainTextLayoutMeasurer.layout(
            text: text,
            zone: zone,
            fontScale: fontScale,
            availableWidth: availableWidth
        )
    }

    var body: some View {
        VStack(alignment: textAlignment.horizontalAlignment, spacing: layout.lineSpacing) {
            ForEach(Array(layout.lines.enumerated()), id: \.offset) { _, line in
                line.textView(defaultColor: zone.textColor.color)
                    .frame(width: line.width, alignment: .leading)
            }
        }
        .frame(width: max(availableWidth, layout.size.width), alignment: frameAlignment)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .onAppear {
            onIntrinsicContentSizeChange?(layout.size)
        }
        .onChange(of: layout.size) { _, newSize in
            onIntrinsicContentSizeChange?(newSize)
        }
    }

    private var frameAlignment: Alignment {
        switch textAlignment {
        case .leading:
            return .topLeading
        case .center:
            return .top
        case .trailing:
            return .topTrailing
        }
    }
}

private enum FlashcardPlainTextLayoutMeasurer {
    static func layout(
        text rawText: String,
        zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> FlashcardPlainTextLineLayout {
        let text = MathTextSanitizer.heal(rawText.trimmingCharacters(in: .whitespacesAndNewlines))
        let widthLimit = max(availableWidth, 1)
        let lineSpacing = max(floor(fontSize(for: zone) * fontScale * 0.26), 6)

        guard !text.isEmpty else {
            let emptyLine = FlashcardPlainTextLine(tokens: [], width: 1, height: lineHeight(for: zone, fontScale: fontScale))
            return FlashcardPlainTextLineLayout(lines: [emptyLine], lineSpacing: lineSpacing)
        }

        let sourceLines = text.components(separatedBy: .newlines)
        var output: [FlashcardPlainTextLine] = []

        for sourceLine in sourceLines {
            let tokens = tokens(for: sourceLine, zone: zone, fontScale: fontScale)
            guard !tokens.isEmpty else {
                output.append(FlashcardPlainTextLine(tokens: [], width: 1, height: lineHeight(for: zone, fontScale: fontScale)))
                continue
            }

            var current: [FlashcardPlainTextToken] = []
            for token in tokens {
                var remainingToken = token

                while !remainingToken.isEmpty {
                    let nextToken = current.isEmpty
                        ? remainingToken.trimmedLeadingWhitespace()
                        : remainingToken

                    guard !nextToken.isEmpty else { break }

                    let candidate = current.isEmpty
                        ? [nextToken]
                        : current + [nextToken]
                    let candidateWidth = measuredWidth(for: normalizedLineTokens(candidate))

                    if !current.isEmpty, candidateWidth > widthLimit {
                        output.append(line(from: current, zone: zone, fontScale: fontScale))
                        current = []
                        continue
                    }

                    if current.isEmpty, candidateWidth > widthLimit {
                        let split = splitOversizedToken(nextToken, widthLimit: widthLimit)
                        output.append(line(from: [split.lineToken], zone: zone, fontScale: fontScale))
                        remainingToken = split.remainingToken
                        continue
                    }

                    current = candidate
                    break
                }
            }

            if !current.isEmpty {
                output.append(line(from: current, zone: zone, fontScale: fontScale))
            }
        }

        if output.isEmpty {
            output.append(FlashcardPlainTextLine(tokens: [], width: 1, height: lineHeight(for: zone, fontScale: fontScale)))
        }

        return FlashcardPlainTextLineLayout(lines: output, lineSpacing: lineSpacing)
    }

    private static func tokens(
        for text: String,
        zone: ZoneModel,
        fontScale: CGFloat
    ) -> [FlashcardPlainTextToken] {
        var tokens: [FlashcardPlainTextToken] = []
        var cursor = text.startIndex
        var isEmphasized = false

        func appendToken(_ value: String, emphasized: Bool) {
            guard !value.isEmpty else { return }
            let attributes = attributes(for: zone, fontScale: fontScale, emphasized: emphasized)
            tokens.append(
                FlashcardPlainTextToken(
                    text: value,
                    attributes: attributes,
                    font: swiftUIFont(
                        for: zone,
                        fontScale: fontScale,
                        weight: swiftUIFontWeight(for: zone, emphasized: emphasized)
                    ),
                    isItalic: zone.isItalic,
                    emphasized: emphasized
                )
            )
        }

        while cursor < text.endIndex {
            if text[cursor...].hasPrefix("**") {
                isEmphasized.toggle()
                cursor = text.index(cursor, offsetBy: 2)
                continue
            }

            let nextMarkdown = text[cursor...].range(of: "**")?.lowerBound ?? text.endIndex
            let run = String(text[cursor..<nextMarkdown])
            splitRun(run).forEach { appendToken($0, emphasized: isEmphasized) }
            cursor = nextMarkdown
        }

        return tokens
    }

    private static func splitRun(_ run: String) -> [String] {
        guard !run.isEmpty else { return [] }
        var result: [String] = []
        var current = ""
        var previousWasWhitespace = false

        for character in run {
            let isWhitespace = character.isWhitespace
            if !current.isEmpty, !isWhitespace, previousWasWhitespace {
                result.append(current)
                current = ""
            }
            current.append(character)
            previousWasWhitespace = isWhitespace
        }

        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private static func normalizedLineTokens(_ tokens: [FlashcardPlainTextToken]) -> [FlashcardPlainTextToken] {
        guard let firstIndex = tokens.firstIndex(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return []
        }

        var normalized = Array(tokens[firstIndex...])
        normalized[0] = normalized[0].trimmedLeadingWhitespace()

        if let lastIndex = normalized.lastIndex(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }) {
            normalized = Array(normalized[...lastIndex])
            normalized[normalized.count - 1] = normalized[normalized.count - 1].trimmedTrailingWhitespace()
        }

        return normalized.filter { !$0.text.isEmpty }
    }

    private static func splitOversizedToken(
        _ token: FlashcardPlainTextToken,
        widthLimit: CGFloat
    ) -> (lineToken: FlashcardPlainTextToken, remainingToken: FlashcardPlainTextToken) {
        guard !token.text.isEmpty else {
            return (token, token)
        }

        let start = token.text.startIndex
        var candidateEnd = start
        var bestEnd = start

        while candidateEnd < token.text.endIndex {
            let nextEnd = token.text.index(after: candidateEnd)
            let candidateText = String(token.text[start..<nextEnd])
            let candidateWidth = measuredWidth(for: [token.replacingText(candidateText)])

            if candidateWidth <= widthLimit || bestEnd == start {
                bestEnd = nextEnd
                candidateEnd = nextEnd
            } else {
                break
            }
        }

        let lineText = String(token.text[start..<bestEnd])
        let remainingText = String(token.text[bestEnd...])

        return (
            token.replacingText(lineText),
            token.replacingText(remainingText)
        )
    }

    private static func line(
        from tokens: [FlashcardPlainTextToken],
        zone: ZoneModel,
        fontScale: CGFloat
    ) -> FlashcardPlainTextLine {
        let normalized = normalizedLineTokens(tokens)
        return FlashcardPlainTextLine(
            tokens: normalized,
            width: min(max(ceil(measuredWidth(for: normalized)), 1), .greatestFiniteMagnitude),
            height: lineHeight(for: zone, fontScale: fontScale)
        )
    }

    private static func measuredWidth(for tokens: [FlashcardPlainTextToken]) -> CGFloat {
        guard !tokens.isEmpty else { return 1 }
        let attributed = NSMutableAttributedString()
        tokens.forEach {
            attributed.append(NSAttributedString(string: $0.text, attributes: $0.attributes))
        }
        return ceil(attributed.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).width)
    }

    private static func attributes(
        for zone: ZoneModel,
        fontScale: CGFloat,
        emphasized: Bool
    ) -> [NSAttributedString.Key: Any] {
        let weight = fontWeight(for: zone, emphasized: emphasized)
        return [
            .font: uiFont(for: zone, fontScale: fontScale, weight: weight)
        ]
    }

    private static func lineHeight(for zone: ZoneModel, fontScale: CGFloat) -> CGFloat {
        ceil(uiFont(for: zone, fontScale: fontScale, weight: fontWeight(for: zone, emphasized: false)).lineHeight)
    }

    private static func uiFont(
        for zone: ZoneModel,
        fontScale: CGFloat,
        weight: UIFont.Weight
    ) -> UIFont {
        let size = fontSize(for: zone) * fontScale
        let baseFont = zone.fontFamily.uiFont(size: size, weight: weight)

        guard zone.isItalic,
              let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic)
        else {
            return baseFont
        }

        return UIFont(descriptor: descriptor, size: size)
    }

    private static func swiftUIFont(
        for zone: ZoneModel,
        fontScale: CGFloat,
        weight: Font.Weight
    ) -> Font {
        zone.fontFamily.font(size: fontSize(for: zone) * fontScale, weight: weight)
    }

    private static func fontWeight(for zone: ZoneModel, emphasized: Bool) -> UIFont.Weight {
        if zone.isBold || emphasized {
            return .bold
        }

        switch zone.textStyle {
        case .title:
            return .bold
        case .headline:
            return .semibold
        case .body, .caption:
            return .regular
        }
    }

    private static func swiftUIFontWeight(for zone: ZoneModel, emphasized: Bool) -> Font.Weight {
        if zone.isBold || emphasized {
            return .bold
        }

        switch zone.textStyle {
        case .title:
            return .bold
        case .headline:
            return .semibold
        case .body, .caption:
            return .regular
        }
    }

    private static func fontSize(for zone: ZoneModel) -> CGFloat {
        switch zone.textStyle {
        case .caption: return 16
        case .body: return 22
        case .headline: return 26
        case .title: return 32
        }
    }
}

private struct FlashcardPlainTextLineLayout: Equatable {
    let lines: [FlashcardPlainTextLine]
    let lineSpacing: CGFloat

    static let empty = FlashcardPlainTextLineLayout(lines: [], lineSpacing: 0)

    var size: CGSize {
        let widest = lines.map(\.width).max() ?? 1
        let totalLineHeight = lines.reduce(CGFloat(0)) { $0 + $1.height }
        let totalSpacing = CGFloat(max(lines.count - 1, 0)) * lineSpacing
        return CGSize(width: ceil(max(widest, 1)), height: ceil(max(totalLineHeight + totalSpacing, 1)))
    }
}

private struct FlashcardPlainTextLine: Equatable {
    let tokens: [FlashcardPlainTextToken]
    let width: CGFloat
    let height: CGFloat

    var plainText: String {
        tokens.map(\.text).joined()
    }

    func textView(defaultColor: Color) -> Text {
        guard !tokens.isEmpty else { return Text("") }

        return tokens.reduce(Text("")) { partial, token in
            partial + token.textView(defaultColor: defaultColor)
        }
    }
}

private struct FlashcardPlainTextToken: Equatable {
    let text: String
    let attributes: [NSAttributedString.Key: Any]
    let font: Font
    let isItalic: Bool
    let emphasized: Bool

    static func == (lhs: FlashcardPlainTextToken, rhs: FlashcardPlainTextToken) -> Bool {
        lhs.text == rhs.text && lhs.isItalic == rhs.isItalic && lhs.emphasized == rhs.emphasized
    }

    var isEmpty: Bool {
        text.isEmpty
    }

    func trimmedLeadingWhitespace() -> FlashcardPlainTextToken {
        replacingText(String(text.drop(while: \.isWhitespace)))
    }

    func trimmedTrailingWhitespace() -> FlashcardPlainTextToken {
        var value = text
        while let last = value.last, last.isWhitespace {
            value.removeLast()
        }
        return replacingText(value)
    }

    func textView(defaultColor: Color) -> Text {
        var textView = Text(displayText)
            .foregroundColor(defaultColor)
            .font(font)

        if emphasized {
            textView = textView.bold()
        }

        if isItalic {
            textView = textView.italic()
        }

        return textView
    }

    private var displayText: String {
        text.map { character in
            character == " " ? "\u{00A0}" : String(character)
        }
        .joined()
    }

    func replacingText(_ value: String) -> FlashcardPlainTextToken {
        FlashcardPlainTextToken(
            text: value,
            attributes: attributes,
            font: font,
            isItalic: isItalic,
            emphasized: emphasized
        )
    }
}

// MARK: - Flashcard Grid Content Estimator

enum FlashcardGridContentEstimator {
    private static let childSpacing = FlashcardGridContentMetrics.childSpacing
    private static let textVerticalPadding = FlashcardGridContentMetrics.textVerticalPadding
    private static let highlightedHorizontalPadding = FlashcardGridContentMetrics.highlightedHorizontalPadding
    private static let bulletWidth = FlashcardGridContentMetrics.bulletWidth
    private static let bulletSpacing = FlashcardGridContentMetrics.bulletSpacing

    static func estimatedSize(
        for zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> CGSize {
        let clampedWidth = max(availableWidth, 1)

        guard zone.hasContent else {
            return CGSize(width: 1, height: 36)
        }

        if zone.isLeaf {
            return estimatedLeafSize(
                for: zone,
                fontScale: fontScale,
                availableWidth: clampedWidth
            )
        }

        let children = zone.children?.filter(\.hasContent) ?? []
        guard !children.isEmpty else {
            return CGSize(width: 1, height: 36)
        }

        switch zone.direction {
        case .vertical:
            let childSizes = children.map {
                estimatedSize(for: $0, fontScale: fontScale, availableWidth: clampedWidth)
            }
            let totalHeight = childSizes.reduce(CGFloat(0)) { $0 + $1.height }
                + (CGFloat(max(children.count - 1, 0)) * childSpacing)
            let widestChild = childSizes.map(\.width).max() ?? 1

            return CGSize(
                width: min(ceil(widestChild), clampedWidth),
                height: ceil(totalHeight)
            )

        case .horizontal:
            let spacingTotal = CGFloat(max(children.count - 1, 0)) * childSpacing
            let childWidth = max((clampedWidth - spacingTotal) / CGFloat(max(children.count, 1)), 1)
            let childSizes = children.map {
                estimatedSize(for: $0, fontScale: fontScale, availableWidth: childWidth)
            }
            let totalWidth = childSizes.reduce(CGFloat(0)) { $0 + $1.width } + spacingTotal
            let tallestChild = childSizes.map(\.height).max() ?? 1

            return CGSize(
                width: min(ceil(totalWidth), clampedWidth),
                height: ceil(tallestChild)
            )
        }
    }

    static func debugLineWidths(
        for zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> [CGFloat] {
        let displayText = MathTextSanitizer.stripTerminalZonePeriod(zone.text)
        return measuredTextLayout(
            displayText,
            zone: zone,
            fontScale: fontScale,
            availableWidth: availableWidth
        )
        .lineWidths
    }

    private static func estimatedLeafSize(
        for zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> CGSize {
        switch zone.contentType {
        case .empty:
            return CGSize(width: 1, height: 36)

        case .text:
            let displayText = MathTextSanitizer.stripTerminalZonePeriod(zone.text)
            let horizontalInsets = zone.highlightColor != .none ? highlightedHorizontalPadding : 0
            let bulletInset = zone.hasBullet ? bulletWidth + bulletSpacing : 0
            let textWidth = max(availableWidth - horizontalInsets - bulletInset, 1)
            let textSize = measuredTextSize(
                displayText,
                zone: zone,
                fontScale: fontScale,
                availableWidth: textWidth
            )

            return CGSize(
                width: min(ceil(textSize.width + horizontalInsets + bulletInset), availableWidth),
                height: ceil(textSize.height + textVerticalPadding)
            )

        case .code:
            let codeSize = measuredTextSize(
                strippedCodeText(zone.text),
                zone: zone,
                fontScale: fontScale,
                availableWidth: availableWidth
            )

            return CGSize(
                width: availableWidth,
                height: ceil(codeSize.height + 32)
            )

        case .image, .sketch:
            let imageWidth = min(
                availableWidth,
                max(UIScreen.main.bounds.width * zone.imageScale * 0.85, 1)
            )
            return CGSize(width: imageWidth, height: imageWidth * 0.66)
        }
    }

    private static func measuredTextSize(
        _ rawText: String,
        zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> CGSize {
        let text = MathTextSanitizer.heal(rawText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !text.isEmpty else {
            let font = font(for: zone, fontScale: fontScale, emphasized: false, monospaced: false)
            return CGSize(width: 1, height: ceil(font.lineHeight))
        }

        return measuredTextLayout(
            text,
            zone: zone,
            fontScale: fontScale,
            availableWidth: availableWidth
        )
        .size
    }

    private static func measuredTextLayout(
        _ rawText: String,
        zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> TextLayoutMeasurement {
        let text = MathTextSanitizer.heal(rawText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !text.isEmpty else {
            let font = font(for: zone, fontScale: fontScale, emphasized: false, monospaced: false)
            return TextLayoutMeasurement(
                size: CGSize(width: 1, height: ceil(font.lineHeight)),
                lineWidths: [1]
            )
        }

        let lineLayout = FlashcardPlainTextLayoutMeasurer.layout(
            text: text,
            zone: zone,
            fontScale: fontScale,
            availableWidth: availableWidth
        )
        return TextLayoutMeasurement(
            size: lineLayout.size,
            lineWidths: lineLayout.lines.map(\.width)
        )
    }

    private struct TextLayoutMeasurement {
        let size: CGSize
        let lineWidths: [CGFloat]
    }

    private static func attributedString(
        for text: String,
        zone: ZoneModel,
        fontScale: CGFloat
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var plainBuffer = ""
        var cursor = text.startIndex

        func append(_ value: String, emphasized: Bool = false, monospaced: Bool = false) {
            guard !value.isEmpty else { return }
            result.append(
                NSAttributedString(
                    string: value,
                    attributes: attributes(
                        for: zone,
                        fontScale: fontScale,
                        emphasized: emphasized,
                        monospaced: monospaced
                    )
                )
            )
        }

        func flushPlainBuffer() {
            append(plainBuffer)
            plainBuffer.removeAll(keepingCapacity: true)
        }

        while cursor < text.endIndex {
            if text[cursor...].hasPrefix("**") {
                let contentStart = text.index(cursor, offsetBy: 2)
                if let closing = text[contentStart...].range(of: "**") {
                    flushPlainBuffer()
                    append(String(text[contentStart..<closing.lowerBound]), emphasized: true)
                    cursor = closing.upperBound
                    continue
                }
            }

            if text[cursor] == "`" {
                let contentStart = text.index(after: cursor)
                if let closing = text[contentStart...].firstIndex(of: "`") {
                    flushPlainBuffer()
                    append(String(text[contentStart..<closing]), monospaced: true)
                    cursor = text.index(after: closing)
                    continue
                }
            }

            plainBuffer.append(text[cursor])
            cursor = text.index(after: cursor)
        }

        flushPlainBuffer()
        return result
    }

    private static func attributes(
        for zone: ZoneModel,
        fontScale: CGFloat,
        emphasized: Bool,
        monospaced: Bool
    ) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byWordWrapping

        return [
            .font: font(
                for: zone,
                fontScale: fontScale,
                emphasized: emphasized,
                monospaced: monospaced
            ),
            .paragraphStyle: paragraphStyle
        ]
    }

    private static func font(
        for zone: ZoneModel,
        fontScale: CGFloat,
        emphasized: Bool,
        monospaced: Bool
    ) -> UIFont {
        let size = fontSize(for: zone) * fontScale
        let weight = fontWeight(for: zone, emphasized: emphasized)
        let baseFont = monospaced
            ? UIFont.monospacedSystemFont(ofSize: size, weight: weight)
            : zone.fontFamily.uiFont(size: size, weight: weight)

        guard zone.isItalic,
              let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic)
        else {
            return baseFont
        }

        return UIFont(descriptor: descriptor, size: size)
    }

    private static func fontWeight(for zone: ZoneModel, emphasized: Bool) -> UIFont.Weight {
        if zone.isBold || emphasized {
            return .bold
        }

        switch zone.textStyle {
        case .title:
            return .bold
        case .headline:
            return .semibold
        case .body, .caption:
            return .regular
        }
    }

    private static func fontSize(for zone: ZoneModel) -> CGFloat {
        switch zone.textStyle {
        case .caption: return 16
        case .body: return 22
        case .headline: return 26
        case .title: return 32
        }
    }

    private static func strippedCodeText(_ text: String) -> String {
        var stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard stripped.hasPrefix("```") else {
            return stripped
        }

        let lines = stripped.components(separatedBy: .newlines)
        stripped = lines.dropFirst().joined(separator: "\n")
        if stripped.hasSuffix("```") {
            stripped = String(stripped.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return stripped
    }
}

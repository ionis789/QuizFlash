//
//  FlashcardGridContentLayout.swift
//  QuizFlash
//
//  Layout helpers for the centered flashcard text-block alignment used by
//  flashcard play mode.
//

import Foundation
import SwiftUI
import UIKit

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
        let estimatedHeight = max(ceil(estimatedContentSize.height), 1)
        if measuredContentSize.height > 0 {
            return max(ceil(measuredContentSize.height), estimatedHeight)
        }

        return estimatedHeight
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
            alignLeafBlocksToGroupLeading: false,
            showsDebugGuides: showsDebugGuides,
            collectsDebugMetrics: collectsDebugMetrics,
            onTap: onTap
        )
        .frame(width: max(availableWidth, 1), alignment: .topLeading)
    }
}

// MARK: - Flashcard Grid Zone Preview

private enum FlashcardGridZoneRenderPolicy {
    nonisolated static func shouldRender(_ zone: ZoneModel) -> Bool {
        if zone.hasContent || zone.highlightColor != .none || zone.sizeMode == .fixed {
            return true
        }

        return zone.children?.contains(where: shouldRender) ?? false
    }
}

private struct FlashcardGridZonePreview: View {
    let zone: ZoneModel
    let path: String
    let fontScale: CGFloat
    let availableWidth: CGFloat
    let centersLeafBlocks: Bool
    let alignLeafBlocksToGroupLeading: Bool
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
                alignLeafBlocksToGroupLeading: alignLeafBlocksToGroupLeading,
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
        let children = zone.children?.filter(FlashcardGridZoneRenderPolicy.shouldRender) ?? []

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
                        alignLeafBlocksToGroupLeading: alignLeafBlocksToGroupLeading,
                        showsDebugGuides: showsDebugGuides,
                        collectsDebugMetrics: collectsDebugMetrics,
                        onTap: onTap
                    )
                    .frame(width: childWidth, alignment: .topLeading)
                }
            }
            .frame(width: availableWidth, alignment: .topLeading)
        } else {
            let groupWidth = verticalGroupWidth(for: children)

            VStack(alignment: .leading, spacing: FlashcardGridContentMetrics.childSpacing) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                    FlashcardGridZonePreview(
                        zone: child,
                        path: "\(path).\(index)",
                        fontScale: fontScale,
                        availableWidth: groupWidth,
                        centersLeafBlocks: centersLeafBlocks,
                        alignLeafBlocksToGroupLeading: true,
                        showsDebugGuides: showsDebugGuides,
                        collectsDebugMetrics: collectsDebugMetrics,
                        onTap: onTap
                    )
                    .frame(width: groupWidth, alignment: .topLeading)
                }
            }
            .frame(width: groupWidth, alignment: .topLeading)
            .frame(width: availableWidth, alignment: .top)
        }
    }

    private func verticalGroupWidth(for children: [ZoneModel]) -> CGFloat {
        let widestChild = children
            .map {
                FlashcardGridContentEstimator.estimatedBlockWidth(
                    for: $0,
                    fontScale: fontScale,
                    availableWidth: availableWidth
                )
            }
            .max() ?? availableWidth

        return min(max(ceil(widestChild), 1), availableWidth)
    }
}

// MARK: - Flashcard Grid Leaf Preview

private struct FlashcardGridLeafPreview: View {
    let zone: ZoneModel
    let path: String
    let fontScale: CGFloat
    let availableWidth: CGFloat
    let centersLeafBlocks: Bool
    let alignLeafBlocksToGroupLeading: Bool
    let showsDebugGuides: Bool
    let collectsDebugMetrics: Bool
    var onTap: (() -> Void)?

    @State private var renderedContentSize: CGSize = .zero

    var body: some View {
        let resolvedLayoutZone = layoutZone
        let layout = CardZoneLayoutEngine.leafLayout(
            for: resolvedLayoutZone,
            spec: CardZoneLayoutSpec(
                availableWidth: availableWidth,
                fontScale: fontScale
            ),
            measuredContentSize: renderedContentSize
        )

        ZStack(alignment: .topLeading) {
            zoneBlockSurface(layout: layout)

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
                .frame(
                    width: layout.contentLayoutWidth,
                    height: contentFrameHeight(for: layout),
                    alignment: .topLeading
                )
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

    private func contentFrameHeight(for layout: CardZoneLayoutResult) -> CGFloat? {
        switch zone.contentType {
        case .image, .sketch:
            return layout.blockSize.height
        case .empty, .text, .code:
            return zone.sizeMode == .fixed ? layout.blockSize.height : nil
        }
    }

    private var layoutZone: ZoneModel {
        guard alignLeafBlocksToGroupLeading else { return zone }

        var leadingZone = zone
        leadingZone.blockAlignment = .leading
        return leadingZone
    }

    @ViewBuilder
    private func zoneBlockSurface(layout: CardZoneLayoutResult) -> some View {
        switch zone.contentType {
        case .empty, .text, .code:
            let tint = zone.highlightColor.zoneSurfaceTint
            RoundedRectangle(cornerRadius: FlashcardGridContentMetrics.zoneCornerRadius, style: .continuous)
                .fill(zone.highlightColor.zoneSurfaceFill)
                .overlay {
                    if tint == nil {
                        RoundedRectangle(cornerRadius: FlashcardGridContentMetrics.zoneCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                    }
                }
                .overlay {
                    if let tint {
                        RoundedRectangle(cornerRadius: FlashcardGridContentMetrics.zoneCornerRadius, style: .continuous)
                            .stroke(tint.opacity(0.86), lineWidth: 2)
                    }
                }
                .shadow(color: tint?.opacity(0.34) ?? .clear, radius: tint == nil ? 0 : 10)
                .frame(width: layout.blockSize.width, height: layout.blockSize.height)
                .offset(x: layout.leadingInset)
                .allowsHitTesting(false)
        case .image, .sketch:
            EmptyView()
        }
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
        let semanticText = MathTextSanitizer.heal(previewText)
        let usesMathRenderer = MathTextSanitizer.containsMath(semanticText)
            || MathTextSanitizer.containsInlineCode(semanticText)
        let textWidthLimit = layout.textWidthLimit ?? max(layout.contentLayoutWidth, 1)
        let showsBullet = zone.hasBullet
            && !previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return HStack(alignment: .top, spacing: showsBullet ? FlashcardGridContentMetrics.bulletSpacing : 0) {
            if showsBullet {
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
            } else {
                FlashcardPlainTextBlockView(
                    text: previewText,
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
                text: displayText,
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
            return MathTextSanitizer.stripTerminalZonePeriodPreservingWhitespace(zone.text)
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
    static let textVerticalPadding: CGFloat = 32
    static let textHorizontalPadding: CGFloat = 24
    static let zoneCornerRadius: CGFloat = 18
    static let highlightedHorizontalPadding: CGFloat = textHorizontalPadding
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
        let text = rawText.replacingOccurrences(of: "\r\n", with: "\n")
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
                    let nextToken = remainingToken

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
        tokens.filter { !$0.text.isEmpty }
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
    private static let textHorizontalPadding = FlashcardGridContentMetrics.textHorizontalPadding
    private static let highlightedHorizontalPadding = FlashcardGridContentMetrics.highlightedHorizontalPadding
    private static let bulletWidth = FlashcardGridContentMetrics.bulletWidth
    private static let bulletSpacing = FlashcardGridContentMetrics.bulletSpacing

    static func estimatedSize(
        for zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> CGSize {
        let clampedWidth = max(availableWidth, 1)

        guard FlashcardGridZoneRenderPolicy.shouldRender(zone) else {
            return CGSize(width: 1, height: 36)
        }

        if zone.isLeaf {
            return estimatedLeafSize(
                for: zone,
                fontScale: fontScale,
                availableWidth: clampedWidth
            )
        }

        let children = zone.children?.filter(FlashcardGridZoneRenderPolicy.shouldRender) ?? []
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

    static func estimatedBlockWidth(
        for zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> CGFloat {
        let clampedWidth = max(availableWidth, 1)

        guard FlashcardGridZoneRenderPolicy.shouldRender(zone) else {
            return 1
        }

        if zone.isLeaf {
            let measuredSize = estimatedLeafSize(
                for: zone,
                fontScale: fontScale,
                availableWidth: clampedWidth
            )
            let layout = CardZoneLayoutEngine.leafLayout(
                for: zone,
                spec: CardZoneLayoutSpec(
                    availableWidth: clampedWidth,
                    fontScale: fontScale
                ),
                measuredContentSize: measuredSize
            )

            return min(max(ceil(layout.blockSize.width), 1), clampedWidth)
        }

        let children = zone.children?.filter(FlashcardGridZoneRenderPolicy.shouldRender) ?? []
        guard !children.isEmpty else { return 1 }

        switch zone.direction {
        case .vertical:
            return children
                .map {
                    estimatedBlockWidth(
                        for: $0,
                        fontScale: fontScale,
                        availableWidth: clampedWidth
                    )
                }
                .max() ?? 1

        case .horizontal:
            return estimatedSize(
                for: zone,
                fontScale: fontScale,
                availableWidth: clampedWidth
            )
            .width
        }
    }

    static func debugLineWidths(
        for zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> [CGFloat] {
        let displayText = MathTextSanitizer.stripTerminalZonePeriodPreservingWhitespace(zone.text)
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
            let displayText = MathTextSanitizer.stripTerminalZonePeriodPreservingWhitespace(zone.text)
            let horizontalInsets = textHorizontalPadding
            let bulletInset = zone.hasBullet && !displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? bulletWidth + bulletSpacing
                : 0
            if let codeLiteral = singleInlineCodeLiteral(in: displayText) {
                let textWidth = max(availableWidth - horizontalInsets - bulletInset, 1)
                let codeSize = measuredInlineCodeSize(
                    codeLiteral,
                    zone: zone,
                    fontScale: fontScale,
                    availableWidth: textWidth
                )

                return CGSize(
                    width: min(ceil(codeSize.width + horizontalInsets + bulletInset), availableWidth),
                    height: ceil(codeSize.height + textVerticalPadding)
                )
            }

            if MathTextSanitizer.containsMath(displayText) {
                let textWidth = max(availableWidth - horizontalInsets - bulletInset, 1)
                let textSize = measuredTextSize(
                    displayText,
                    zone: zone,
                    fontScale: fontScale,
                    availableWidth: textWidth
                )

                return CGSize(
                    width: availableWidth,
                    height: ceil(textSize.height + textVerticalPadding)
                )
            }

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
                max(availableWidth * zone.imageScale, 1)
            )
            return CGSize(
                width: imageWidth,
                height: imageWidth * imageHeightRatio(for: zone.imageData)
            )
        }
    }

    private static func imageHeightRatio(for data: Data?) -> CGFloat {
        guard let data,
              let image = UIImage(data: data),
              image.size.width > 0,
              image.size.height > 0
        else {
            return 0.66
        }

        return max(image.size.height / image.size.width, 0.05)
    }

    private static func measuredTextSize(
        _ rawText: String,
        zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> CGSize {
        let text = rawText.replacingOccurrences(of: "\r\n", with: "\n")
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

    private static func singleInlineCodeLiteral(in text: String) -> String? {
        guard
            let regex = try? NSRegularExpression(pattern: #"^`([^`]+)`$"#),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return String(text[range]).replacingOccurrences(of: "\r\n", with: "\n")
    }

    private static func measuredInlineCodeSize(
        _ value: String,
        zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> CGSize {
        let font = UIFont.monospacedSystemFont(
            ofSize: fontSize(for: zone) * fontScale * 0.92,
            weight: .semibold
        )
        let constrainedWidth = max(availableWidth, 1)
        let lines = value.components(separatedBy: .newlines)
        let lineRects = lines.map {
            ($0 as NSString).boundingRect(
                with: CGSize(width: constrainedWidth, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            )
        }
        let widestLine = lineRects.map(\.width).max() ?? 1
        let lineHeight = max(lineRects.map(\.height).max() ?? font.lineHeight, font.lineHeight * 1.5)

        return CGSize(
            width: min(ceil(widestLine), constrainedWidth),
            height: ceil(lineRects.reduce(CGFloat(0)) { $0 + max(ceil($1.height), lineHeight) })
        )
    }

    private static func measuredTextLayout(
        _ rawText: String,
        zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> TextLayoutMeasurement {
        let text = rawText.replacingOccurrences(of: "\r\n", with: "\n")
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
        if MathTextSanitizer.containsInlineCode(text) {
            let preferredWidth = measuredPreferredInlineMarkdownWidth(
                text,
                zone: zone,
                fontScale: fontScale
            )
            let resolvedWidth = min(max(lineLayout.size.width, preferredWidth), max(availableWidth, 1))

            return TextLayoutMeasurement(
                size: CGSize(width: ceil(resolvedWidth), height: lineLayout.size.height),
                lineWidths: preferredWidth <= availableWidth
                    ? [ceil(preferredWidth)]
                    : lineLayout.lines.map(\.width)
            )
        }

        return TextLayoutMeasurement(
            size: lineLayout.size,
            lineWidths: lineLayout.lines.map(\.width)
        )
    }

    private struct TextLayoutMeasurement {
        let size: CGSize
        let lineWidths: [CGFloat]
    }

    private static func measuredPreferredInlineMarkdownWidth(
        _ text: String,
        zone: ZoneModel,
        fontScale: CGFloat
    ) -> CGFloat {
        text.components(separatedBy: .newlines)
            .map {
                measuredPreferredInlineMarkdownLineWidth(
                    $0,
                    zone: zone,
                    fontScale: fontScale
                )
            }
            .max() ?? 1
    }

    private static func measuredPreferredInlineMarkdownLineWidth(
        _ line: String,
        zone: ZoneModel,
        fontScale: CGFloat
    ) -> CGFloat {
        var width: CGFloat = 0
        var plainBuffer = ""
        var cursor = line.startIndex
        var isEmphasized = false

        func flushPlainBuffer() {
            guard !plainBuffer.isEmpty else { return }
            width += measuredPlainRunWidth(
                plainBuffer,
                zone: zone,
                fontScale: fontScale,
                emphasized: isEmphasized
            )
            plainBuffer.removeAll(keepingCapacity: true)
        }

        while cursor < line.endIndex {
            if line[cursor...].hasPrefix("**") {
                flushPlainBuffer()
                isEmphasized.toggle()
                cursor = line.index(cursor, offsetBy: 2)
                continue
            }

            if line[cursor] == "`" {
                let contentStart = line.index(after: cursor)
                if let closing = line[contentStart...].firstIndex(of: "`") {
                    flushPlainBuffer()
                    width += measuredInlineCodeRunWidth(
                        String(line[contentStart..<closing]),
                        zone: zone,
                        fontScale: fontScale,
                        emphasized: isEmphasized
                    )
                    cursor = line.index(after: closing)
                    continue
                }
            }

            plainBuffer.append(line[cursor])
            cursor = line.index(after: cursor)
        }

        flushPlainBuffer()
        return max(ceil(width), 1)
    }

    private static func measuredPlainRunWidth(
        _ value: String,
        zone: ZoneModel,
        fontScale: CGFloat,
        emphasized: Bool
    ) -> CGFloat {
        measuredRunWidth(
            value,
            font: font(for: zone, fontScale: fontScale, emphasized: emphasized, monospaced: false)
        )
    }

    private static func measuredInlineCodeRunWidth(
        _ value: String,
        zone: ZoneModel,
        fontScale: CGFloat,
        emphasized: Bool
    ) -> CGFloat {
        let font = UIFont.monospacedSystemFont(
            ofSize: fontSize(for: zone) * fontScale * 0.88,
            weight: fontWeight(for: zone, emphasized: emphasized)
        )
        return measuredRunWidth(value, font: font) + 14
    }

    private static func measuredRunWidth(_ value: String, font: UIFont) -> CGFloat {
        guard !value.isEmpty else { return 0 }
        return ceil((value as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).width)
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

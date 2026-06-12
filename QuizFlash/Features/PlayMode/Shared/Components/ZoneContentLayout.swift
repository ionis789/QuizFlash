//
//  ZoneContentLayout.swift
//  QuizFlash
//
//  Shared zone layout and rendering helpers used by play mode, quiz play,
//  and editor preview surfaces.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Zone Content Layout Debug

struct ZoneContentLayoutDebugSnapshot: Equatable {
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
    let leafSnapshots: [ZoneContentLeafLayoutDebugSnapshot]
}

struct ZoneContentLeafLayoutDebugSnapshot: Equatable {
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
    let rawTextCharacterCount: Int
    let rawTextLineCount: Int
    let rawText: String
    let normalizedDisplayText: String
    let healedDisplayText: String
    let textCharacterCount: Int
    let textLineCount: Int
    let estimatedLineWidths: [CGFloat]
    let renderedLineTexts: [String]
    let renderedLineWidths: [CGFloat]
    let renderedTokenLines: [MixedMathRenderedLineDebug]
    let renderedScrollableMath: [MixedMathScrollableDebug]
    let mathGestureDebug: MixedMathGestureDebugSnapshot?
    let textPreview: String
    let fullText: String
}

struct ZoneContentLeafDebugPreferenceKey: PreferenceKey {
    static var defaultValue: [ZoneContentLeafLayoutDebugSnapshot] { [] }

    static func reduce(
        value: inout [ZoneContentLeafLayoutDebugSnapshot],
        nextValue: () -> [ZoneContentLeafLayoutDebugSnapshot]
    ) {
        value.append(contentsOf: nextValue())
    }
}

struct ZoneContentRenderBlockBounds {
    let zoneID: UUID
    let frame: CGRect
}

struct ZoneContentRenderBlockBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: [ZoneContentRenderBlockBounds] { [] }

    static func reduce(
        value: inout [ZoneContentRenderBlockBounds],
        nextValue: () -> [ZoneContentRenderBlockBounds]
    ) {
        value.append(contentsOf: nextValue())
    }
}

enum ZoneContentRenderCoordinateSpace {
    static let name = "ZoneContentRenderSurface"
}

private struct ZoneContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }

    static func reduce(
        value: inout [String: CGFloat],
        nextValue: () -> [String: CGFloat]
    ) {
        for (path, width) in nextValue() {
            value[path] = max(value[path] ?? 0, width)
        }
    }
}

enum ZoneContentLeafTapBehavior {
    case all
    case richContentOnly
    case none

    var allowsRichContentTap: Bool {
        switch self {
        case .all, .richContentOnly:
            return true
        case .none:
            return false
        }
    }

    var allowsPlainTextTap: Bool {
        switch self {
        case .all:
            return true
        case .richContentOnly, .none:
            return false
        }
    }
}

private struct ZoneContentLeafMeasurementIdentity: Equatable {
    let id: UUID
    let contentType: ZoneContentType
    let text: String
    let textStyle: TextBlockStyle
    let textAlignment: TextBlockAlignment
    let sizeMode: ZoneSizeMode
    let fixedWidth: CGFloat?
    let fixedHeight: CGFloat?
    let isBold: Bool
    let isItalic: Bool
    let hasBullet: Bool
    let fontFamily: FontFamily
    let fontScale: CGFloat
    let textVerticalPadding: CGFloat
    let textHorizontalPaddingOverride: CGFloat?
    let availableWidth: CGFloat
}

private enum ZoneContentDisplayTextNormalizer {
    nonisolated static func textZoneDisplayText(_ rawText: String) -> String {
        let strippedText = MathTextSanitizer.stripTerminalZonePeriodPreservingWhitespace(rawText)
        if strippedText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
            return ZoneForcedLineBreak.renderText(strippedText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return normalizeEditorLineWrapping(in: strippedText)
    }

    /// Play surfaces own their own wrapping. The editor may contain manual
    /// single-newline wraps because raw LaTeX is wider than rendered KaTeX; those
    /// wraps should not force bad line breaks in flashcard or quiz playback.
    nonisolated private static func normalizeEditorLineWrapping(in text: String) -> String {
        ZoneForcedLineBreak.normalizeCarriageReturns(in: text)
            .components(separatedBy: ZoneForcedLineBreak.marker)
            .map(normalizeSoftEditorLineWrapping)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func normalizeSoftEditorLineWrapping(in text: String) -> String {
        let normalizedNewlines = ZoneForcedLineBreak.normalizeCarriageReturns(in: text)
        guard normalizedNewlines.contains("\n") else {
            return normalizedNewlines.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var paragraphs: [String] = []
        var currentLines: [String] = []

        for line in normalizedNewlines.components(separatedBy: "\n") {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty {
                if !currentLines.isEmpty {
                    paragraphs.append(currentLines.joined(separator: " "))
                    currentLines = []
                }
            } else {
                currentLines.append(trimmedLine)
            }
        }

        if !currentLines.isEmpty {
            paragraphs.append(currentLines.joined(separator: " "))
        }

        return paragraphs
            .map { paragraph in
                paragraph.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ZoneContentContainerMeasurementIdentity: Equatable {
    let id: UUID
    let direction: ZoneDirection
    let childIdentities: [ZoneContentLeafMeasurementIdentity]
    let fontScale: CGFloat
    let availableWidth: CGFloat
}

@ViewBuilder
private func zoneAlignmentHighlight(cornerRadius: CGFloat = 16) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .stroke(
            ThemeManager.shared.accentColor.color.opacity(0.78),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
        )
        .shadow(color: ThemeManager.shared.accentColor.color.opacity(0.24), radius: 8)
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
}

// MARK: - Zone Content Content Layout

struct ZoneContentLayout {
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
            return max(ceil(measuredContentSize.height), 1)
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

// MARK: - Zone Content Content View

struct ZoneContentRenderView: View {
    let zone: ZoneModel
    let fontScale: CGFloat
    let availableWidth: CGFloat
    let centersLeafBlocks: Bool
    var alignLeafBlocksToGroupLeading: Bool = false
    let showsDebugGuides: Bool
    var showsZoneSurfaces: Bool = true
    var showsCodeBlockZoneSurfaces: Bool = false
    var usesBorderOnlyZoneHighlights: Bool = false
    var zoneHighlightStrokeStyle: StrokeStyle = StrokeStyle(lineWidth: 2)
    var textVerticalPadding: CGFloat = ZoneContentMetrics.textVerticalPadding
    var textHorizontalPaddingOverride: CGFloat? = nil
    var alignmentFeedback: ZoneAlignmentFeedback = .inactive
    let collectsDebugMetrics: Bool
    var leafTapBehavior: ZoneContentLeafTapBehavior = .all
    var onTap: (() -> Void)?
    var onRootBlockWidthChange: ((CGFloat) -> Void)?

    var body: some View {
        ZoneContentTreePreview(
            zone: zone,
            path: "root",
            fontScale: fontScale,
            availableWidth: max(availableWidth, 1),
            centersLeafBlocks: centersLeafBlocks,
            alignLeafBlocksToGroupLeading: alignLeafBlocksToGroupLeading,
            showsDebugGuides: showsDebugGuides,
            showsZoneSurfaces: showsZoneSurfaces,
            showsCodeBlockZoneSurfaces: showsCodeBlockZoneSurfaces,
            usesBorderOnlyZoneHighlights: usesBorderOnlyZoneHighlights,
            zoneHighlightStrokeStyle: zoneHighlightStrokeStyle,
            textVerticalPadding: textVerticalPadding,
            textHorizontalPaddingOverride: textHorizontalPaddingOverride,
            alignmentFeedback: alignmentFeedback,
            collectsDebugMetrics: collectsDebugMetrics,
            leafTapBehavior: leafTapBehavior,
            onTap: onTap
        )
        .frame(width: max(availableWidth, 1), alignment: .topLeading)
        .onPreferenceChange(ZoneContentWidthPreferenceKey.self) { widths in
            guard let width = widths["root"], width > 0 else { return }
            onRootBlockWidthChange?(ceil(width))
        }
    }
}

// MARK: - Zone Content Zone Preview

private enum ZoneContentRenderPolicy {
    nonisolated static func shouldRender(_ zone: ZoneModel) -> Bool {
        if zone.hasContent || zone.highlightColor != .none || zone.sizeMode == .fixed {
            return true
        }

        return zone.children?.contains(where: shouldRender) ?? false
    }
}

private struct ZoneContentTreePreview: View {
    let zone: ZoneModel
    let path: String
    let fontScale: CGFloat
    let availableWidth: CGFloat
    let centersLeafBlocks: Bool
    let alignLeafBlocksToGroupLeading: Bool
    let showsDebugGuides: Bool
    let showsZoneSurfaces: Bool
    let showsCodeBlockZoneSurfaces: Bool
    let usesBorderOnlyZoneHighlights: Bool
    let zoneHighlightStrokeStyle: StrokeStyle
    let textVerticalPadding: CGFloat
    let textHorizontalPaddingOverride: CGFloat?
    let alignmentFeedback: ZoneAlignmentFeedback
    let collectsDebugMetrics: Bool
    let leafTapBehavior: ZoneContentLeafTapBehavior
    var onTap: (() -> Void)?

    @State private var measuredDirectChildWidths: [String: CGFloat] = [:]

    var body: some View {
        if zone.isLeaf {
            ZoneContentLeafPreview(
                zone: zone,
                path: path,
                fontScale: fontScale,
                availableWidth: availableWidth,
                centersLeafBlocks: centersLeafBlocks,
                alignLeafBlocksToGroupLeading: alignLeafBlocksToGroupLeading,
                showsDebugGuides: showsDebugGuides,
                showsZoneSurfaces: showsZoneSurfaces,
                showsCodeBlockZoneSurfaces: showsCodeBlockZoneSurfaces,
                usesBorderOnlyZoneHighlights: usesBorderOnlyZoneHighlights,
                zoneHighlightStrokeStyle: zoneHighlightStrokeStyle,
                textVerticalPadding: textVerticalPadding,
                textHorizontalPaddingOverride: textHorizontalPaddingOverride,
                alignmentFeedback: alignmentFeedback,
                collectsDebugMetrics: collectsDebugMetrics,
                leafTapBehavior: leafTapBehavior,
                onTap: onTap
            )
        } else {
            containerPreview
        }
    }

    @ViewBuilder
    private var containerPreview: some View {
        let indexedChildren = renderableIndexedChildren
        let children = indexedChildren.map(\.element)

        if children.isEmpty {
            Color.clear.frame(width: availableWidth, height: 1)
        } else if zone.direction == .horizontal {
            let spacingTotal = CGFloat(max(children.count - 1, 0)) * ZoneContentMetrics.childSpacing
            let childWidth = max((availableWidth - spacingTotal) / CGFloat(max(children.count, 1)), 1)

            HStack(alignment: .top, spacing: ZoneContentMetrics.childSpacing) {
                ForEach(indexedChildren, id: \.element.id) { index, child in
                    ZoneContentTreePreview(
                        zone: child,
                        path: "\(path).\(index)",
                        fontScale: fontScale,
                        availableWidth: childWidth,
                        centersLeafBlocks: centersLeafBlocks,
                        alignLeafBlocksToGroupLeading: alignLeafBlocksToGroupLeading,
                        showsDebugGuides: showsDebugGuides,
                        showsZoneSurfaces: showsZoneSurfaces,
                        showsCodeBlockZoneSurfaces: showsCodeBlockZoneSurfaces,
                        usesBorderOnlyZoneHighlights: usesBorderOnlyZoneHighlights,
                        zoneHighlightStrokeStyle: zoneHighlightStrokeStyle,
                        textVerticalPadding: textVerticalPadding,
                        textHorizontalPaddingOverride: textHorizontalPaddingOverride,
                        alignmentFeedback: alignmentFeedback,
                        collectsDebugMetrics: collectsDebugMetrics,
                        leafTapBehavior: leafTapBehavior,
                        onTap: onTap
                    )
                    .frame(width: childWidth, alignment: .topLeading)
                }
            }
            .frame(width: availableWidth, alignment: .topLeading)
        } else {
            let childPaths = indexedChildren.map { "\(path).\($0.offset)" }
            let containerIdentity = verticalContainerMeasurementIdentity(for: children)
            let groupWidth = verticalGroupWidth(for: children, childPaths: childPaths)
            let groupTarget = zonePath.map { ZoneAlignmentTargetRef(path: $0, kind: .group) }
            let groupWiggleOffset = groupTarget.map { alignmentFeedback.offset(for: $0) } ?? 0
            let groupLeadingInset = ZoneContentLayoutEngine.blockLeadingInset(
                for: zone.blockAlignment,
                blockWidth: groupWidth,
                availableWidth: availableWidth,
                defaultAlignment: .center
            )

            HStack(spacing: 0) {
                Color.clear.frame(width: groupLeadingInset)

                VStack(alignment: .leading, spacing: ZoneContentMetrics.childSpacing) {
                    ForEach(indexedChildren, id: \.element.id) { index, child in
                        ZoneContentTreePreview(
                            zone: child,
                            path: "\(path).\(index)",
                            fontScale: fontScale,
                            availableWidth: groupWidth,
                            centersLeafBlocks: centersLeafBlocks,
                            alignLeafBlocksToGroupLeading: false,
                            showsDebugGuides: showsDebugGuides,
                            showsZoneSurfaces: showsZoneSurfaces,
                            showsCodeBlockZoneSurfaces: showsCodeBlockZoneSurfaces,
                            usesBorderOnlyZoneHighlights: usesBorderOnlyZoneHighlights,
                            zoneHighlightStrokeStyle: zoneHighlightStrokeStyle,
                            textVerticalPadding: textVerticalPadding,
                            textHorizontalPaddingOverride: textHorizontalPaddingOverride,
                            alignmentFeedback: alignmentFeedback,
                            collectsDebugMetrics: collectsDebugMetrics,
                            leafTapBehavior: leafTapBehavior,
                            onTap: onTap
                        )
                        .frame(width: groupWidth, alignment: .topLeading)
                    }
                }
                .frame(width: groupWidth, alignment: .topLeading)
                .overlay {
                    if let groupTarget,
                       alignmentFeedback.highlightedTarget == groupTarget {
                        zoneAlignmentHighlight()
                    }
                }
                .offset(x: groupWiggleOffset)

                Color.clear.frame(width: max(availableWidth - groupLeadingInset - groupWidth, 0))
            }
            .frame(width: availableWidth, alignment: .topLeading)
            .animation(.easeOut(duration: 0.22), value: groupLeadingInset)
            .animation(.easeOut(duration: 0.22), value: groupWidth)
            .onPreferenceChange(ZoneContentWidthPreferenceKey.self) { widths in
                let directWidths: [String: CGFloat] = Dictionary(
                    uniqueKeysWithValues: zip(childPaths, children).compactMap { childPath, child -> (String, CGFloat)? in
                        guard let width = widths[childPath], width > 0 else {
                            return nil
                        }

                        let resolvedWidth = ceil(width)
                        guard isValidMeasuredWidth(resolvedWidth, for: child) else {
                            return nil
                        }

                        return (childPath, resolvedWidth)
                    }
                )

                guard directWidths.count == childPaths.count else {
                    if !measuredDirectChildWidths.isEmpty {
                        measuredDirectChildWidths = [:]
                    }
                    return
                }

                guard directWidths != measuredDirectChildWidths else {
                    return
                }

                measuredDirectChildWidths = directWidths
            }
            .onChange(of: containerIdentity) { _, _ in
                measuredDirectChildWidths = [:]
            }
            .preference(
                key: ZoneContentWidthPreferenceKey.self,
                value: [path: groupWidth]
            )
        }
    }

    private var renderableIndexedChildren: [(offset: Int, element: ZoneModel)] {
        (zone.children ?? [])
            .enumerated()
            .filter { ZoneContentRenderPolicy.shouldRender($0.element) }
    }

    private var zonePath: ZonePath? {
        Self.zonePath(from: path)
    }

    private static func zonePath(from value: String) -> ZonePath? {
        guard value == "root" || value.hasPrefix("root.") else { return nil }
        let components = value.split(separator: ".").dropFirst()
        let indices = components.compactMap { Int($0) }
        guard indices.count == components.count else { return nil }
        return ZonePath(indices: indices)
    }

    private func verticalGroupWidth(for children: [ZoneModel], childPaths: [String]) -> CGFloat {
        let estimatedWidth = estimatedVerticalGroupWidth(for: children)

        if measuredDirectChildWidths.count == childPaths.count {
            let measuredWidth = childPaths
                .compactMap { measuredDirectChildWidths[$0] }
                .max() ?? 1

            return min(max(ceil(max(measuredWidth, estimatedWidth)), 1), availableWidth)
        }

        return min(max(ceil(estimatedWidth), 1), availableWidth)
    }

    private func estimatedVerticalGroupWidth(for children: [ZoneModel]) -> CGFloat {
        let widestChild = children
            .map {
                ZoneContentEstimator.estimatedBlockWidth(
                    for: $0,
                    fontScale: fontScale,
                    availableWidth: availableWidth,
                    textVerticalPadding: textVerticalPadding,
                    textHorizontalPaddingOverride: textHorizontalPaddingOverride
                )
            }
            .max() ?? availableWidth

        return min(max(ceil(widestChild), 1), availableWidth)
    }

    private func isValidMeasuredWidth(_ width: CGFloat, for child: ZoneModel) -> Bool {
        width >= minimumValidMeasuredWidth(for: child)
    }

    private func minimumValidMeasuredWidth(for child: ZoneModel) -> CGFloat {
        if child.isLeaf {
            guard child.hasContent else { return 1 }

            switch child.contentType {
            case .text, .code, .empty:
                return min(
                    max(resolvedTextHorizontalPadding + 8, 1),
                    availableWidth
                )
            case .image, .sketch:
                return 1
            }
        }

        let childMinimum = child.children?
            .filter(ZoneContentRenderPolicy.shouldRender)
            .map(minimumValidMeasuredWidth(for:))
            .max() ?? 1

        return min(max(childMinimum, 1), availableWidth)
    }

    private func verticalContainerMeasurementIdentity(for children: [ZoneModel]) -> ZoneContentContainerMeasurementIdentity {
        ZoneContentContainerMeasurementIdentity(
            id: zone.id,
            direction: zone.direction,
            childIdentities: children.map { leafMeasurementIdentity(for: $0) },
            fontScale: fontScale,
            availableWidth: ceil(availableWidth)
        )
    }

    private func leafMeasurementIdentity(for child: ZoneModel) -> ZoneContentLeafMeasurementIdentity {
        ZoneContentLeafMeasurementIdentity(
            id: child.id,
            contentType: child.contentType,
            text: child.text,
            textStyle: child.textStyle,
            textAlignment: child.textAlignment,
            sizeMode: child.sizeMode,
            fixedWidth: child.fixedWidth.map(ceil),
            fixedHeight: child.fixedHeight.map(ceil),
            isBold: child.isBold,
            isItalic: child.isItalic,
            hasBullet: child.hasBullet,
            fontFamily: child.fontFamily,
            fontScale: fontScale,
            textVerticalPadding: ceil(textVerticalPadding),
            textHorizontalPaddingOverride: textHorizontalPaddingOverride.map(ceil),
            availableWidth: ceil(availableWidth)
        )
    }

    private var resolvedTextHorizontalPadding: CGFloat {
        textHorizontalPaddingOverride ?? ZoneContentMetrics.textHorizontalPadding
    }
}

// MARK: - Zone Content Leaf Preview

private struct ZoneContentLeafPreview: View {
    let zone: ZoneModel
    let path: String
    let fontScale: CGFloat
    let availableWidth: CGFloat
    let centersLeafBlocks: Bool
    let alignLeafBlocksToGroupLeading: Bool
    let showsDebugGuides: Bool
    let showsZoneSurfaces: Bool
    let showsCodeBlockZoneSurfaces: Bool
    let usesBorderOnlyZoneHighlights: Bool
    let zoneHighlightStrokeStyle: StrokeStyle
    let textVerticalPadding: CGFloat
    let textHorizontalPaddingOverride: CGFloat?
    let alignmentFeedback: ZoneAlignmentFeedback
    let collectsDebugMetrics: Bool
    let leafTapBehavior: ZoneContentLeafTapBehavior
    var onTap: (() -> Void)?

    @State private var renderedContentSize: CGSize = .zero
    @State private var renderedTokenLines: [MixedMathRenderedLineDebug] = []
    @State private var renderedScrollableMath: [MixedMathScrollableDebug] = []
    @State private var mathGestureDebug: MixedMathGestureDebugSnapshot?

    var body: some View {
        let resolvedLayoutZone = layoutZone
        let layout = ZoneContentLayoutEngine.leafLayout(
            for: resolvedLayoutZone,
            spec: ZoneContentLayoutSpec(
                availableWidth: availableWidth,
                fontScale: fontScale,
                textVerticalPadding: textVerticalPadding,
                textHorizontalPaddingOverride: textHorizontalPaddingOverride
            ),
            measuredContentSize: renderedContentSize
        )

        HStack(spacing: 0) {
            Color.clear.frame(width: layout.leadingInset)

            ZStack(alignment: .topLeading) {
                renderBlockBounds(layout: layout)
                zoneBlockSurface(layout: layout)

                if let leafTarget,
                   alignmentFeedback.highlightedTarget == leafTarget {
                    zoneAlignmentHighlight()
                        .frame(width: layout.blockSize.width, height: layout.blockSize.height)
                }

                if showsDebugGuides {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            Color.orange.opacity(0.95),
                            style: StrokeStyle(lineWidth: 1.6, dash: [5, 4])
                        )
                        .frame(width: layout.blockSize.width, height: layout.blockSize.height)
                        .allowsHitTesting(false)
                }

                leafContent(layout: layout)
                    .frame(
                        width: layout.contentLayoutWidth,
                        height: contentFrameHeight(for: layout),
                        alignment: contentAlignment(for: resolvedLayoutZone)
                    )
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
            .frame(width: layout.blockSize.width, height: layout.blockSize.height, alignment: .topLeading)
            .offset(x: leafWiggleOffset)

            Color.clear.frame(width: max(availableWidth - layout.leadingInset - layout.blockSize.width, 0))
        }
        .frame(width: availableWidth, height: layout.blockSize.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.22), value: layout.leadingInset)
        .preference(
            key: ZoneContentLeafDebugPreferenceKey.self,
            value: collectsDebugMetrics
                ? [debugSnapshot(layout: layout, layoutZone: resolvedLayoutZone)]
                : []
        )
        .preference(
            key: ZoneContentWidthPreferenceKey.self,
            value: [path: layout.blockSize.width]
        )
        .onChange(of: measurementIdentity) { _, _ in
            renderedContentSize = .zero
            renderedTokenLines = []
            renderedScrollableMath = []
            mathGestureDebug = nil
        }
    }

    private func renderBlockBounds(layout: ZoneContentLayoutResult) -> some View {
        Color.clear
            .frame(width: layout.blockSize.width, height: layout.blockSize.height)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ZoneContentRenderBlockBoundsPreferenceKey.self,
                        value: [
                            ZoneContentRenderBlockBounds(
                                zoneID: zone.id,
                                frame: proxy.frame(in: .named(ZoneContentRenderCoordinateSpace.name))
                            )
                        ]
                    )
                }
            )
            .allowsHitTesting(false)
    }

    private var leafWiggleOffset: CGFloat {
        leafTarget.map(alignmentFeedback.offset(for:)) ?? 0
    }

    private var leafTarget: ZoneAlignmentTargetRef? {
        zonePath.map { ZoneAlignmentTargetRef(path: $0, kind: .leaf) }
    }

    private var zonePath: ZonePath? {
        Self.zonePath(from: path)
    }

    private static func zonePath(from value: String) -> ZonePath? {
        guard value == "root" || value.hasPrefix("root.") else { return nil }
        let components = value.split(separator: ".").dropFirst()
        let indices = components.compactMap { Int($0) }
        guard indices.count == components.count else { return nil }
        return ZonePath(indices: indices)
    }

    private func contentFrameHeight(for layout: ZoneContentLayoutResult) -> CGFloat? {
        switch zone.contentType {
        case .image, .sketch:
            return layout.blockSize.height
        case .empty, .text, .code:
            return zone.sizeMode == .fixed ? layout.blockSize.height : nil
        }
    }

    private func contentAlignment(for zone: ZoneModel) -> Alignment {
        switch zone.verticalAlignment.resolved(fallback: .top) {
        case .auto, .top:
            return .topLeading
        case .center:
            return .leading
        case .bottom:
            return .bottomLeading
        }
    }

    private var layoutZone: ZoneModel {
        var layoutZone = zone
        layoutZone.textAlignment = .leading

        if layoutZone.blockAlignment == .auto {
            layoutZone.blockAlignment = path == "root" ? .center : .leading
        }

        guard alignLeafBlocksToGroupLeading else { return layoutZone }

        layoutZone.blockAlignment = .leading
        return layoutZone
    }

    private var measurementIdentity: ZoneContentLeafMeasurementIdentity {
        ZoneContentLeafMeasurementIdentity(
            id: zone.id,
            contentType: zone.contentType,
            text: zone.text,
            textStyle: zone.textStyle,
            textAlignment: zone.textAlignment,
            sizeMode: zone.sizeMode,
            fixedWidth: zone.fixedWidth.map(ceil),
            fixedHeight: zone.fixedHeight.map(ceil),
            isBold: zone.isBold,
            isItalic: zone.isItalic,
            hasBullet: zone.hasBullet,
            fontFamily: zone.fontFamily,
            fontScale: fontScale,
            textVerticalPadding: ceil(textVerticalPadding),
            textHorizontalPaddingOverride: textHorizontalPaddingOverride.map(ceil),
            availableWidth: ceil(availableWidth)
        )
    }

    @ViewBuilder
    private func zoneBlockSurface(layout: ZoneContentLayoutResult) -> some View {
        switch zone.contentType {
        case .empty, .text, .code:
            if !shouldRenderZoneBlockSurface {
                EmptyView()
            } else {
                let tint = zone.highlightColor.zoneSurfaceTint
                RoundedRectangle(cornerRadius: ZoneContentMetrics.zoneCornerRadius, style: .continuous)
                    .fill(zoneSurfaceFill)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: ZoneContentMetrics.zoneCornerRadius, style: .continuous)
                                .strokeBorder(tint.opacity(0.86), style: zoneHighlightStrokeStyle)
                        }
                    }
                    .shadow(color: tint?.opacity(0.16) ?? .clear, radius: tint == nil ? 0 : 3)
                    .frame(width: layout.blockSize.width, height: layout.blockSize.height)
                    .allowsHitTesting(false)
            }
        case .image, .sketch:
            EmptyView()
        }
    }

    private var shouldRenderZoneBlockSurface: Bool {
        showsZoneSurfaces && (!rendersCodeBlock || showsCodeBlockZoneSurfaces || zone.highlightColor != .none)
    }

    private var zoneSurfaceFill: Color {
        guard usesBorderOnlyZoneHighlights, zone.highlightColor != .none else {
            return zone.highlightColor.zoneSurfaceFill
        }
        return HighlightColor.none.zoneSurfaceFill
    }

    @ViewBuilder
    private func leafContent(layout: ZoneContentLayoutResult) -> some View {
        switch zone.contentType {
        case .empty:
            Color.clear.frame(height: 28).padding(.vertical, 4)

        case .text, .code:
            let previewText = displayText(for: zone)
            if !previewText.isEmpty {
                if zone.contentType == .code || previewText.hasPrefix("```") {
                    CodeSnippetView(
                        rawText: previewText,
                        fontSize: codeBlockFontSize(for: zone)
                    )
                        .padding(.vertical, 4)
                        .padding(.horizontal, codeBlockZoneHorizontalPadding(for: layout))
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
        layout: ZoneContentLayoutResult
    ) -> some View {
        let semanticText = MathTextSanitizer.heal(previewText)
        let usesMathRenderer = MathTextSanitizer.containsMath(semanticText)
            || MathTextSanitizer.containsInlineCode(semanticText)
        let textWidthLimit = layout.textWidthLimit ?? max(layout.contentLayoutWidth, 1)
        let intrinsicMeasurementTextWidthLimit = max(
            availableWidth - layout.textHorizontalInsets - layout.bulletHorizontalInset,
            1
        )
        let renderedLineDebugHandler: (([MixedMathRenderedLineDebug]) -> Void)? = collectsDebugMetrics
            ? { lines in
                renderedTokenLines = lines
            }
            : nil
        let scrollableDebugHandler: (([MixedMathScrollableDebug]) -> Void)? = collectsDebugMetrics
            ? { rows in
                renderedScrollableMath = rows
            }
            : nil
        let gestureDebugHandler: ((MixedMathGestureDebugSnapshot) -> Void)? = collectsDebugMetrics
            ? { snapshot in
                mathGestureDebug = snapshot
            }
            : nil
        let showsBullet = zone.hasBullet
            && !previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return HStack(alignment: .top, spacing: showsBullet ? ZoneContentMetrics.bulletSpacing : 0) {
            if showsBullet {
                Circle()
                    .fill(zone.textColor.color)
                    .frame(
                        width: ZoneContentMetrics.bulletWidth,
                        height: ZoneContentMetrics.bulletWidth
                    )
                    .padding(.top, 8)
            }

            if usesMathRenderer {
                MixedMathTextView(
                    text: previewText,
                    fontSize: fontSizeFor(zone),
                    fontFamily: zone.fontFamily,
                    textColor: zone.textColor.color,
                    alignment: layout.resolvedTextAlignment.horizontalAlignment,
                    isBold: zone.isBold,
                    isItalic: zone.isItalic,
                    isInteractive: false,
                    allowsReadOnlyOverflowScrolling: true,
                    intrinsicWidthLimit: textWidthLimit,
                    intrinsicMeasurementWidthLimit: intrinsicMeasurementTextWidthLimit,
                    onIntrinsicContentSizeChange: { size in
                        updateRenderedContentSize(
                            CGSize(
                                width: ceil(size.width + layout.textHorizontalInsets + layout.bulletHorizontalInset),
                                height: ceil(size.height + textVerticalPadding)
                            )
                        )
                    },
                    onRenderedLineDebugChange: renderedLineDebugHandler,
                    onScrollableDebugChange: scrollableDebugHandler,
                    onGestureDebugChange: gestureDebugHandler,
                    showsRenderDebugBounds: showsDebugGuides || collectsDebugMetrics,
                    onTap: leafTapBehavior.allowsRichContentTap ? onTap : nil
                )
                .padding(.vertical, textVerticalPadding / 2)
                .padding(.horizontal, layout.textHorizontalInsets / 2)
            } else {
                ZoneContentPlainTextBlockView(
                    text: previewText,
                    zone: zone,
                    fontScale: fontScale,
                    availableWidth: textWidthLimit,
                    textAlignment: layout.resolvedTextAlignment,
                    onIntrinsicContentSizeChange: { size in
                        updateRenderedContentSize(
                            CGSize(
                                width: ceil(size.width + layout.textHorizontalInsets + layout.bulletHorizontalInset),
                                height: ceil(size.height + textVerticalPadding)
                            )
                        )
                    },
                    onTap: leafTapBehavior.allowsPlainTextTap ? onTap : nil
                )
                .padding(.vertical, textVerticalPadding / 2)
                .padding(.horizontal, layout.textHorizontalInsets / 2)
            }
        }
        .frame(width: layout.contentLayoutWidth, alignment: .topLeading)
    }

    private func updateRenderedContentSize(_ newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        guard isValidRenderedMeasurement(newSize) else { return }
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
        guard isValidRenderedHeight(newHeight) else { return }
        let clampedHeight = max(ceil(newHeight), 1)
        if abs(renderedContentSize.height - clampedHeight) > 0.5 {
            renderedContentSize = CGSize(
                width: isValidRenderedWidth(renderedContentSize.width) ? renderedContentSize.width : 0,
                height: clampedHeight
            )
        }
    }

    private func isValidRenderedMeasurement(_ size: CGSize) -> Bool {
        isValidRenderedWidth(size.width) && isValidRenderedHeight(size.height)
    }

    private func isValidRenderedWidth(_ width: CGFloat) -> Bool {
        guard requiresStableTextMeasurement else { return width > 0 }
        return width >= minimumValidRenderedWidth
    }

    private func isValidRenderedHeight(_ height: CGFloat) -> Bool {
        guard requiresStableTextMeasurement else { return height > 0 }
        return height >= minimumValidRenderedHeight
    }

    private var requiresStableTextMeasurement: Bool {
        guard zone.contentType == .text else { return false }
        return !displayText(for: zone).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var minimumValidRenderedWidth: CGFloat {
        let bulletInset = zone.hasBullet
            ? ZoneContentMetrics.bulletWidth + ZoneContentMetrics.bulletSpacing
            : 0
        return min(
            max(resolvedTextHorizontalPadding + bulletInset + 8, 1),
            availableWidth
        )
    }

    private var resolvedTextHorizontalPadding: CGFloat {
        textHorizontalPaddingOverride ?? ZoneContentMetrics.textHorizontalPadding
    }

    private var minimumValidRenderedHeight: CGFloat {
        min(max(textVerticalPadding / 2, 8), 24)
    }

    private func debugSnapshot(
        layout: ZoneContentLayoutResult,
        layoutZone: ZoneModel
    ) -> ZoneContentLeafLayoutDebugSnapshot {
        let rawText = zone.text
        let displayText = zone.contentType == .text ? displayText(for: zone) : zone.text
        let healedText = MathTextSanitizer.heal(displayText)
        let containsMath = MathTextSanitizer.containsMath(healedText)
        let containsInlineCode = MathTextSanitizer.containsInlineCode(healedText)
        let effectiveTextWidthLimit = layout.textWidthLimit ?? max(layout.contentLayoutWidth, 1)
        let estimatedLineWidths = zone.contentType == .text
            ? ZoneContentEstimator.debugLineWidths(
                for: zone,
                fontScale: fontScale,
                availableWidth: effectiveTextWidthLimit
            )
            : []
        let renderedLineLayout = zone.contentType == .text && !containsMath && !containsInlineCode
            ? ZoneContentPlainTextLayoutMeasurer.layout(
                text: displayText,
                zone: zone,
                fontScale: fontScale,
                availableWidth: effectiveTextWidthLimit
            )
            : .empty

        return ZoneContentLeafLayoutDebugSnapshot(
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
            zoneSizeMode: layoutZone.sizeMode,
            zoneBlockAlignment: layoutZone.blockAlignment,
            zoneTextAlignment: layoutZone.textAlignment,
            usesNaturalBlockCentering: layout.usesAutoBlockCentering,
            textStyle: zone.textStyle,
            fontFamily: zone.fontFamily,
            isBold: zone.isBold,
            isItalic: zone.isItalic,
            hasBullet: zone.hasBullet,
            highlightColor: zone.highlightColor,
            containsMath: containsMath,
            containsInlineCode: containsInlineCode,
            rawTextCharacterCount: rawText.count,
            rawTextLineCount: max(rawText.components(separatedBy: .newlines).count, 1),
            rawText: rawText,
            normalizedDisplayText: displayText,
            healedDisplayText: healedText,
            textCharacterCount: displayText.count,
            textLineCount: max(displayText.components(separatedBy: .newlines).count, 1),
            estimatedLineWidths: estimatedLineWidths.map(ceil),
            renderedLineTexts: renderedLineLayout.lines.map(\.plainText),
            renderedLineWidths: renderedLineLayout.lines.map { ceil($0.width) },
            renderedTokenLines: containsMath || containsInlineCode ? renderedTokenLines : [],
            renderedScrollableMath: containsMath || containsInlineCode ? renderedScrollableMath : [],
            mathGestureDebug: containsMath || containsInlineCode ? mathGestureDebug : nil,
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
            return ZoneContentDisplayTextNormalizer.textZoneDisplayText(zone.text)
        default:
            return zone.text
        }
    }

    private func fontSizeFor(_ zone: ZoneModel) -> CGFloat {
        ZoneTextTypography.fontSize(for: zone.textStyle, fontScale: fontScale)
    }

    private func codeBlockFontSize(for zone: ZoneModel) -> CGFloat {
        fontSizeFor(zone) * CodeSnippetMetrics.relativeFontScale
    }

    private func codeBlockZoneHorizontalPadding(for layout: ZoneContentLayoutResult) -> CGFloat {
        showsCodeBlockZoneSurfaces ? layout.textHorizontalInsets / 2 : 0
    }

    private var rendersCodeBlock: Bool {
        zone.contentType == .code || displayText(for: zone).hasPrefix("```")
    }
}

// MARK: - Zone Content Content Metrics

enum ZoneContentMetrics {
    static let childSpacing: CGFloat = 12
    static let textVerticalPadding: CGFloat = 24
    static let textHorizontalPadding: CGFloat = 24
    static let zoneCornerRadius: CGFloat = 24
    static let highlightedHorizontalPadding: CGFloat = textHorizontalPadding
    static let bulletWidth: CGFloat = 6
    static let bulletSpacing: CGFloat = 8
}

// MARK: - Plain Text Zone Layout

private struct ZoneContentPlainTextBlockView: View {
    let text: String
    let zone: ZoneModel
    let fontScale: CGFloat
    let availableWidth: CGFloat
    let textAlignment: TextBlockAlignment
    var onIntrinsicContentSizeChange: ((CGSize) -> Void)?
    var onTap: (() -> Void)?

    private var layout: ZoneContentPlainTextLineLayout {
        ZoneContentPlainTextLayoutMeasurer.layout(
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
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: line.width, alignment: .leading)
            }
        }
        .frame(width: max(availableWidth, layout.size.width), alignment: frameAlignment)
        .zoneContentPlainTextTap(onTap)
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

private extension View {
    @ViewBuilder
    func zoneContentPlainTextTap(_ onTap: (() -> Void)?) -> some View {
        if let onTap {
            contentShape(Rectangle())
                .onTapGesture(perform: onTap)
        } else {
            self
        }
    }
}

private enum ZoneContentPlainTextLayoutMeasurer {
    static func layout(
        text rawText: String,
        zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> ZoneContentPlainTextLineLayout {
        let text = rawText.replacingOccurrences(of: "\r\n", with: "\n")
        let widthLimit = max(availableWidth, 1)
        let lineSpacing = max(floor(fontSize(for: zone) * fontScale * 0.26), 6)

        guard !text.isEmpty else {
            let emptyLine = ZoneContentPlainTextLine(tokens: [], width: 1, height: lineHeight(for: zone, fontScale: fontScale))
            return ZoneContentPlainTextLineLayout(lines: [emptyLine], lineSpacing: lineSpacing)
        }

        let sourceLines = text.components(separatedBy: .newlines)
        var output: [ZoneContentPlainTextLine] = []

        for sourceLine in sourceLines {
            let tokens = tokens(for: sourceLine, zone: zone, fontScale: fontScale)
            guard !tokens.isEmpty else {
                output.append(ZoneContentPlainTextLine(tokens: [], width: 1, height: lineHeight(for: zone, fontScale: fontScale)))
                continue
            }

            var current: [ZoneContentPlainTextToken] = []
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
            output.append(ZoneContentPlainTextLine(tokens: [], width: 1, height: lineHeight(for: zone, fontScale: fontScale)))
        }

        return ZoneContentPlainTextLineLayout(lines: output, lineSpacing: lineSpacing)
    }

    private static func tokens(
        for text: String,
        zone: ZoneModel,
        fontScale: CGFloat
    ) -> [ZoneContentPlainTextToken] {
        var tokens: [ZoneContentPlainTextToken] = []
        var cursor = text.startIndex
        var isEmphasized = false

        func appendToken(_ value: String, emphasized: Bool) {
            guard !value.isEmpty else { return }
            let attributes = attributes(for: zone, fontScale: fontScale, emphasized: emphasized)
            tokens.append(
                ZoneContentPlainTextToken(
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

    private static func normalizedLineTokens(_ tokens: [ZoneContentPlainTextToken]) -> [ZoneContentPlainTextToken] {
        tokens.filter { !$0.text.isEmpty }
    }

    private static func splitOversizedToken(
        _ token: ZoneContentPlainTextToken,
        widthLimit: CGFloat
    ) -> (lineToken: ZoneContentPlainTextToken, remainingToken: ZoneContentPlainTextToken) {
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
        from tokens: [ZoneContentPlainTextToken],
        zone: ZoneModel,
        fontScale: CGFloat
    ) -> ZoneContentPlainTextLine {
        let normalized = normalizedLineTokens(tokens)
        return ZoneContentPlainTextLine(
            tokens: normalized,
            width: min(max(ceil(measuredWidth(for: normalized)), 1), .greatestFiniteMagnitude),
            height: lineHeight(for: zone, fontScale: fontScale)
        )
    }

    private static func measuredWidth(for tokens: [ZoneContentPlainTextToken]) -> CGFloat {
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
        ZoneTextTypography.uiFont(
            family: zone.fontFamily,
            style: zone.textStyle,
            isBold: false,
            isItalic: zone.isItalic,
            fontScale: fontScale,
            emphasized: weight == .bold
        )
    }

    private static func swiftUIFont(
        for zone: ZoneModel,
        fontScale: CGFloat,
        weight: Font.Weight
    ) -> Font {
        ZoneTextTypography.font(
            family: zone.fontFamily,
            style: zone.textStyle,
            isBold: false,
            isItalic: zone.isItalic,
            fontScale: fontScale,
            emphasized: weight == .bold
        )
    }

    private static func fontWeight(for zone: ZoneModel, emphasized: Bool) -> UIFont.Weight {
        ZoneTextTypography.uiFontWeight(for: zone.textStyle, isBold: zone.isBold, emphasized: emphasized)
    }

    private static func swiftUIFontWeight(for zone: ZoneModel, emphasized: Bool) -> Font.Weight {
        ZoneTextTypography.fontWeight(for: zone.textStyle, isBold: zone.isBold, emphasized: emphasized)
    }

    private static func fontSize(for zone: ZoneModel) -> CGFloat {
        ZoneTextTypography.baseFontSize(for: zone.textStyle)
    }
}

private struct ZoneContentPlainTextLineLayout: Equatable {
    let lines: [ZoneContentPlainTextLine]
    let lineSpacing: CGFloat

    static let empty = ZoneContentPlainTextLineLayout(lines: [], lineSpacing: 0)

    var size: CGSize {
        let widest = lines.map(\.width).max() ?? 1
        let totalLineHeight = lines.reduce(CGFloat(0)) { $0 + $1.height }
        let totalSpacing = CGFloat(max(lines.count - 1, 0)) * lineSpacing
        return CGSize(width: ceil(max(widest, 1)), height: ceil(max(totalLineHeight + totalSpacing, 1)))
    }
}

private struct ZoneContentPlainTextLine: Equatable {
    let tokens: [ZoneContentPlainTextToken]
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

private struct ZoneContentPlainTextToken: Equatable {
    let text: String
    let attributes: [NSAttributedString.Key: Any]
    let font: Font
    let isItalic: Bool
    let emphasized: Bool

    static func == (lhs: ZoneContentPlainTextToken, rhs: ZoneContentPlainTextToken) -> Bool {
        lhs.text == rhs.text && lhs.isItalic == rhs.isItalic && lhs.emphasized == rhs.emphasized
    }

    var isEmpty: Bool {
        text.isEmpty
    }

    func trimmedLeadingWhitespace() -> ZoneContentPlainTextToken {
        replacingText(String(text.drop(while: \.isWhitespace)))
    }

    func trimmedTrailingWhitespace() -> ZoneContentPlainTextToken {
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

    func replacingText(_ value: String) -> ZoneContentPlainTextToken {
        ZoneContentPlainTextToken(
            text: value,
            attributes: attributes,
            font: font,
            isItalic: isItalic,
            emphasized: emphasized
        )
    }
}

// MARK: - Zone Content Content Estimator

enum ZoneContentEstimator {
    private static let childSpacing = ZoneContentMetrics.childSpacing
    private static let textHorizontalPadding = ZoneContentMetrics.textHorizontalPadding
    private static let highlightedHorizontalPadding = ZoneContentMetrics.highlightedHorizontalPadding
    private static let bulletWidth = ZoneContentMetrics.bulletWidth
    private static let bulletSpacing = ZoneContentMetrics.bulletSpacing

    static func estimatedSize(
        for zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat,
        textVerticalPadding: CGFloat = ZoneContentMetrics.textVerticalPadding,
        textHorizontalPaddingOverride: CGFloat? = nil
    ) -> CGSize {
        let clampedWidth = max(availableWidth, 1)

        guard ZoneContentRenderPolicy.shouldRender(zone) else {
            return CGSize(width: 1, height: 36)
        }

        if zone.isLeaf {
            return estimatedLeafSize(
                for: zone,
                fontScale: fontScale,
                availableWidth: clampedWidth,
                textVerticalPadding: textVerticalPadding,
                textHorizontalPaddingOverride: textHorizontalPaddingOverride
            )
        }

        let children = zone.children?.filter(ZoneContentRenderPolicy.shouldRender) ?? []
        guard !children.isEmpty else {
            return CGSize(width: 1, height: 36)
        }

        switch zone.direction {
        case .vertical:
            let childSizes = children.map {
                estimatedSize(
                    for: $0,
                    fontScale: fontScale,
                    availableWidth: clampedWidth,
                    textVerticalPadding: textVerticalPadding,
                    textHorizontalPaddingOverride: textHorizontalPaddingOverride
                )
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
                estimatedSize(
                    for: $0,
                    fontScale: fontScale,
                    availableWidth: childWidth,
                    textVerticalPadding: textVerticalPadding,
                    textHorizontalPaddingOverride: textHorizontalPaddingOverride
                )
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
        availableWidth: CGFloat,
        textVerticalPadding: CGFloat = ZoneContentMetrics.textVerticalPadding,
        textHorizontalPaddingOverride: CGFloat? = nil
    ) -> CGFloat {
        let clampedWidth = max(availableWidth, 1)

        guard ZoneContentRenderPolicy.shouldRender(zone) else {
            return 1
        }

        if zone.isLeaf {
            let measuredSize = estimatedLeafSize(
                for: zone,
                fontScale: fontScale,
                availableWidth: clampedWidth,
                textVerticalPadding: textVerticalPadding,
                textHorizontalPaddingOverride: textHorizontalPaddingOverride
            )
            let layout = ZoneContentLayoutEngine.leafLayout(
                for: zone,
                spec: ZoneContentLayoutSpec(
                    availableWidth: clampedWidth,
                    fontScale: fontScale,
                    textVerticalPadding: textVerticalPadding,
                    textHorizontalPaddingOverride: textHorizontalPaddingOverride
                ),
                measuredContentSize: measuredSize
            )

            return min(max(ceil(layout.blockSize.width), 1), clampedWidth)
        }

        let children = zone.children?.filter(ZoneContentRenderPolicy.shouldRender) ?? []
        guard !children.isEmpty else { return 1 }

        switch zone.direction {
        case .vertical:
            return children
                .map {
                    estimatedBlockWidth(
                        for: $0,
                        fontScale: fontScale,
                        availableWidth: clampedWidth,
                        textVerticalPadding: textVerticalPadding,
                        textHorizontalPaddingOverride: textHorizontalPaddingOverride
                    )
                }
                .max() ?? 1

        case .horizontal:
            return estimatedSize(
                for: zone,
                fontScale: fontScale,
                availableWidth: clampedWidth,
                textVerticalPadding: textVerticalPadding,
                textHorizontalPaddingOverride: textHorizontalPaddingOverride
            )
            .width
        }
    }

    static func debugLineWidths(
        for zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> [CGFloat] {
        let displayText = ZoneContentDisplayTextNormalizer.textZoneDisplayText(zone.text)
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
        availableWidth: CGFloat,
        textVerticalPadding: CGFloat,
        textHorizontalPaddingOverride: CGFloat?
    ) -> CGSize {
        switch zone.contentType {
        case .empty:
            return CGSize(width: 1, height: 36)

        case .text:
            let displayText = ZoneContentDisplayTextNormalizer.textZoneDisplayText(zone.text)
            let horizontalInsets = textHorizontalPaddingOverride ?? textHorizontalPadding
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
            let codeSize = measuredCodeBlockSize(
                strippedCodeText(zone.text),
                zone: zone,
                fontScale: fontScale,
                availableWidth: availableWidth
            )

            return CGSize(
                width: codeSize.width,
                height: codeSize.height
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

    private static func measuredCodeBlockSize(
        _ value: String,
        zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> CGSize {
        let text = value.replacingOccurrences(of: "\r\n", with: "\n")
        let measuredText = text.isEmpty ? " " : text
        let font = UIFont.monospacedSystemFont(
            ofSize: codeBlockFontSize(for: zone, fontScale: fontScale),
            weight: .regular
        )
        let textRect = (measuredText as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        let horizontalPadding = CodeSnippetMetrics.contentPadding * 2
        let verticalPadding = CodeSnippetMetrics.contentPadding * 2 + 8

        return CGSize(
            width: min(ceil(textRect.width + horizontalPadding), availableWidth),
            height: ceil(textRect.height + verticalPadding)
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

        let lineLayout = ZoneContentPlainTextLayoutMeasurer.layout(
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
            let resolvedWidth = preferredWidth <= availableWidth
                ? max(lineLayout.size.width, preferredWidth)
                : lineLayout.size.width

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
        ZoneTextTypography.uiFont(
            for: zone,
            fontScale: fontScale,
            emphasized: emphasized,
            monospaced: monospaced
        )
    }

    private static func fontWeight(for zone: ZoneModel, emphasized: Bool) -> UIFont.Weight {
        ZoneTextTypography.uiFontWeight(for: zone.textStyle, isBold: zone.isBold, emphasized: emphasized)
    }

    private static func fontSize(for zone: ZoneModel) -> CGFloat {
        ZoneTextTypography.baseFontSize(for: zone.textStyle)
    }

    private static func codeBlockFontSize(for zone: ZoneModel, fontScale: CGFloat) -> CGFloat {
        fontSize(for: zone) * fontScale * CodeSnippetMetrics.relativeFontScale
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

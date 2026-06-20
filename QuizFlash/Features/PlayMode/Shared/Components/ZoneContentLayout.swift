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
    let measurementSource: String
    let contentBodyHeight: CGFloat
    let contentFitsVertically: Bool
    let centeredTopInset: CGFloat
    let scrollContentHeight: CGFloat
    let faceDebugEvents: [String]
    let leafSnapshots: [ZoneContentLeafLayoutDebugSnapshot]
}

struct ZoneContentLeafLayoutDebugSnapshot: Equatable {
    let path: String
    let zoneID: UUID
    let contentType: ZoneContentType
    let hasContent: Bool
    let rawBlockAlignment: ZoneBlockAlignment
    let resolvedBlockAlignment: ZoneBlockAlignment
    let availableWidth: CGFloat
    let estimatedSize: CGSize
    let renderedContentSize: CGSize
    let measurementUpdateCount: Int
    let measurementResetCount: Int
    let rawMeasuredContentSize: CGSize
    let blockSize: CGSize
    let leadingInset: CGFloat
    let contentFrameHeight: CGFloat?
    let contentLayoutWidth: CGFloat
    let textWidthLimit: CGFloat?
    let textHorizontalInsets: CGFloat
    let blockHeightSlack: CGFloat
    let usesIntrinsicTextMeasurement: Bool
    let zoneSizeMode: ZoneSizeMode
    let textStyle: TextBlockStyle
    let fontFamily: FontFamily
    let isBold: Bool
    let isItalic: Bool
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
    let renderStatusDebug: MixedMathRenderStatusDebug?
    let nativeRenderDebug: MixedMathNativeRenderDebug?
    let lastMeasurementSource: String
    let lastMeasurementDecision: String
    let measurementEvents: [String]
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

struct ZoneContentRenderBlockBounds: Equatable {
    let zoneID: UUID
    let path: String
    let kind: String
    let frame: CGRect
    let availableWidth: CGFloat
    let blockSize: CGSize
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let rawBlockAlignment: ZoneBlockAlignment
    let resolvedBlockAlignment: ZoneBlockAlignment
    let textHorizontalInsets: CGFloat
    let textVerticalPadding: CGFloat
    let contentLayoutWidth: CGFloat
    let textWidthLimit: CGFloat?
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

enum ZoneMediaMetrics {
    static func displaySize(for zone: ZoneModel, availableWidth: CGFloat) -> CGSize {
        let clampedAvailableWidth = max(availableWidth, 1)
        let ratio = imageHeightRatio(for: zone.imageData)
        let width: CGFloat

        if let fixedWidth = zone.fixedWidth {
            width = min(max(ceil(fixedWidth), 1), clampedAvailableWidth)
        } else if let fixedHeight = zone.fixedHeight {
            width = min(max(ceil(fixedHeight / ratio), 1), clampedAvailableWidth)
        } else {
            width = min(clampedAvailableWidth, max(clampedAvailableWidth * zone.imageScale, 1))
        }

        return CGSize(width: width, height: max(ceil(width * ratio), 1))
    }

    static func imageHeightRatio(for data: Data?) -> CGFloat {
        guard let data,
              let image = UIImage(data: data),
              image.size.width > 0,
              image.size.height > 0 else {
            return 0.66
        }

        return max(image.size.height / image.size.width, 0.05)
    }
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
    let sizeMode: ZoneSizeMode
    let fixedWidth: CGFloat?
    let fixedHeight: CGFloat?
    let isBold: Bool
    let isItalic: Bool
    let fontFamily: FontFamily
    let fontScale: CGFloat
    let textVerticalPadding: CGFloat
    let textHorizontalPaddingOverride: CGFloat?
    let availableWidth: CGFloat

    func matchesContent(of other: Self) -> Bool {
        id == other.id
            && contentType == other.contentType
            && text == other.text
            && textStyle == other.textStyle
            && sizeMode == other.sizeMode
            && fixedWidth == other.fixedWidth
            && fixedHeight == other.fixedHeight
            && isBold == other.isBold
            && isItalic == other.isItalic
            && fontFamily == other.fontFamily
            && fontScale == other.fontScale
            && textVerticalPadding == other.textVerticalPadding
            && textHorizontalPaddingOverride == other.textHorizontalPaddingOverride
    }
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

enum ZoneContentDebugGuideStyle: Equatable {
    case debug
    case editorRender
}

private struct ZoneContentSurfaceCornerRadiusKey: EnvironmentKey {
    static let defaultValue = ZoneContentMetrics.zoneCornerRadius
}

extension EnvironmentValues {
    var zoneContentSurfaceCornerRadius: CGFloat {
        get { self[ZoneContentSurfaceCornerRadiusKey.self] }
        set { self[ZoneContentSurfaceCornerRadiusKey.self] = newValue }
    }
}

@ViewBuilder
private func zoneAlignmentHighlight(
    cornerRadius: CGFloat = 16,
    lineWidth: CGFloat = 1.6,
    shadowRadius: CGFloat = 8
) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(
            ThemeManager.shared.accentColor.color.opacity(0.78),
            lineWidth: lineWidth
        )
        .shadow(
            color: ThemeManager.shared.accentColor.color.opacity(0.24),
            radius: shadowRadius
        )
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
        let measuredHeight = ceil(measuredContentSize.height)
        let minimumPlausibleMeasuredHeight = max(1, estimatedHeight * 0.25)

        if measuredHeight >= minimumPlausibleMeasuredHeight {
            return max(measuredHeight, 1)
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
    var debugGuideStyle: ZoneContentDebugGuideStyle = .debug
    var textVerticalPadding: CGFloat = ZoneContentMetrics.textVerticalPadding
    var textHorizontalPaddingOverride: CGFloat? = nil
    var alignmentFeedback: ZoneAlignmentFeedback = .inactive
    let collectsDebugMetrics: Bool
    var leafTapBehavior: ZoneContentLeafTapBehavior = .all
    var onTap: (() -> Void)?
    var onZoneTap: ((UUID) -> Void)?
    var onBlockBoundsChange: (([ZoneContentRenderBlockBounds]) -> Void)?
    var onRootBlockWidthChange: ((CGFloat) -> Void)?

    var body: some View {
        ZoneContentTreePreview(
            zone: zone,
            path: "root",
            suppressOwnEditorRenderGuide: false,
            representsSelectedGroupGuide: false,
            fontScale: fontScale,
            availableWidth: max(availableWidth, 1),
            centersLeafBlocks: centersLeafBlocks,
            alignLeafBlocksToGroupLeading: alignLeafBlocksToGroupLeading,
            showsDebugGuides: showsDebugGuides,
            showsZoneSurfaces: showsZoneSurfaces,
            showsCodeBlockZoneSurfaces: showsCodeBlockZoneSurfaces,
            usesBorderOnlyZoneHighlights: usesBorderOnlyZoneHighlights,
            zoneHighlightStrokeStyle: zoneHighlightStrokeStyle,
            debugGuideStyle: debugGuideStyle,
            textVerticalPadding: textVerticalPadding,
            textHorizontalPaddingOverride: textHorizontalPaddingOverride,
            alignmentFeedback: alignmentFeedback,
            collectsDebugMetrics: collectsDebugMetrics,
            leafTapBehavior: leafTapBehavior,
            onTap: onTap,
            onZoneTap: onZoneTap
        )
            .frame(width: max(availableWidth, 1), alignment: .topLeading)
            .onPreferenceChange(ZoneContentWidthPreferenceKey.self) { widths in
            guard let width = widths["root"], width > 0 else { return }
            onRootBlockWidthChange?(ceil(width))
        }
            .onPreferenceChange(ZoneContentRenderBlockBoundsPreferenceKey.self) { bounds in
            onBlockBoundsChange?(bounds.sorted { $0.path < $1.path })
        }
    }
}

// MARK: - Zone Content Zone Preview

enum ZoneContentRenderPolicy {
    nonisolated static func shouldRender(_ zone: ZoneModel) -> Bool {
        if zone.hasContent || zone.highlightColor != .none || zone.sizeMode == .fixed {
            return true
        }

        return zone.children?.contains(where: shouldRender) ?? false
    }

    nonisolated static func renderableLeafCount(in zone: ZoneModel) -> Int {
        guard shouldRender(zone) else { return 0 }
        guard !zone.isLeaf else { return 1 }

        return zone.children?.reduce(into: 0) { count, child in
            count += renderableLeafCount(in: child)
        } ?? 0
    }
}

private struct ZoneContentTreePreview: View {
    let zone: ZoneModel
    let path: String
    let suppressOwnEditorRenderGuide: Bool
    let representsSelectedGroupGuide: Bool
    let fontScale: CGFloat
    let availableWidth: CGFloat
    let centersLeafBlocks: Bool
    let alignLeafBlocksToGroupLeading: Bool
    let showsDebugGuides: Bool
    let showsZoneSurfaces: Bool
    let showsCodeBlockZoneSurfaces: Bool
    let usesBorderOnlyZoneHighlights: Bool
    let zoneHighlightStrokeStyle: StrokeStyle
    let debugGuideStyle: ZoneContentDebugGuideStyle
    let textVerticalPadding: CGFloat
    let textHorizontalPaddingOverride: CGFloat?
    let alignmentFeedback: ZoneAlignmentFeedback
    let collectsDebugMetrics: Bool
    let leafTapBehavior: ZoneContentLeafTapBehavior
    var onTap: (() -> Void)?
    var onZoneTap: ((UUID) -> Void)?

    @State private var measuredDirectChildWidths: [String: CGFloat] = [:]

    var body: some View {
        if zone.isLeaf {
            ZoneContentLeafPreview(
                zone: zone,
                path: path,
                suppressOwnEditorRenderGuide: suppressOwnEditorRenderGuide,
                representsSelectedGroupGuide: representsSelectedGroupGuide,
                fontScale: fontScale,
                availableWidth: availableWidth,
                centersLeafBlocks: centersLeafBlocks,
                alignLeafBlocksToGroupLeading: alignLeafBlocksToGroupLeading,
                showsDebugGuides: showsDebugGuides,
                showsZoneSurfaces: showsZoneSurfaces,
                showsCodeBlockZoneSurfaces: showsCodeBlockZoneSurfaces,
                usesBorderOnlyZoneHighlights: usesBorderOnlyZoneHighlights,
                zoneHighlightStrokeStyle: zoneHighlightStrokeStyle,
                debugGuideStyle: debugGuideStyle,
                textVerticalPadding: textVerticalPadding,
                textHorizontalPaddingOverride: textHorizontalPaddingOverride,
                alignmentFeedback: alignmentFeedback,
                collectsDebugMetrics: collectsDebugMetrics,
                leafTapBehavior: leafTapBehavior,
                onTap: onTap,
                onZoneTap: onZoneTap
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
                        suppressOwnEditorRenderGuide: false,
                        representsSelectedGroupGuide: false,
                        fontScale: fontScale,
                        availableWidth: childWidth,
                        centersLeafBlocks: centersLeafBlocks,
                        alignLeafBlocksToGroupLeading: alignLeafBlocksToGroupLeading,
                        showsDebugGuides: showsDebugGuides,
                        showsZoneSurfaces: showsZoneSurfaces,
                        showsCodeBlockZoneSurfaces: showsCodeBlockZoneSurfaces,
                        usesBorderOnlyZoneHighlights: usesBorderOnlyZoneHighlights,
                        zoneHighlightStrokeStyle: zoneHighlightStrokeStyle,
                        debugGuideStyle: debugGuideStyle,
                        textVerticalPadding: textVerticalPadding,
                        textHorizontalPaddingOverride: textHorizontalPaddingOverride,
                        alignmentFeedback: alignmentFeedback,
                        collectsDebugMetrics: collectsDebugMetrics,
                        leafTapBehavior: leafTapBehavior,
                        onTap: onTap,
                        onZoneTap: onZoneTap
                    )
                        .frame(width: childWidth, alignment: .topLeading)
                }
            }
                .frame(width: availableWidth, alignment: .topLeading)
                .background {
                groupBlockBounds(
                    blockWidth: availableWidth,
                    leadingInset: 0,
                    rawAlignment: zone.blockAlignment,
                    resolvedAlignment: .leading
                )
            }
        } else {
            let childPaths = indexedChildren.map { "\(path).\($0.offset)" }
            let containerIdentity = verticalContainerMeasurementIdentity(for: children)
            let groupWidth = verticalGroupWidth(for: children, childPaths: childPaths)
            let groupTarget = zonePath.map { ZoneAlignmentTargetRef(path: $0, kind: .group) }
            let groupWiggleOffset = groupTarget.map { alignmentFeedback.offset(for: $0) } ?? 0
            let resolvedGroupAlignment: ZoneBlockAlignment = zone.blockAlignment == .auto ? .center : zone.blockAlignment
            let groupLeadingInset = ZoneContentLayoutEngine.blockLeadingInset(
                for: resolvedGroupAlignment,
                blockWidth: groupWidth,
                availableWidth: availableWidth
            )

            HStack(spacing: 0) {
                Color.clear.frame(width: groupLeadingInset)

                VStack(alignment: .leading, spacing: ZoneContentMetrics.childSpacing) {
                    ForEach(indexedChildren, id: \.element.id) { index, child in
                        ZoneContentTreePreview(
                            zone: child,
                            path: "\(path).\(index)",
                            suppressOwnEditorRenderGuide: shouldSuppressGuide(
                                for: child,
                                childPath: "\(path).\(index)",
                                childCount: children.count,
                                groupWidth: groupWidth
                            ),
                            representsSelectedGroupGuide: children.count == 1
                                && alignmentFeedback.highlightedTarget == groupTarget,
                            fontScale: fontScale,
                            availableWidth: groupWidth,
                            centersLeafBlocks: centersLeafBlocks,
                            alignLeafBlocksToGroupLeading: false,
                            showsDebugGuides: showsDebugGuides,
                            showsZoneSurfaces: showsZoneSurfaces,
                            showsCodeBlockZoneSurfaces: showsCodeBlockZoneSurfaces,
                            usesBorderOnlyZoneHighlights: usesBorderOnlyZoneHighlights,
                            zoneHighlightStrokeStyle: zoneHighlightStrokeStyle,
                            debugGuideStyle: debugGuideStyle,
                            textVerticalPadding: textVerticalPadding,
                            textHorizontalPaddingOverride: textHorizontalPaddingOverride,
                            alignmentFeedback: alignmentFeedback,
                            collectsDebugMetrics: collectsDebugMetrics,
                            leafTapBehavior: leafTapBehavior,
                            onTap: onTap,
                            onZoneTap: onZoneTap
                        )
                            .frame(width: groupWidth, alignment: .topLeading)
                    }
                }
                    .frame(width: groupWidth, alignment: .topLeading)
                    .background {
                    groupBlockBounds(
                        blockWidth: groupWidth,
                        leadingInset: groupLeadingInset,
                        rawAlignment: zone.blockAlignment,
                        resolvedAlignment: resolvedGroupAlignment
                    )
                }
                    .overlay {
                    ZStack {
                        if let groupTarget,
                           children.count > 1,
                           !suppressOwnEditorRenderGuide {
                            let isSelected = alignmentFeedback.highlightedTarget == groupTarget

                            if isSelected {
                                zoneAlignmentHighlight(
                                    cornerRadius: groupDebugGuideCornerRadius,
                                    lineWidth: 1.6,
                                    shadowRadius: 8
                                )
                                    .padding(groupDebugGuideInsets)
                            } else if showsDebugGuides {
                                RoundedRectangle(
                                    cornerRadius: groupDebugGuideCornerRadius,
                                    style: .continuous
                                )
                                    .strokeBorder(
                                        groupDebugGuideColor,
                                        style: StrokeStyle(lineWidth: 1.4, dash: [8, 5])
                                    )
                                    .padding(groupDebugGuideInsets)
                                    .allowsHitTesting(false)
                            }
                        }
                    }

                        .animation(.easeInOut(duration: 0.22), value: alignmentFeedback.highlightedTarget)
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

    private func groupBlockBounds(
        blockWidth: CGFloat,
        leadingInset: CGFloat,
        rawAlignment: ZoneBlockAlignment,
        resolvedAlignment: ZoneBlockAlignment
    ) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ZoneContentRenderBlockBoundsPreferenceKey.self,
                value: [
                    ZoneContentRenderBlockBounds(
                        zoneID: zone.id,
                        path: path,
                        kind: "group",
                        frame: proxy.frame(in: .named(ZoneContentRenderCoordinateSpace.name)),
                        availableWidth: availableWidth,
                        blockSize: CGSize(width: blockWidth, height: proxy.size.height),
                        leadingInset: leadingInset,
                        trailingInset: max(availableWidth - leadingInset - blockWidth, 0),
                        rawBlockAlignment: rawAlignment,
                        resolvedBlockAlignment: resolvedAlignment,
                        textHorizontalInsets: 0,
                        textVerticalPadding: 0,
                        contentLayoutWidth: blockWidth,
                        textWidthLimit: nil
                    )
                ]
            )
        }
        .allowsHitTesting(false)
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

            let resolvedWidth = children.allSatisfy(requiresIntrinsicTextWidthFloor(for:))
                ? max(measuredWidth, estimatedWidth)
                : measuredWidth
            return min(max(ceil(resolvedWidth), 1), availableWidth)
        }

        return min(max(ceil(estimatedWidth), 1), availableWidth)
    }

    private func shouldSuppressGuide(
        for child: ZoneModel,
        childPath: String,
        childCount: Int,
        groupWidth: CGFloat
    ) -> Bool {
        guard debugGuideStyle == .editorRender, childCount > 1 else {
            return false
        }

        let childWidth = measuredDirectChildWidths[childPath]
            ?? ZoneContentEstimator.estimatedBlockWidth(
                for: child,
                fontScale: fontScale,
                availableWidth: availableWidth,
                textVerticalPadding: textVerticalPadding,
                textHorizontalPaddingOverride: textHorizontalPaddingOverride
            )

        return childWidth >= groupWidth - 1
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
            case .text where requiresIntrinsicTextWidthFloor(for: child):
                let estimatedWidth = ZoneContentEstimator.estimatedBlockWidth(
                    for: child,
                    fontScale: fontScale,
                    availableWidth: availableWidth,
                    textVerticalPadding: textVerticalPadding,
                    textHorizontalPaddingOverride: textHorizontalPaddingOverride
                )
                return min(
                    max(ceil(estimatedWidth), resolvedTextHorizontalPadding + 8, 1),
                    availableWidth
                )
            case .text, .code:
                return min(max(resolvedTextHorizontalPadding + 8, 1), availableWidth)
            case .empty:
                return min(max(resolvedTextHorizontalPadding + 8, 1), availableWidth)
            case .image, .sketch:
                let estimatedWidth = ZoneContentEstimator.estimatedBlockWidth(
                    for: child,
                    fontScale: fontScale,
                    availableWidth: availableWidth,
                    textVerticalPadding: textVerticalPadding,
                    textHorizontalPaddingOverride: textHorizontalPaddingOverride
                )
                return min(max(ceil(estimatedWidth), 1), availableWidth)
            }
        }

        let childMinimum = child.children?
            .filter(ZoneContentRenderPolicy.shouldRender)
            .map(minimumValidMeasuredWidth(for:))
            .max() ?? 1

        return min(max(childMinimum, 1), availableWidth)
    }

    private func requiresIntrinsicTextWidthFloor(for child: ZoneModel) -> Bool {
        guard child.contentType == .text else { return false }
        let previewText = ZoneContentDisplayTextNormalizer.textZoneDisplayText(child.text)
        guard !previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let healedText = MathTextSanitizer.heal(previewText)
        return !MathTextSanitizer.containsMath(healedText)
            && !MathTextSanitizer.containsInlineCode(healedText)
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
            sizeMode: child.sizeMode,
            fixedWidth: child.fixedWidth.map(ceil),
            fixedHeight: child.fixedHeight.map(ceil),
            isBold: child.isBold,
            isItalic: child.isItalic,
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

    private var groupDebugGuideColor: Color {
        switch debugGuideStyle {
        case .debug:
            Color.red.opacity(0.95)
        case .editorRender:
            Color.gray.opacity(0.58)
        }
    }

    private var groupDebugGuideCornerRadius: CGFloat {
        ZoneContentMetrics.zoneCornerRadius + 8
    }

    private var groupDebugGuideInsets: EdgeInsets {
        switch debugGuideStyle {
        case .debug:
            return EdgeInsets()
        case .editorRender:
            let horizontalOutset = FlashcardPlayLayoutTuning.cardToContentHorizontalPaddingCompact
            return EdgeInsets(
                top: -(ZoneContentMetrics.childSpacing + ZoneContentMetrics.groupGuideVerticalPadding),
                leading: -(horizontalOutset + ZoneContentMetrics.groupGuideHorizontalPadding),
                bottom: -(ZoneContentMetrics.childSpacing + ZoneContentMetrics.groupGuideVerticalPadding),
                trailing: -(horizontalOutset + ZoneContentMetrics.groupGuideHorizontalPadding)
            )
        }
    }
}

// MARK: - Zone Content Leaf Preview

private struct ZoneContentLeafPreview: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(\.zoneContentSurfaceCornerRadius) private var zoneSurfaceCornerRadius

    let zone: ZoneModel
    let path: String
    let suppressOwnEditorRenderGuide: Bool
    let representsSelectedGroupGuide: Bool
    let fontScale: CGFloat
    let availableWidth: CGFloat
    let centersLeafBlocks: Bool
    let alignLeafBlocksToGroupLeading: Bool
    let showsDebugGuides: Bool
    let showsZoneSurfaces: Bool
    let showsCodeBlockZoneSurfaces: Bool
    let usesBorderOnlyZoneHighlights: Bool
    let zoneHighlightStrokeStyle: StrokeStyle
    let debugGuideStyle: ZoneContentDebugGuideStyle
    let textVerticalPadding: CGFloat
    let textHorizontalPaddingOverride: CGFloat?
    let alignmentFeedback: ZoneAlignmentFeedback
    let collectsDebugMetrics: Bool
    let leafTapBehavior: ZoneContentLeafTapBehavior
    var onTap: (() -> Void)?
    var onZoneTap: ((UUID) -> Void)?

    @State private var renderedContentSize: CGSize = .zero
    @State private var renderedTokenLines: [MixedMathRenderedLineDebug] = []
    @State private var renderedScrollableMath: [MixedMathScrollableDebug] = []
    @State private var mathGestureDebug: MixedMathGestureDebugSnapshot?
    @State private var renderStatusDebug: MixedMathRenderStatusDebug?
    @State private var nativeRenderDebug: MixedMathNativeRenderDebug?
    @State private var measurementUpdateCount = 0
    @State private var measurementResetCount = 0
    @State private var rawMeasuredContentSize: CGSize = .zero
    @State private var lastMeasurementSource = "none"
    @State private var lastMeasurementDecision = "none"
    @State private var measurementEvents: [String] = []

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
                renderBlockBounds(layout: layout, layoutZone: resolvedLayoutZone)
                zoneBlockSurface(layout: layout)
                paddingDebugGuide(layout: layout)

                if debugGuideStyle != .editorRender,
                    let leafTarget,
                    alignmentFeedback.highlightedTarget == leafTarget {
                    zoneAlignmentHighlight()
                        .frame(width: layout.blockSize.width, height: layout.blockSize.height)
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
                    updateRenderedContentSize(newSize, source: "swiftui-geometry")
                }

                if showsDebugGuides && !suppressOwnEditorRenderGuide {
                    RoundedRectangle(
                        cornerRadius: leafDebugGuideCornerRadius,
                        style: .continuous
                    )
                        .stroke(
                            leafDebugGuideColor,
                            style: leafDebugGuideStrokeStyle
                        )
                        .frame(width: layout.blockSize.width, height: layout.blockSize.height)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.18), value: isLeafAlignmentTarget)
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
            .onChange(of: measurementIdentity) { oldIdentity, newIdentity in
            guard !oldIdentity.matchesContent(of: newIdentity) else {
                if shouldResetPreservedMeasurement(forAvailableWidth: newIdentity.availableWidth) {
                    resetRenderedMeasurements(reason: "width floor reset")
                    return
                }

                appendMeasurementEvent(
                    "width changed \(Int(oldIdentity.availableWidth)) -> \(Int(newIdentity.availableWidth)); preserved \(debugSize(renderedContentSize))"
                )
                return
            }

            resetRenderedMeasurements(reason: "identity reset")
        }
    }

    private func renderBlockBounds(
        layout: ZoneContentLayoutResult,
        layoutZone: ZoneModel
    ) -> some View {
        Color.clear
            .frame(width: layout.blockSize.width, height: layout.blockSize.height)
            .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ZoneContentRenderBlockBoundsPreferenceKey.self,
                    value: [
                        ZoneContentRenderBlockBounds(
                            zoneID: zone.id,
                            path: path,
                            kind: "leaf",
                            frame: proxy.frame(in: .named(ZoneContentRenderCoordinateSpace.name)),
                            availableWidth: availableWidth,
                            blockSize: layout.blockSize,
                            leadingInset: layout.leadingInset,
                            trailingInset: max(availableWidth - layout.leadingInset - layout.blockSize.width, 0),
                            rawBlockAlignment: zone.blockAlignment,
                            resolvedBlockAlignment: layoutZone.blockAlignment,
                            textHorizontalInsets: layout.textHorizontalInsets,
                            textVerticalPadding: textVerticalPadding,
                            contentLayoutWidth: layout.contentLayoutWidth,
                            textWidthLimit: layout.textWidthLimit
                        )
                    ]
                )
            }
        )
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func paddingDebugGuide(layout: ZoneContentLayoutResult) -> some View {
        if showsDebugGuides,
           (zone.contentType == .empty || zone.contentType == .text || zone.contentType == .code) {
            let horizontalInset = layout.textHorizontalInsets / 2
            let verticalInset = textVerticalPadding / 2
            let contentWidth = max(layout.blockSize.width - layout.textHorizontalInsets, 1)
            let contentHeight = max(layout.blockSize.height - textVerticalPadding, 1)

            RoundedRectangle(cornerRadius: max(zoneSurfaceCornerRadius - 10, 8), style: .continuous)
                .stroke(
                    debugGuideStyle == .editorRender
                        ? Color.mint.opacity(0.92)
                        : Color.cyan.opacity(0.9),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
                .frame(width: contentWidth, height: contentHeight)
                .offset(x: horizontalInset, y: verticalInset)
                .overlay(alignment: .topLeading) {
                    Text("pad \(Int(ceil(horizontalInset)))x\(Int(ceil(verticalInset)))")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.mint)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .offset(x: horizontalInset + 3, y: verticalInset + 3)
                }
                .allowsHitTesting(false)
        }
    }

    private var leafWiggleOffset: CGFloat {
        leafTarget.map(alignmentFeedback.offset(for:)) ?? 0
    }

    private var leafTarget: ZoneAlignmentTargetRef? {
        zonePath.map { ZoneAlignmentTargetRef(path: $0, kind: .leaf) }
    }

    private var isLeafAlignmentTarget: Bool {
        if representsSelectedGroupGuide {
            return true
        }

        guard let leafTarget else { return false }
        return alignmentFeedback.highlightedTarget == leafTarget
    }

    private var leafDebugGuideColor: Color {
        switch debugGuideStyle {
        case .debug:
            Color.orange.opacity(0.95)
        case .editorRender:
            isLeafAlignmentTarget
                ? ThemeManager.shared.accentColor.color.opacity(0.9)
            : Color.gray.opacity(0.58)
        }
    }

    private var leafDebugGuideStrokeStyle: StrokeStyle {
        switch debugGuideStyle {
        case .debug:
            return StrokeStyle(lineWidth: 1.6, dash: [5, 4])
        case .editorRender:
            if zone.isEditorMediaLeaf {
                return StrokeStyle(lineWidth: 1.6, dash: [5, 4])
            }
            return isLeafAlignmentTarget
                ? StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            : StrokeStyle(lineWidth: 1.6, dash: [5, 4])
        }
    }

    private var leafDebugGuideCornerRadius: CGFloat {
        zone.isEditorMediaLeaf ? 10 : zoneSurfaceCornerRadius
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
            sizeMode: zone.sizeMode,
            fixedWidth: zone.fixedWidth.map(ceil),
            fixedHeight: zone.fixedHeight.map(ceil),
            isBold: zone.isBold,
            isItalic: zone.isItalic,
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
                RoundedRectangle(cornerRadius: zoneSurfaceCornerRadius, style: .continuous)
                    .fill(zoneSurfaceFill)
                    .overlay {
                    RoundedRectangle(cornerRadius: zoneSurfaceCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                }
                    .overlay {
                    if let tint {
                        RoundedRectangle(cornerRadius: zoneSurfaceCornerRadius, style: .continuous)
                            .stroke(tint.opacity(0.86), style: zoneHighlightStrokeStyle)
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
        showsZoneSurfaces
            && appPreferences.zoneSurfaceStyle.showsZoneSurfaces
            && (!rendersCodeBlock || showsCodeBlockZoneSurfaces || zone.highlightColor != .none)
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
                    cornerRadius: 10,
                    displaySize: ZoneMediaMetrics.displaySize(for: zone, availableWidth: layout.contentLayoutWidth)
                )
            }

        case .sketch:
            if let data = zone.imageData {
                CachedImageView(
                    data: data,
                    scale: zone.imageScale,
                    alignment: .leading,
                    cornerRadius: 10,
                    displaySize: ZoneMediaMetrics.displaySize(for: zone, availableWidth: layout.contentLayoutWidth),
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
            availableWidth - layout.textHorizontalInsets,
            1
        )
        let renderedLineDebugHandler: (([MixedMathRenderedLineDebug]) -> Void)? = collectsDebugMetrics
            ? { lines in renderedTokenLines = lines }
        : nil
        let scrollableDebugHandler: (([MixedMathScrollableDebug]) -> Void)? = collectsDebugMetrics
            ? { rows in renderedScrollableMath = rows }
        : nil
        let gestureDebugHandler: ((MixedMathGestureDebugSnapshot) -> Void)? = collectsDebugMetrics
            ? { snapshot in mathGestureDebug = snapshot }
        : nil
        let renderStatusDebugHandler: ((MixedMathRenderStatusDebug) -> Void)? = collectsDebugMetrics
            ? { snapshot in renderStatusDebug = snapshot }
        : nil
        return HStack(alignment: .top, spacing: 0) {
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
                                width: ceil(size.width + layout.textHorizontalInsets),
                                height: ceil(size.height + textVerticalPadding)
                            ),
                            source: "web-intrinsic"
                        )
                    },
                    onRenderedLineDebugChange: renderedLineDebugHandler,
                    onScrollableDebugChange: scrollableDebugHandler,
                    onGestureDebugChange: gestureDebugHandler,
                    onRenderStatusDebugChange: renderStatusDebugHandler,
                    onNativeRenderDebugChange: collectsDebugMetrics ? { snapshot in
                        nativeRenderDebug = snapshot
                    } : nil,
                    showsRenderDebugBounds: showsDebugGuides || collectsDebugMetrics,
                    onTap: richContentTapHandler
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
                                width: ceil(size.width + layout.textHorizontalInsets),
                                height: ceil(size.height + textVerticalPadding)
                            ),
                            source: "plain-intrinsic"
                        )
                    },
                    onTap: plainTextTapHandler
                )
                    .padding(.vertical, textVerticalPadding / 2)
                    .padding(.horizontal, layout.textHorizontalInsets / 2)
            }
        }
            .frame(width: layout.contentLayoutWidth, alignment: .topLeading)
    }

    private func updateRenderedContentSize(_ newSize: CGSize, source: String) {
        measurementUpdateCount += 1
        rawMeasuredContentSize = newSize
        lastMeasurementSource = source
        guard newSize.width > 0, newSize.height > 0 else {
            recordMeasurementDecision("rejected non-positive", size: newSize, source: source)
            return
        }
        guard isValidRenderedMeasurement(newSize) else {
            recordMeasurementDecision("rejected validation", size: newSize, source: source)
            return
        }
        let clampedSize = CGSize(
            width: min(max(ceil(newSize.width), 1), availableWidth),
            height: max(ceil(newSize.height), 1)
        )

        if abs(renderedContentSize.width - clampedSize.width) > 0.5
            || abs(renderedContentSize.height - clampedSize.height) > 0.5 {
            recordMeasurementDecision("accepted -> \(debugSize(clampedSize))", size: newSize, source: source)
            renderedContentSize = clampedSize
        } else {
            recordMeasurementDecision("unchanged", size: newSize, source: source)
        }
    }

    private func shouldResetPreservedMeasurement(forAvailableWidth availableWidth: CGFloat) -> Bool {
        guard renderedContentSize.width > 0 else { return false }

        if !requiresIntrinsicTextWidthFloor {
            return renderedContentSize.width <= 1.5 && availableWidth > 1.5
        }

        let minimumWidth = ZoneContentEstimator.estimatedBlockWidth(
            for: layoutZone,
            fontScale: fontScale,
            availableWidth: max(availableWidth, 1),
            textVerticalPadding: textVerticalPadding,
            textHorizontalPaddingOverride: textHorizontalPaddingOverride
        )

        return renderedContentSize.width + 0.5 < minimumWidth
    }

    private var requiresIntrinsicTextWidthFloor: Bool {
        guard zone.contentType == .text else { return false }
        let previewText = displayText(for: zone)
        guard !previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let healedText = MathTextSanitizer.heal(previewText)
        return !MathTextSanitizer.containsMath(healedText)
            && !MathTextSanitizer.containsInlineCode(healedText)
    }

    private func resetRenderedMeasurements(reason: String) {
        measurementResetCount += 1
        rawMeasuredContentSize = .zero
        lastMeasurementSource = "identity-reset"
        lastMeasurementDecision = "cleared"
        appendMeasurementEvent(reason)
        renderedContentSize = .zero
        renderedTokenLines = []
        renderedScrollableMath = []
        mathGestureDebug = nil
        renderStatusDebug = nil
        nativeRenderDebug = nil
    }

    private func recordMeasurementDecision(_ decision: String, size: CGSize, source: String) {
        lastMeasurementDecision = decision
        appendMeasurementEvent("\(source) \(debugSize(size)) \(decision)")
    }

    private func appendMeasurementEvent(_ event: String) {
        measurementEvents.append(event)
        if measurementEvents.count > 12 {
            measurementEvents.removeFirst(measurementEvents.count - 12)
        }
    }

    private func debugSize(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    private func handleTap() {
        onZoneTap?(zone.id)
        onTap?()
    }

    private var richContentTapHandler: (() -> Void)? {
        guard leafTapBehavior.allowsRichContentTap else { return nil }
        return { handleTap() }
    }

    private var plainTextTapHandler: (() -> Void)? {
        guard leafTapBehavior.allowsPlainTextTap else { return nil }
        return { handleTap() }
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
        let estimatedWidth: CGFloat = {
            guard requiresIntrinsicTextWidthFloor else { return 1 }
            return ZoneContentEstimator.estimatedBlockWidth(
                for: layoutZone,
                fontScale: fontScale,
                availableWidth: max(availableWidth, 1),
                textVerticalPadding: textVerticalPadding,
                textHorizontalPaddingOverride: textHorizontalPaddingOverride
            )
        }()

        return min(
            max(ceil(estimatedWidth), resolvedTextHorizontalPadding + 8, 1),
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
            rawBlockAlignment: zone.blockAlignment,
            resolvedBlockAlignment: layoutZone.blockAlignment,
            availableWidth: ceil(availableWidth),
            estimatedSize: layout.estimatedContentSize,
            renderedContentSize: roundedSize(renderedContentSize),
            measurementUpdateCount: measurementUpdateCount,
            measurementResetCount: measurementResetCount,
            rawMeasuredContentSize: roundedSize(rawMeasuredContentSize),
            blockSize: layout.blockSize,
            leadingInset: layout.leadingInset,
            contentFrameHeight: contentFrameHeight(for: layout),
            contentLayoutWidth: layout.contentLayoutWidth,
            textWidthLimit: layout.textWidthLimit,
            textHorizontalInsets: layout.textHorizontalInsets,
            blockHeightSlack: max(layout.blockSize.height - renderedContentSize.height, 0),
            usesIntrinsicTextMeasurement: layout.usesIntrinsicTextMeasurement,
            zoneSizeMode: layoutZone.sizeMode,
            textStyle: zone.textStyle,
            fontFamily: zone.fontFamily,
            isBold: zone.isBold,
            isItalic: zone.isItalic,
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
            renderStatusDebug: containsMath || containsInlineCode ? renderStatusDebug : nil,
            nativeRenderDebug: containsMath || containsInlineCode ? nativeRenderDebug : nil,
            lastMeasurementSource: lastMeasurementSource,
            lastMeasurementDecision: lastMeasurementDecision,
            measurementEvents: measurementEvents,
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
    nonisolated static let childSpacing: CGFloat = 12
    static let textVerticalPadding: CGFloat = 24
    static let textHorizontalPadding: CGFloat = 24
    static let zoneCornerRadius: CGFloat = 38
    static let groupGuideHorizontalPadding: CGFloat = 8
    static let groupGuideVerticalPadding: CGFloat = 2
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
    private final class LineLayoutBox {
        let value: ZoneContentPlainTextLineLayout

        init(_ value: ZoneContentPlainTextLineLayout) {
            self.value = value
        }
    }

    private static let layoutCache: NSCache<NSString, LineLayoutBox> = {
        let cache = NSCache<NSString, LineLayoutBox>()
        cache.countLimit = 384
        return cache
    }()

    static func layout(
        text rawText: String,
        zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> ZoneContentPlainTextLineLayout {
        let text = rawText.replacingOccurrences(of: "\r\n", with: "\n")
        let widthLimit = max(availableWidth, 1)
        let cacheKey = layoutCacheKey(
            text: text,
            zone: zone,
            fontScale: fontScale,
            availableWidth: widthLimit
        )

        if let cachedLayout = layoutCache.object(forKey: cacheKey)?.value {
            return cachedLayout
        }

        let lineSpacing = max(floor(fontSize(for: zone) * fontScale * 0.26), 6)

        guard !text.isEmpty else {
            let emptyLine = ZoneContentPlainTextLine(tokens: [], width: 1, height: lineHeight(for: zone, fontScale: fontScale))
            return cacheLayout(
                ZoneContentPlainTextLineLayout(lines: [emptyLine], lineSpacing: lineSpacing),
                for: cacheKey
            )
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

        return cacheLayout(
            ZoneContentPlainTextLineLayout(lines: output, lineSpacing: lineSpacing),
            for: cacheKey
        )
    }

    private static func cacheLayout(
        _ layout: ZoneContentPlainTextLineLayout,
        for key: NSString
    ) -> ZoneContentPlainTextLineLayout {
        layoutCache.setObject(LineLayoutBox(layout), forKey: key)
        return layout
    }

    private static func layoutCacheKey(
        text: String,
        zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat
    ) -> NSString {
        [
            "plain",
            text,
            String(describing: zone.textStyle),
            String(zone.isBold),
            String(zone.isItalic),
            String(describing: zone.fontFamily),
            roundedCacheComponent(fontScale),
            roundedCacheComponent(availableWidth)
        ]
            .joined(separator: "\u{1F}") as NSString
    }

    private static func roundedCacheComponent(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
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
    private static let estimatedSizeCache: NSCache<NSString, NSValue> = {
        let cache = NSCache<NSString, NSValue>()
        cache.countLimit = 512
        return cache
    }()
    private static let estimatedBlockWidthCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 512
        return cache
    }()

    static func estimatedSize(
        for zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat,
        textVerticalPadding: CGFloat = ZoneContentMetrics.textVerticalPadding,
        textHorizontalPaddingOverride: CGFloat? = nil
    ) -> CGSize {
        let clampedWidth = max(availableWidth, 1)
        let cacheKey = estimatedSizeCacheKey(
            for: zone,
            fontScale: fontScale,
            availableWidth: clampedWidth,
            textVerticalPadding: textVerticalPadding,
            textHorizontalPaddingOverride: textHorizontalPaddingOverride
        )

        if let cachedSize = estimatedSizeCache.object(forKey: cacheKey)?.cgSizeValue {
            return cachedSize
        }

        guard ZoneContentRenderPolicy.shouldRender(zone) else {
            return cacheEstimatedSize(CGSize(width: 1, height: 36), for: cacheKey)
        }

        if zone.isLeaf {
            return cacheEstimatedSize(estimatedLeafSize(
                for: zone,
                fontScale: fontScale,
                availableWidth: clampedWidth,
                textVerticalPadding: textVerticalPadding,
                textHorizontalPaddingOverride: textHorizontalPaddingOverride
            ), for: cacheKey)
        }

        let children = zone.children?.filter(ZoneContentRenderPolicy.shouldRender) ?? []
        guard !children.isEmpty else {
            return cacheEstimatedSize(CGSize(width: 1, height: 36), for: cacheKey)
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

            return cacheEstimatedSize(CGSize(
                width: min(ceil(widestChild), clampedWidth),
                height: ceil(totalHeight)
            ), for: cacheKey)

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

            return cacheEstimatedSize(CGSize(
                width: min(ceil(totalWidth), clampedWidth),
                height: ceil(tallestChild)
            ), for: cacheKey)
        }
    }

    private static func cacheEstimatedSize(_ size: CGSize, for key: NSString) -> CGSize {
        estimatedSizeCache.setObject(NSValue(cgSize: size), forKey: key)
        return size
    }

    nonisolated private static func estimatedSizeCacheKey(
        for zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat,
        textVerticalPadding: CGFloat,
        textHorizontalPaddingOverride: CGFloat?
    ) -> NSString {
        [
            "estimate",
            roundedCacheComponent(fontScale),
            roundedCacheComponent(availableWidth),
            roundedCacheComponent(textVerticalPadding),
            textHorizontalPaddingOverride.map(roundedCacheComponent) ?? "nil",
            zoneCacheFingerprint(zone)
        ]
            .joined(separator: "|") as NSString
    }

    nonisolated private static func roundedCacheComponent(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }

    nonisolated private static func zoneCacheFingerprint(_ zone: ZoneModel) -> String {
        var parts: [String] = [
            zone.id.uuidString,
            String(describing: zone.contentType),
            zone.codeLanguage ?? "",
            zone.text,
            String(describing: zone.textStyle),
            String(describing: zone.sizeMode),
            zone.fixedWidth.map(roundedCacheComponent) ?? "nil",
            zone.fixedHeight.map(roundedCacheComponent) ?? "nil",
            String(describing: zone.verticalAlignment),
            String(describing: zone.textColor),
            String(zone.isBold),
            String(zone.isItalic),
            String(describing: zone.fontFamily),
            String(describing: zone.highlightColor),
            roundedCacheComponent(zone.imageScale),
            String(describing: zone.direction),
            zone.imageData.map { "\($0.count):\($0.hashValue)" } ?? "nil"
        ]

        if let children = zone.children, !children.isEmpty {
            parts.append(contentsOf: children.map(zoneCacheFingerprint))
        }

        return parts.joined(separator: "\u{1F}")
    }

    static func estimatedBlockWidth(
        for zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat,
        textVerticalPadding: CGFloat = ZoneContentMetrics.textVerticalPadding,
        textHorizontalPaddingOverride: CGFloat? = nil
    ) -> CGFloat {
        let clampedWidth = max(availableWidth, 1)
        let cacheKey = estimatedBlockWidthCacheKey(
            for: zone,
            fontScale: fontScale,
            availableWidth: clampedWidth,
            textVerticalPadding: textVerticalPadding,
            textHorizontalPaddingOverride: textHorizontalPaddingOverride
        )

        if let cachedWidth = estimatedBlockWidthCache.object(forKey: cacheKey) {
            return CGFloat(truncating: cachedWidth)
        }

        guard ZoneContentRenderPolicy.shouldRender(zone) else {
            return cacheEstimatedBlockWidth(1, for: cacheKey)
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

            return cacheEstimatedBlockWidth(
                min(max(ceil(layout.blockSize.width), 1), clampedWidth),
                for: cacheKey
            )
        }

        let children = zone.children?.filter(ZoneContentRenderPolicy.shouldRender) ?? []
        guard !children.isEmpty else {
            return cacheEstimatedBlockWidth(1, for: cacheKey)
        }

        switch zone.direction {
        case .vertical:
            return cacheEstimatedBlockWidth(children
                .map {
                estimatedBlockWidth(
                    for: $0,
                    fontScale: fontScale,
                    availableWidth: clampedWidth,
                    textVerticalPadding: textVerticalPadding,
                    textHorizontalPaddingOverride: textHorizontalPaddingOverride
                )
            }
                .max() ?? 1, for: cacheKey)

        case .horizontal:
            return cacheEstimatedBlockWidth(estimatedSize(
                for: zone,
                fontScale: fontScale,
                availableWidth: clampedWidth,
                textVerticalPadding: textVerticalPadding,
                textHorizontalPaddingOverride: textHorizontalPaddingOverride
            )
                .width, for: cacheKey)
        }
    }

    private static func cacheEstimatedBlockWidth(_ width: CGFloat, for key: NSString) -> CGFloat {
        estimatedBlockWidthCache.setObject(NSNumber(value: Double(width)), forKey: key)
        return width
    }

    nonisolated private static func estimatedBlockWidthCacheKey(
        for zone: ZoneModel,
        fontScale: CGFloat,
        availableWidth: CGFloat,
        textVerticalPadding: CGFloat,
        textHorizontalPaddingOverride: CGFloat?
    ) -> NSString {
        [
            "blockWidth",
            roundedCacheComponent(fontScale),
            roundedCacheComponent(availableWidth),
            roundedCacheComponent(textVerticalPadding),
            textHorizontalPaddingOverride.map(roundedCacheComponent) ?? "nil",
            zoneCacheFingerprint(zone)
        ]
            .joined(separator: "|") as NSString
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
            let textWidth = max(availableWidth - horizontalInsets, 1)
            let measuredSize: CGSize

            if let codeLiteral = singleInlineCodeLiteral(in: displayText) {
                measuredSize = measuredInlineCodeSize(
                    codeLiteral,
                    zone: zone,
                    fontScale: fontScale,
                    availableWidth: textWidth
                )
            } else {
                measuredSize = measuredTextSize(
                    displayText,
                    zone: zone,
                    fontScale: fontScale,
                    availableWidth: textWidth
                )
            }

            return CGSize(
                width: min(ceil(measuredSize.width + horizontalInsets), availableWidth),
                height: ceil(measuredSize.height + textVerticalPadding)
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
            return ZoneMediaMetrics.displaySize(for: zone, availableWidth: availableWidth)
        }
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
        guard text.first == "`", text.last == "`", text.count > 2 else {
            return nil
        }

        let inner = text.dropFirst().dropLast()
        guard !inner.contains("`") else { return nil }
        return String(inner).replacingOccurrences(of: "\r\n", with: "\n")
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

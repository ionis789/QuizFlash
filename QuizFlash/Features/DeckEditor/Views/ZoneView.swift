//
//  ZoneView.swift
//  QuizFlash
//
//  Recursive zone editor and read-only card face preview.
//  All zone mutations go through `ZoneCardContent`; views are read-only consumers.
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - Ghost Block View

/// A dashed-border placeholder that previews where a new zone will be inserted
/// during keyboard-preserving zone insertion. Rendered as a visual overlay only — never
/// mutates the zone data model.
struct FakeGhostBlockView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.yellow.opacity(0.15))
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.yellow.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [6]))
        }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
    }
}

// MARK: - Zone Editor Frame Preferences

struct ZoneEditorZoneBounds {
    let path: ZonePath
    let zoneID: UUID
    let bounds: Anchor<CGRect>
}

struct ZoneEditorZoneBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: [ZoneEditorZoneBounds] { [] }

    static func reduce(
        value: inout [ZoneEditorZoneBounds],
        nextValue: () -> [ZoneEditorZoneBounds]
    ) {
        value.append(contentsOf: nextValue())
    }
}

struct ZoneEditorResolvedZoneFrame: Equatable {
    let path: ZonePath
    let zoneID: UUID
    let frame: CGRect
}

struct ZoneEditorResolvedZoneFramePreferenceKey: PreferenceKey {
    static var defaultValue: [ZoneEditorResolvedZoneFrame] { [] }

    static func reduce(
        value: inout [ZoneEditorResolvedZoneFrame],
        nextValue: () -> [ZoneEditorResolvedZoneFrame]
    ) {
        value.append(contentsOf: nextValue())
    }
}

struct ZoneEditorNaturalBlockWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }

    static func reduce(
        value: inout [String: CGFloat],
        nextValue: () -> [String: CGFloat]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

// MARK: - Zone Editor View (Recursive)

/// Recursive view that renders a zone tree rooted at `path`.
///
/// - Leaf zones are handed off to `ZoneContentView` for text/image/sketch rendering.
/// - Container zones lay out children vertically and inject ghost block overlays
///   based on `previewDirection`.
struct ZoneEditorView: View {
    @Bindable var content: ZoneCardContent
    let path: ZonePath
    @Binding var selectedPath: ZonePath?
    var highlightContext: HighlightContext?
    var fontScale: CGFloat
    var availableWidth: CGFloat
    var measurementWidth: CGFloat
    var maxEditableZoneHeight: CGFloat?
    var previewDirection: Binding<AddDirection?>

    private var zone: ZoneModel? { content.zone(at: path) }
    private var isSelected: Bool { selectedPath == path }
    @State private var measuredDirectChildWidths: [String: CGFloat] = [:]

    init(
        content: ZoneCardContent,
        path: ZonePath,
        selectedPath: Binding<ZonePath?>,
        highlightContext: HighlightContext?,
        fontScale: CGFloat = 1.0,
        availableWidth: CGFloat = 320,
        measurementWidth: CGFloat? = nil,
        maxEditableZoneHeight: CGFloat? = nil,
        previewDirection: Binding<AddDirection?> = .constant(nil)
    ) {
        self.content = content
        self.path = path
        self._selectedPath = selectedPath
        self.highlightContext = highlightContext
        self.fontScale = fontScale
        self.availableWidth = availableWidth
        self.measurementWidth = measurementWidth ?? availableWidth
        self.maxEditableZoneHeight = maxEditableZoneHeight
        self.previewDirection = previewDirection
    }

    var body: some View {
        if let zone = zone {
            if zone.isLeaf {
                leafZoneView(zone: zone)
            } else {
                containerZoneView(zone: zone)
            }
        }
    }

    @ViewBuilder
    private func leafZoneView(zone: ZoneModel) -> some View {
        ZoneContentView(
            content: content,
            path: path,
            isSelected: isSelected,
            highlightContext: highlightContext,
            fontScale: fontScale,
            availableWidth: availableWidth,
            measurementWidth: measurementWidth,
            maxEditableZoneHeight: maxEditableZoneHeight,
            onSelect: { selectZone() },
            previewDirection: previewDirection
        )
            .id(path.id)
    }

    // MARK: - Container Zone View

    @ViewBuilder
    private func containerZoneView(zone: ZoneModel) -> some View {
        let children = zone.children ?? []
        let indexedChildren = Array(children.enumerated())
        let childPaths = indexedChildren.map { path.appending($0.offset).id }
        let groupWidth = verticalGroupWidth(for: children, childPaths: childPaths)
        let groupLeadingInset = max((availableWidth - groupWidth) / 2, 0)

        VStack(spacing: 8) {
            ForEach(indexedChildren, id: \.element.id) { index, _ in
                let childPath = path.appending(index)
                let isChildSelected = (selectedPath == childPath)

                if isChildSelected, previewDirection.wrappedValue == .up {
                    FakeGhostBlockView()
                        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                }

                ZoneEditorView(
                    content: content,
                    path: childPath,
                    selectedPath: $selectedPath,
                    highlightContext: highlightContext,
                    fontScale: fontScale,
                    availableWidth: groupWidth,
                    measurementWidth: measurementWidth,
                    maxEditableZoneHeight: maxEditableZoneHeight,
                    previewDirection: maskedPreviewDirection(for: isChildSelected)
                )
                .frame(width: groupWidth, alignment: .topLeading)

                if isChildSelected, previewDirection.wrappedValue == .down {
                    FakeGhostBlockView()
                        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                }
            }
        }
        .frame(width: groupWidth, alignment: .topLeading)
        .offset(x: groupLeadingInset)
        .frame(width: availableWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeOut(duration: 0.14), value: groupWidth)
        .onPreferenceChange(ZoneEditorNaturalBlockWidthPreferenceKey.self) { widths in
            let directWidths = Dictionary(
                uniqueKeysWithValues: childPaths.compactMap { childPath -> (String, CGFloat)? in
                    guard let width = widths[childPath], width > 0 else { return nil }
                    return (childPath, min(max(ceil(width), 1), availableWidth))
                }
            )

            guard directWidths.count == childPaths.count else {
                if !measuredDirectChildWidths.isEmpty {
                    measuredDirectChildWidths = [:]
                }
                return
            }

            guard directWidths != measuredDirectChildWidths else { return }
            measuredDirectChildWidths = directWidths
        }
        .onChange(of: verticalGroupIdentity(for: children)) { _, _ in
            measuredDirectChildWidths = [:]
        }
    }

    private func verticalGroupWidth(for children: [ZoneModel], childPaths: [String]) -> CGFloat {
        if measuredDirectChildWidths.count == childPaths.count {
            let measuredWidth = childPaths
                .compactMap { measuredDirectChildWidths[$0] }
                .max() ?? 1

            return min(max(ceil(measuredWidth), 1), availableWidth)
        }

        let estimatedWidth = children
            .map { estimatedEditorBlockWidth(for: $0, constrainedTo: measurementWidth) }
            .max() ?? availableWidth

        return min(max(ceil(estimatedWidth), 1), availableWidth)
    }

    private func estimatedEditorBlockWidth(for zone: ZoneModel, constrainedTo width: CGFloat) -> CGFloat {
        if zone.isLeaf {
            return ZoneContentEstimator.estimatedBlockWidth(
                for: normalizedEditorMeasurementZone(zone),
                fontScale: fontScale,
                availableWidth: width
            )
        }

        let children = zone.children ?? []
        guard !children.isEmpty else { return 1 }
        return children
            .map { estimatedEditorBlockWidth(for: $0, constrainedTo: width) }
            .max() ?? 1
    }

    private func normalizedEditorMeasurementZone(_ zone: ZoneModel) -> ZoneModel {
        var layoutZone = zone
        layoutZone.textAlignment = .leading
        if layoutZone.blockAlignment == .auto {
            layoutZone.blockAlignment = .leading
        }
        return layoutZone
    }

    private func verticalGroupIdentity(for children: [ZoneModel]) -> String {
        children.map(\.id.uuidString)
        .joined(separator: "||")
    }

    private func maskedPreviewDirection(for isChildSelected: Bool) -> Binding<AddDirection?> {
        Binding<AddDirection?>(
            get: {
                guard isChildSelected, previewDirection.wrappedValue != nil else {
                    return previewDirection.wrappedValue
                }
                return nil
            },
            set: { previewDirection.wrappedValue = $0 }
        )
    }

    private func selectZone() {
        let wasSelected = selectedPath == path
        selectedPath = path
        NotificationCenter.default.post(
            name: .zoneEditorZoneTapped,
            object: nil,
            userInfo: [ZoneEditorCaretScrollNotification.pathIDKey: path.id]
        )
        if !wasSelected {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// MARK: - Zone Content View (Leaf)

/// Renders the content of a single leaf zone: text editor, image, or sketch.
///
/// Handles:
/// - Focus negotiation with `ZoneFocusManager` and `ZoneController`
/// - Switching between `ZoneTextViewRepresentable` (edit mode) and
///   a read-only raw text preview that mirrors the editor metrics
/// - Image long-press → full-screen `ImageCropEditorView`
/// - Ghost block overlays for vertical zone insertion
struct ZoneContentView: View {
    @Bindable var content: ZoneCardContent
    let path: ZonePath
    let isSelected: Bool
    var highlightContext: HighlightContext?
    var fontScale: CGFloat
    var availableWidth: CGFloat
    var measurementWidth: CGFloat
    var maxEditableZoneHeight: CGFloat?
    var onSelect: () -> Void
    @Binding var previewDirection: AddDirection?

    @State private var isFocused: Bool = false
    @State private var isCroppingImage: Bool = false
    @State private var isPressingImage: Bool = false
    @State private var renderedContentSize: CGSize = .zero
    @State private var lastPostedCaretAnchorY: CGFloat?
    @State private var isTextViewFirstResponder: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppPreferences.self) private var appPreferences
    private var focusManager = ZoneFocusManager.shared
    private var zoneController = ZoneController.shared
    private var lineTracker = ZoneLineTracker.shared

    private var zone: ZoneModel? { content.zone(at: path) }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var currentZoneID: UUID? { zone?.id }
    private var locale: Locale { appPreferences.resolvedLocale }

    init(
        content: ZoneCardContent,
        path: ZonePath,
        isSelected: Bool,
        highlightContext: HighlightContext? = nil,
        fontScale: CGFloat = 1.0,
        availableWidth: CGFloat = 320,
        measurementWidth: CGFloat? = nil,
        maxEditableZoneHeight: CGFloat? = nil,
        onSelect: @escaping () -> Void,
        previewDirection: Binding<AddDirection?> = .constant(nil)
    ) {
        self.content = content
        self.path = path
        self.isSelected = isSelected
        self.highlightContext = highlightContext
        self.fontScale = fontScale
        self.availableWidth = availableWidth
        self.measurementWidth = measurementWidth ?? availableWidth
        self.maxEditableZoneHeight = maxEditableZoneHeight
        self.onSelect = onSelect
        self._previewDirection = previewDirection
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private var shouldShowHighlight: Bool {
        guard let highlightContext = highlightContext, let zone = zone else { return false }
        return highlightContext.shouldHighlight(text: zone.text)
    }

    var body: some View {
        if let zone {
            let layoutZone = normalizedLayoutZone(zone)
            let measuredContentSize = measuredLayoutContentSize(
                for: zone,
                layoutZone: layoutZone
            )
            let layout = ZoneContentLayoutEngine.leafLayout(
                for: layoutZone,
                spec: ZoneContentLayoutSpec(
                    availableWidth: availableWidth,
                    fontScale: fontScale,
                    minimumAutoWidth: stableMinimumAutoWidth(for: layoutZone)
                ),
                measuredContentSize: measuredContentSize
            )
            let visualOutset = visualZoneOutset(for: zone)
            let contentFrameHeight = contentFrameHeight(for: layoutZone, layout: layout)
            let contentPlacement = contentPlacement(
                for: layoutZone,
                layout: layout,
                measuredContentSize: measuredContentSize
            )

            ZStack(alignment: .topLeading) {
                blockFrameReporter(layout: layout, zone: zone)
                blockSurface(layout: layout, zone: zone)

                if isSelected {
                    selectionOutline(layout: layout, zone: zone, active: isTextViewFirstResponder)
                }

                contentView(maxVisibleTextHeight: contentFrameHeight ?? maximumResizableHeight)
                    .frame(
                        width: contentPlacement.width,
                        height: contentFrameHeight,
                        alignment: .topLeading
                    )
                    .clipped()
                    .offset(x: contentPlacement.leadingInset)
                    .onGeometryChange(for: CGSize.self) { proxy in
                        CGSize(width: ceil(proxy.size.width), height: ceil(proxy.size.height))
                    } action: { newSize in
                        if !layout.usesIntrinsicTextMeasurement {
                            updateRenderedContentSize(newSize)
                        }
                    }

            }
            .frame(
                width: availableWidth,
                height: layout.blockSize.height + (visualOutset.vertical * 2),
                alignment: .topLeading
            )
            .preference(
                key: ZoneEditorNaturalBlockWidthPreferenceKey.self,
                value: [path.id: naturalBlockWidth(for: layoutZone, measuredContentSize: measuredContentSize)]
            )
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture().onEnded { _ in
                    let type = zone.contentType

                    if type != .text && type != .empty && type != .code {
                        onSelect()
                        ZoneEditorDebugStore.shared.recordTap("tap zone path=\(path.id) type=\(zone.contentType.rawValue)")
                        focusManager.updateFocusedZone(zone.id)
                        zoneController.updateFocusedZone(zone.id)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                },
                including: isTextResizableZone(zone) || isTextViewFirstResponder ? .none : .all
            )
            .onAppear {
                syncFocusState(with: focusManager.focusedZoneID)
                activatePendingFocusIfNeeded(focusManager.pendingFocusZoneID)
                reportDebugZoneState(zone: zone, layout: layout)
            }
            .onChange(of: zoneDebugSignature(zone: zone, layout: layout)) { _, _ in
                reportDebugZoneState(zone: zone, layout: layout)
            }
            .onChange(of: isTextViewFirstResponder) { _, _ in
                reportDebugZoneState(zone: zone, layout: layout)
            }
            .onChange(of: isFocused) { _, focused in
                handleMountedFocusStateChange(focused)
                reportDebugZoneState(zone: zone, layout: layout)
            }
            .onChange(of: focusManager.focusedZoneID) { _, focusedID in
                syncFocusState(with: focusedID)
                reportDebugZoneState(zone: zone, layout: layout)
            }
            .onChange(of: focusManager.pendingFocusZoneID) { _, pendingID in
                activatePendingFocusIfNeeded(pendingID)
                reportDebugZoneState(zone: zone, layout: layout)
            }
            .fullScreenCover(isPresented: $isCroppingImage) {
                if let data = zone.imageData, let img = UIImage(data: data) {
                    ImageCropEditorView(image: img) { croppedImage in
                        if let newImageData = croppedImage.jpegData(compressionQuality: 0.85) {
                            content.updateZone(at: path) { $0.imageData = newImageData }
                        }
                        isCroppingImage = false
                    } onCancel: {
                        isCroppingImage = false
                    }
                }
            }
        }
    }

    private func selectionOutline(layout: ZoneContentLayoutResult, zone: ZoneModel, active: Bool) -> some View {
        let outset = visualZoneOutset(for: zone)

        return RoundedRectangle(cornerRadius: zoneCornerRadius, style: .continuous)
            .stroke(
                active ? accent.opacity(0.35) : Color.gray.opacity(0.18),
                lineWidth: 1
            )
            .frame(
                width: layout.blockSize.width + (outset.horizontal * 2),
                height: layout.blockSize.height + (outset.vertical * 2)
            )
            .offset(x: layout.leadingInset - outset.horizontal, y: -outset.vertical)
            .allowsHitTesting(false)
    }

    private func blockFrameReporter(layout: ZoneContentLayoutResult, zone: ZoneModel) -> some View {
        let outset = visualZoneOutset(for: zone)

        return Color.clear
            .frame(
                width: layout.blockSize.width + (outset.horizontal * 2),
                height: layout.blockSize.height + (outset.vertical * 2)
            )
            .offset(x: layout.leadingInset - outset.horizontal, y: -outset.vertical)
            .allowsHitTesting(false)
            .anchorPreference(key: ZoneEditorZoneBoundsPreferenceKey.self, value: .bounds) { anchor in
                [ZoneEditorZoneBounds(path: path, zoneID: zone.id, bounds: anchor)]
            }
    }

    private func blockSurface(layout: ZoneContentLayoutResult, zone: ZoneModel) -> some View {
        let outset = visualZoneOutset(for: zone)
        let highlightTint = zone.highlightColor.zoneSurfaceTint

        return ZStack {
            RoundedRectangle(cornerRadius: zoneCornerRadius, style: .continuous)
                .fill(editorZoneFill(for: zone))
                .overlay(idleZoneStroke)
                .overlay {
                    if let highlightTint {
                        RoundedRectangle(cornerRadius: zoneCornerRadius, style: .continuous)
                            .stroke(highlightTint.opacity(0.86), lineWidth: 2)
                    }
                }
                .shadow(color: highlightTint?.opacity(0.34) ?? .clear, radius: highlightTint == nil ? 0 : 10)
        }
        .frame(
            width: layout.blockSize.width + (outset.horizontal * 2),
            height: layout.blockSize.height + (outset.vertical * 2)
        )
        .offset(x: layout.leadingInset - outset.horizontal, y: -outset.vertical)
        .allowsHitTesting(false)
    }

    private func normalizedLayoutZone(_ zone: ZoneModel) -> ZoneModel {
        if isTextResizableZone(zone) {
            var layoutZone = zone
            layoutZone.sizeMode = .auto
            if layoutZone.blockAlignment == .auto {
                layoutZone.blockAlignment = content.rootZone.leafCount == 1 ? .center : .leading
            }
            layoutZone.textAlignment = .leading
            layoutZone.fixedWidth = nil
            layoutZone.fixedHeight = nil
            return layoutZone
        }

        guard zone.sizeMode == .fixed else { return zone }

        var layoutZone = zone
        if let fixedWidth = layoutZone.fixedWidth {
            layoutZone.fixedWidth = min(max(fixedWidth, minimumResizableWidth), availableWidth)
        }
        if let fixedHeight = layoutZone.fixedHeight {
            layoutZone.fixedHeight = min(max(fixedHeight, baseMinimumResizableHeight), maximumResizableHeight)
        }

        return layoutZone
    }

    private var minimumResizableWidth: CGFloat {
        guard let zone else {
            return min(max(72, availableWidth * 0.18), availableWidth)
        }

        return minimumResizableWidth(for: zone)
    }

    private func minimumResizableWidth(for _: ZoneModel) -> CGFloat {
        min(max(72, availableWidth * 0.18), availableWidth)
    }

    private var minimumResizableHeight: CGFloat {
        baseMinimumResizableHeight
    }

    private var baseMinimumResizableHeight: CGFloat {
        baseMinimumResizableHeight(for: zone)
    }

    private func baseMinimumResizableHeight(for zone: ZoneModel?) -> CGFloat {
        let textInsets = editorTextContentInsets(for: zone)
        return max(
            48,
            ceil(textUIFont(for: zone).lineHeight + textInsets.top + textInsets.bottom)
        )
    }

    private var maximumResizableHeight: CGFloat {
        max(baseMinimumResizableHeight, ceil(maxEditableZoneHeight ?? max(availableWidth * 1.75, 520)))
    }

    private func measuredLayoutContentSize(
        for zone: ZoneModel,
        layoutZone: ZoneModel
    ) -> CGSize {
        guard isTextResizableZone(layoutZone) else {
            return renderedContentSize
        }

        let contentWidth = measuredLayoutContentWidth(for: zone, layoutZone: layoutZone)

        let measuredSize = measuredRawTextSize(
            for: layoutZone,
            width: contentWidth,
            preservesTrailingBlankLines: true
        )
        let rawHeight = layoutZone.text.isEmpty
            ? baseMinimumResizableHeight(for: zone)
            : measuredSize.height

        return CGSize(
            width: max(contentWidth, 1),
            height: min(max(rawHeight, baseMinimumResizableHeight(for: zone)), maximumResizableHeight)
        )
    }

    private func measuredLayoutContentWidth(
        for zone: ZoneModel,
        layoutZone: ZoneModel
    ) -> CGFloat {
        let maxMeasurementWidth = max(measurementWidth, availableWidth, 1)
        switch layoutZone.sizeMode {
        case .fixed:
            return min(max(layoutZone.fixedWidth ?? maxMeasurementWidth, minimumResizableWidth(for: zone)), maxMeasurementWidth)
        case .fillWidth:
            return maxMeasurementWidth
        case .auto:
            if layoutZone.text.isEmpty {
                return stableEmptyTextWidth(for: zone, constrainedTo: maxMeasurementWidth)
            }
            return rawTextMeasurementWidth(for: layoutZone, constrainedTo: maxMeasurementWidth)
        }
    }

    private func naturalBlockWidth(
        for layoutZone: ZoneModel,
        measuredContentSize: CGSize
    ) -> CGFloat {
        let minimumWidth = stableMinimumAutoWidth(for: layoutZone)
        switch layoutZone.sizeMode {
        case .fixed:
            return min(max(ceil(layoutZone.fixedWidth ?? measuredContentSize.width), minimumWidth), measurementWidth)
        case .fillWidth:
            return min(max(measurementWidth, 1), measurementWidth)
        case .auto:
            return min(max(ceil(measuredContentSize.width), minimumWidth), measurementWidth)
        }
    }

    private func contentPlacement(
        for zone: ZoneModel,
        layout: ZoneContentLayoutResult,
        measuredContentSize: CGSize
    ) -> (leadingInset: CGFloat, width: CGFloat) {
        guard isTextResizableZone(zone),
              zone.sizeMode == .auto,
              !zone.text.isEmpty else {
            return (layout.leadingInset, layout.contentLayoutWidth)
        }

        let roundedSlack = min(
            max(layout.blockSize.width - measuredContentSize.width, 0),
            1
        )
        guard roundedSlack > 0 else {
            return (layout.leadingInset, layout.contentLayoutWidth)
        }

        return (
            leadingInset: layout.leadingInset + roundedSlack / 2,
            width: max(layout.contentLayoutWidth - roundedSlack, 1)
        )
    }

    private func stableMinimumAutoWidth(for zone: ZoneModel) -> CGFloat {
        guard isTextResizableZone(zone), zone.text.isEmpty else {
            return minimumResizableWidth(for: zone)
        }

        return stableEmptyTextWidth(for: zone)
    }

    private func stableEmptyTextWidth(for zone: ZoneModel) -> CGFloat {
        stableEmptyTextWidth(for: zone, constrainedTo: availableWidth)
    }

    private func stableEmptyTextWidth(for zone: ZoneModel, constrainedTo width: CGFloat) -> CGFloat {
        min(max(156, minimumResizableWidth(for: zone)), width)
    }

    private func rawTextMeasurementWidth(
        for zone: ZoneModel,
        constrainedTo width: CGFloat
    ) -> CGFloat {
        let maxWidth = max(width, 1)
        let measuredSize = measuredRawTextSize(for: zone, width: maxWidth)
        return min(
            max(
                ceil(measuredSize.width),
                stableEmptyTextWidth(for: zone)
            ),
            maxWidth
        )
    }

    private func measuredRawTextSize(
        for zone: ZoneModel,
        width: CGFloat,
        preservesTrailingBlankLines: Bool = false
    ) -> CGSize {
        let bulletOffset = shouldShowBullet(for: zone)
            ? ZoneContentMetrics.bulletWidth + ZoneContentMetrics.bulletSpacing
            : 0
        let horizontalPadding = editorTextHorizontalPadding(for: zone) * 2
        let textViewWidth = max(width - bulletOffset - horizontalPadding, 1)
        let textInsets = editorTextContentInsets(for: zone)
        let textContainerWidth = max(
            textViewWidth - textInsets.left - textInsets.right,
            1
        )
        let textForMeasurement = preservesTrailingBlankLines
            ? zone.text
            : textWithoutTrailingBlankLines(zone.text)
        let rawText = textForMeasurement.isEmpty ? " " : textForMeasurement
        let measuredText = rawText.hasSuffix("\n") ? rawText + " " : rawText
        let textStorage = NSTextStorage(
            attributedString: NSAttributedString(
                string: measuredText,
                attributes: textMeasurementAttributes(for: zone)
            )
        )
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(width: textContainerWidth, height: .greatestFiniteMagnitude)
        )

        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0
        layoutManager.usesFontLeading = true
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let measuredWidth = usedRect.width + textInsets.left + textInsets.right + horizontalPadding + bulletOffset
        let measuredHeight = ceil(usedRect.height + textInsets.top + textInsets.bottom)

        return CGSize(
            width: measuredWidth,
            height: measuredHeight
        )
    }

    private func minimumContentHeight(forWidth width: CGFloat) -> CGFloat {
        guard let zone,
              isTextResizableZone(zone)
        else { return baseMinimumResizableHeight }

        return minimumContentHeight(for: zone, width: width)
    }

    private func minimumContentHeight(for zone: ZoneModel, width: CGFloat) -> CGFloat {
        let baseHeight = baseMinimumResizableHeight(for: zone)
        guard isTextResizableZone(zone), !zone.text.isEmpty else {
            return baseHeight
        }

        let measuredHeight = measuredTextHeight(for: zone, width: width)
        return min(max(baseHeight, measuredHeight), maximumResizableHeight)
    }

    private func measuredTextHeight(for zone: ZoneModel, width: CGFloat) -> CGFloat {
        measuredRawTextSize(for: zone, width: width).height
    }

    private func textWithoutTrailingBlankLines(_ text: String) -> String {
        var trimmed = text
        while trimmed.last == "\n" {
            trimmed.removeLast()
        }
        return trimmed
    }

    private func textMeasurementAttributes(for zone: ZoneModel) -> [NSAttributedString.Key: Any] {
        textMeasurementAttributes(for: zone, alignment: .left)
    }

    private func textMeasurementAttributes(
        for zone: ZoneModel,
        alignment: NSTextAlignment
    ) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = max(editorTextLineSpacing, 0)

        return [
            .font: textUIFont(for: zone),
            .paragraphStyle: paragraphStyle
        ]
    }

    private func isTextResizableZone(_ zone: ZoneModel) -> Bool {
        zone.contentType == .text || zone.contentType == .empty || zone.contentType == .code
    }

    private func contentFrameHeight(for zone: ZoneModel, layout: ZoneContentLayoutResult) -> CGFloat? {
        switch zone.contentType {
        case .image, .sketch:
            return layout.blockSize.height
        case .empty, .text, .code:
            return zone.sizeMode == .fixed ? layout.blockSize.height : nil
        }
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

    @ViewBuilder
    private func contentView(maxVisibleTextHeight: CGFloat) -> some View {
        switch zone?.contentType ?? .empty {
        case .empty, .text, .code:
            textViewWithGhostOverlay(maxVisibleTextHeight: maxVisibleTextHeight)
        case .image: imageView
        case .sketch: sketchView
        }
    }

    // MARK: - textViewWithGhostOverlay

    @ViewBuilder
    private func textViewWithGhostOverlay(maxVisibleTextHeight: CGFloat) -> some View {
        VStack(spacing: 8) {
            if isSelected, previewDirection == .up {
                FakeGhostBlockView()
                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
            }

            HStack(alignment: .top, spacing: 8) {
                if shouldShowBullet {
                    Circle()
                        .fill(zone?.textColor.color ?? .primary)
                        .frame(width: editorBulletSize, height: editorBulletSize)
                        .padding(.top, editorBulletTopPadding)
                }

                if shouldUseInteractiveTextSurface {
                    textEditorCore(maxVisibleTextHeight: maxVisibleTextHeight)
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if zone?.text.isEmpty ?? true {
                    emptyZonePreview
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    rawTextPreview
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: topAlignmentFor(zone))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())

            if isSelected, previewDirection == .down {
                FakeGhostBlockView()
                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var shouldUseInteractiveTextSurface: Bool {
        guard let zone else { return false }
        guard zone.contentType == .text || zone.contentType == .empty || zone.contentType == .code else {
            return false
        }

        return true
    }

    private var shouldShowBullet: Bool {
        guard let zone else { return false }
        return shouldShowBullet(for: zone)
    }

    private func shouldShowBullet(for zone: ZoneModel) -> Bool {
        zone.hasBullet && !zone.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyZonePreview: some View {
        RoundedRectangle(cornerRadius: zoneCornerRadius, style: .continuous)
            .fill(Color.clear)
            .frame(height: minimumResizableHeight)
            .contentShape(Rectangle())
    }

    private var rawTextPreview: some View {
        ZonePlainTextViewRepresentable(
            text: zone?.text ?? "",
            font: textUIFont,
            textColor: UIColor(zone?.textColor.color ?? .primary),
            textAlignment: .left,
            lineSpacing: editorTextLineSpacing,
            contentInset: editorTextContentInsets,
            forcedLineBreakTintColor: UIColor(accent)
        )
        .padding(.horizontal, editorTextHorizontalPadding)
        .contentShape(Rectangle())
    }

    private var highlightedBackground: some View {
        let rawText = zone?.text ?? ""
        let displayText = rawText.hasSuffix("\n") ? rawText + "\u{200B}" : (rawText.isEmpty ? "\u{200B}" : rawText)
        let attrString = highlightContext?.generateOverlay(for: displayText, font: textFont, highlightColor: ThemeManager.shared.accentColor.color) ?? AttributedString(displayText)
        return Text(attrString)
            .multilineTextAlignment(.leading)
            .lineSpacing(editorTextLineSpacing)
            .padding(.top, editorTextContentInsets.top)
            .padding(.leading, editorTextContentInsets.left)
            .padding(.trailing, editorTextContentInsets.right)
            .padding(.bottom, editorTextContentInsets.bottom)
            .allowsHitTesting(false)
    }

    private func fontSizeFor(_ zone: ZoneModel?) -> CGFloat {
        ZoneTextTypography.fontSize(for: zone?.textStyle ?? .body, fontScale: fontScale)
    }

    // MARK: - Text Editor Core

    @ViewBuilder
    private func textEditorCore(maxVisibleTextHeight: CGFloat) -> some View {
        let currentTextColor = zone?.textColor.color ?? .primary
        let currentTextAlignment = NSTextAlignment.left
        let currentIsBold = zone?.isBold ?? false
        let currentIsItalic = zone?.isItalic ?? false
        let currentPath = path
        let zoneID = zone?.id ?? UUID()
        let currentContentType = zone?.contentType ?? .empty
        let textInsets = editorTextContentInsets

        ZStack(alignment: .topLeading) {
            ZoneTextViewRepresentable(
                text: pureTextBinding, font: textUIFont, textColor: UIColor(currentTextColor), textAlignment: currentTextAlignment, isBold: currentIsBold, isItalic: currentIsItalic, lineSpacing: editorTextLineSpacing, contentInset: textInsets, maximumVisibleHeight: maxVisibleTextHeight, cursorTintColor: UIColor(accent), forcedLineBreakTintColor: UIColor(accent), zoneID: zoneID, isFirstResponder: isFocused,
                onTextChange: { newText in
                    if currentContentType == .text || currentContentType == .empty || currentContentType == .code {
                        highlightContext?.dismiss()
                        content.updateZone(at: currentPath) { z in z.text = newText; if z.contentType == .empty { z.contentType = .text } }
                    }
                },
                onCursorChange: { _, _ in },
                onFocusLineChange: { lineIndex, totalLines in
                    lineTracker.updateFocusedLine(for: zoneID, lineIndex: lineIndex, totalLines: totalLines)
                    zoneController.updateZoneHeightInfo(for: zoneID, lineCount: totalLines, focusedLineIndex: lineIndex)
                },
                onCaretGeometryChange: { anchorY, caretRectInWindow in
                    postCaretScrollHint(anchorY: anchorY, caretRectInWindow: caretRectInWindow)
                },
                onCommit: { },
                onFocusChange: { focused in
                    handleTextViewFocusChange(focused)
                }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if shouldShowHighlight { highlightedBackground }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, editorTextHorizontalPadding)
            .contentShape(Rectangle())
    }

    // MARK: - Focus Handling

    private func handleMountedFocusStateChange(_ focused: Bool) {
        if focused {
            highlightContext?.dismiss()
            if !isSelected { onSelect() }
        } else {
            isTextViewFirstResponder = false
            guard focusManager.focusedZoneID == currentZoneID else { return }
            focusManager.updateFocusedZone(nil)
            zoneController.updateFocusedZone(nil)
        }
    }

    private func handleTextViewFocusChange(_ focused: Bool) {
        if isTextViewFirstResponder != focused {
            isTextViewFirstResponder = focused
        }

        if isFocused != focused {
            isFocused = focused
        }

        if focused {
            highlightContext?.dismiss()
            if !isSelected {
                onSelect()
            }
            if let zoneID = currentZoneID {
                focusManager.updateFocusedZone(zoneID)
                zoneController.updateFocusedZone(zoneID)
            }
        } else if focusManager.focusedZoneID == currentZoneID {
            focusManager.updateFocusedZone(nil)
            zoneController.updateFocusedZone(nil)
        }
    }

    private func syncFocusState(with focusedZoneID: UUID?) {
        guard let zone else { return }
        let acceptsTextFocus = zone.contentType == .text
            || zone.contentType == .empty
            || zone.contentType == .code
        let shouldBeFocused = acceptsTextFocus && focusedZoneID == zone.id

        if shouldBeFocused {
            if !isSelected {
                onSelect()
            }
            if !isFocused {
                isFocused = true
            }
        } else if isFocused {
            isFocused = false
        }
    }

    private func activatePendingFocusIfNeeded(_ pendingID: UUID?) {
        guard pendingID == currentZoneID,
              let zone,
              zone.contentType == .text || zone.contentType == .empty || zone.contentType == .code else {
            return
        }

        if !isSelected {
            onSelect()
        }
        if !isFocused {
            isFocused = true
        }
    }

    private func triggerFocus() {
        if let zoneID = currentZoneID { focusManager.requestFocus(for: zoneID) }
        isFocused = true; onSelect()
    }

    private func postCaretScrollHint(anchorY: CGFloat, caretRectInWindow: CGRect) {
        let normalizedAnchorY = min(max(anchorY, 0.08), 0.92)
        lastPostedCaretAnchorY = normalizedAnchorY

        NotificationCenter.default.post(
            name: .zoneEditorCaretMoved,
            object: nil,
            userInfo: [
                ZoneEditorCaretScrollNotification.pathIDKey: path.id,
                ZoneEditorCaretScrollNotification.anchorYKey: normalizedAnchorY,
                ZoneEditorCaretScrollNotification.caretRectInWindowKey: NSValue(cgRect: caretRectInWindow)
            ]
        )
    }

    // MARK: - Debug Reporting

    private func reportDebugZoneState(zone: ZoneModel, layout: ZoneContentLayoutResult) {
        ZoneEditorDebugStore.shared.updateFocusManager(
            focusedZoneID: focusManager.focusedZoneID,
            pendingZoneID: focusManager.pendingFocusZoneID,
            retainKeyboard: focusManager.shouldRetainKeyboard
        )
        ZoneEditorDebugStore.shared.updateTextView(
            zoneID: zone.id,
            mountedFocused: isFocused,
            textViewFirstResponder: isTextViewFirstResponder,
            uiViewFirstResponder: isTextViewFirstResponder,
            requestedFirstResponder: isFocused,
            textLength: (zone.text as NSString).length
        )
        ZoneEditorDebugStore.shared.updateSelectedZone(
            pathID: path.id,
            zoneID: zone.id,
            contentType: zone.contentType.rawValue,
            sizeMode: zone.sizeMode.rawValue,
            blockAlignment: zone.blockAlignment.rawValue,
            textAlignment: zone.textAlignment.rawValue,
            verticalAlignment: zone.verticalAlignment.rawValue,
            fixedWidth: zone.fixedWidth,
            fixedHeight: zone.fixedHeight
        )
        ZoneEditorDebugStore.shared.updateSelectedLayout(
            blockSize: layout.blockSize,
            contentWidth: layout.contentLayoutWidth,
            leadingInset: layout.leadingInset,
            renderedSize: renderedContentSize,
            isSelected: isSelected
        )
    }

    private func zoneDebugSignature(zone: ZoneModel, layout: ZoneContentLayoutResult) -> String {
        let parts: [String] = [
            path.id,
            zone.id.uuidString,
            zone.contentType.rawValue,
            zone.sizeMode.rawValue,
            zone.blockAlignment.rawValue,
            zone.textAlignment.rawValue,
            zone.verticalAlignment.rawValue,
            String((zone.text as NSString).length),
            String(Int(zone.fixedWidth ?? -1)),
            String(Int(zone.fixedHeight ?? -1)),
            String(Int(layout.blockSize.width)),
            String(Int(layout.blockSize.height)),
            String(Int(layout.leadingInset)),
            String(Int(renderedContentSize.width)),
            String(Int(renderedContentSize.height)),
            isSelected ? "selected" : "idle",
            isFocused ? "mounted" : "unmounted"
        ]
        return parts.joined(separator: "|")
    }

    // MARK: - Pure Text Binding

    /// Returns a binding that writes zone text changes to the content tree.
    ///
    /// Avoids redundant writes by checking for equality before mutating the tree,
    /// preventing superfluous `@Observable` invalidations.
    ///
    /// Note: The binding intentionally does NOT strip or alter math delimiters (e.g. `$$`)
    /// so that KaTeX rendering is not disrupted while the user edits math content.
    private var pureTextBinding: Binding<String> {
        Binding(get: {
            return zone?.text ?? ""
        }, set: { newValue in
            if self.zone?.text != newValue {
                highlightContext?.dismiss()
                content.updateZone(at: path) { zone in
                    zone.text = newValue
                    if zone.contentType == .empty { zone.contentType = .text }
                }
            }
        })
    }

    private var textFont: Font {
        guard let zone else {
            return ZoneTextTypography.font(
                family: .system,
                style: .body,
                isBold: false,
                isItalic: false,
                fontScale: fontScale
            )
        }
        return ZoneTextTypography.font(for: zone, fontScale: fontScale)
    }
    private var textUIFont: UIFont {
        textUIFont(for: zone)
    }

    private func textUIFont(for zone: ZoneModel?) -> UIFont {
        guard let zone else {
            return ZoneTextTypography.uiFont(
                family: .system,
                style: .body,
                isBold: false,
                isItalic: false,
                fontScale: fontScale
            )
        }
        return ZoneTextTypography.uiFont(for: zone, fontScale: fontScale)
    }

    private var editorTextHorizontalPadding: CGFloat {
        editorTextHorizontalPadding(for: zone)
    }

    private func editorTextHorizontalPadding(for zone: ZoneModel?) -> CGFloat {
        guard zone.map(isTextResizableZone) == true else { return 0 }
        return 0
    }

    private var editorTextLineSpacing: CGFloat {
        ZoneTextTypography.lineSpacing(for: zone?.textStyle ?? .body, fontScale: fontScale)
    }

    private var editorTextVerticalPadding: CGFloat {
        editorTextContentInsets.top + editorTextContentInsets.bottom
    }

    private var editorTextContentInsets: UIEdgeInsets {
        editorTextContentInsets(for: zone)
    }

    private func editorTextContentInsets(for zone: ZoneModel?) -> UIEdgeInsets {
        guard let zone,
              isTextResizableZone(zone) else {
            return .zero
        }

        return UIEdgeInsets(
            top: zoneTextVerticalPadding,
            left: zoneTextHorizontalPadding,
            bottom: zoneTextVerticalPadding,
            right: zoneTextHorizontalPadding
        )
    }

    private var zoneCornerRadius: CGFloat {
        18
    }

    private func visualZoneOutset(for zone: ZoneModel?) -> (horizontal: CGFloat, vertical: CGFloat) {
        guard let zone,
              isTextResizableZone(zone) else {
            return (horizontal: 0, vertical: 0)
        }

        return (horizontal: 0, vertical: 0)
    }

    private var zoneTextHorizontalPadding: CGFloat { 12 }

    private var zoneTextVerticalPadding: CGFloat { 16 }

    private var editorBulletSize: CGFloat {
        ZoneContentMetrics.bulletWidth
    }

    private var editorBulletTopPadding: CGFloat {
        let centeredInFirstLine = (textUIFont.lineHeight - editorBulletSize) / 2
        return editorTextContentInsets.top + max(centeredInFirstLine, 0)
    }

    private func editorZoneFill(for zone: ZoneModel) -> Color {
        zone.highlightColor.zoneSurfaceFill
    }

    // MARK: - Image View
    @ViewBuilder
    private var imageView: some View {
        if let data = zone?.imageData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .scaleEffect(isPressingImage ? 0.95 : 1.0)
                .opacity(isPressingImage ? 0.85 : 1.0)
                .shadow(color: .black.opacity(isPressingImage ? 0.0 : 0.08), radius: 4, y: 2)
                .contentShape(Rectangle())
                .onLongPressGesture(
                    minimumDuration: 0.5,
                    perform: {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        isCroppingImage = true
                    },
                    onPressingChanged: { isPressing in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            self.isPressingImage = isPressing
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Sketch View
    @ViewBuilder
    private var sketchView: some View {
        if let data = zone?.imageData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .background(colorScheme == .dark ? Color.black : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Alignment Helper
    @ViewBuilder
    private var idleZoneStroke: some View {
        if !isSelected {
            RoundedRectangle(cornerRadius: zoneCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        }
    }

    private func alignmentFor(_ zone: ZoneModel?) -> Alignment { .leading }
    private func topAlignmentFor(_ zone: ZoneModel?) -> Alignment { .topLeading }
}

struct CardFaceView: View {
    let zone: ZoneModel
    let fontScale: CGFloat
    var onTap: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    init(
        zone: ZoneModel,
        fontScale: CGFloat = 1.0,
        onTap: (() -> Void)? = nil
    ) {
        self.zone = zone
        self.fontScale = fontScale
        self.onTap = onTap
    }

    var body: some View {
        if zone.isLeaf { leafPreview } else { containerPreview }
    }

    @ViewBuilder
    private var leafPreview: some View {
        switch zone.contentType {
        case .empty:
            Color.clear.frame(height: 28).padding(.vertical, 4)
        case .text, .code:
            if !zone.text.isEmpty {
                let previewText = displayText(for: zone)
                if zone.contentType == .code || previewText.hasPrefix("```") {
                    CodeSnippetView(
                        rawText: previewText,
                        fontSize: fontSizeFor(zone) * CodeSnippetMetrics.relativeFontScale
                    )
                        .padding(.vertical, 4)
                }
                else {
                    HStack(alignment: .top, spacing: 8) {
                        if zone.hasBullet {
                            Circle()
                                .fill(zone.textColor.color)
                                .frame(
                                    width: ZoneContentMetrics.bulletWidth,
                                    height: ZoneContentMetrics.bulletWidth
                                )
                                .padding(.top, previewBulletTopPadding(for: zone))
                        }
                        MixedMathTextView(
                            text: previewText,
                            fontSize: fontSizeFor(zone),
                            fontFamily: zone.fontFamily,
                            textColor: zone.textColor.color,
                            alignment: TextBlockAlignment.leading.horizontalAlignment,
                            isBold: zone.isBold,
                            isItalic: zone.isItalic,
                            isInteractive: false,
                            allowsReadOnlyOverflowScrolling: true,
                            onTap: onTap
                        )
                        .padding(.vertical, 4)
                        .padding(.horizontal, zone.highlightColor != HighlightColor.none ? 6 : 0)
                        .background {
                            if let color = zone.highlightColor.color {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(color)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .image:
            if let data = zone.imageData { CachedImageView(data: data, scale: zone.imageScale, alignment: zone.textAlignment, cornerRadius: 10) }
        case .sketch:
            if let data = zone.imageData { CachedImageView(data: data, scale: zone.imageScale, alignment: zone.textAlignment, cornerRadius: 10, isSketch: true) }
        }
    }

    private func displayText(for zone: ZoneModel) -> String {
        switch zone.contentType {
        case .text:
            return ZoneForcedLineBreak.renderText(
                MathTextSanitizer.stripTerminalZonePeriodPreservingWhitespace(zone.text)
            )
        default:
            return ZoneForcedLineBreak.renderText(zone.text)
        }
    }

    private func fontSizeFor(_ zone: ZoneModel) -> CGFloat {
        ZoneTextTypography.fontSize(for: zone.textStyle, fontScale: fontScale)
    }

    private func previewBulletTopPadding(for zone: ZoneModel) -> CGFloat {
        let lineHeight = ZoneTextTypography.uiFont(for: zone, fontScale: fontScale).lineHeight
        return 4 + max((lineHeight - ZoneContentMetrics.bulletWidth) / 2, 0)
    }

    @ViewBuilder
    private var containerPreview: some View {
        let children = zone.children ?? []
        if zone.direction == .horizontal {
            HStack(alignment: .top, spacing: 12) {
                ForEach(children) { child in
                    CardFaceView(
                        zone: child,
                        fontScale: fontScale,
                        onTap: onTap
                    )
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(children) { child in
                    CardFaceView(
                        zone: child,
                        fontScale: fontScale,
                        onTap: onTap
                    )
                }
            }
        }
    }

    private func previewFont(for zone: ZoneModel) -> Font {
        ZoneTextTypography.font(for: zone, fontScale: fontScale)
    }
}

// MARK: - Cached Image View

struct CachedImageView: View {
    let data: Data
    let scale: CGFloat
    let alignment: TextBlockAlignment
    let cornerRadius: CGFloat
    var isSketch: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let image = uiImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background {
                        if isSketch {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(colorScheme == .dark ? Color.black : Color.white)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            } else { ProgressView().frame(height: 100) }
        }
            .task { loadImage() }
            .onDisappear {
                // Force release the rendered bitmap memory immediately when the card disappears
                self.uiImage = nil
            }
    }

    private func loadImage() {
        Task.detached {
            let optimizedImage = await ImageCache.shared.image(for: data, id: String(data.hashValue), targetSize: CGSize(width: 800, height: 800), scale: 1.0)
            await MainActor.run { self.uiImage = optimizedImage ?? UIImage(data: data) }
        }
    }
}

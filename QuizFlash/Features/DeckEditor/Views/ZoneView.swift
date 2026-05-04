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
    var previewDirection: Binding<AddDirection?>

    private var zone: ZoneModel? { content.zone(at: path) }
    private var isSelected: Bool { selectedPath == path }

    init(
        content: ZoneCardContent,
        path: ZonePath,
        selectedPath: Binding<ZonePath?>,
        highlightContext: HighlightContext?,
        fontScale: CGFloat = 1.0,
        availableWidth: CGFloat = 320,
        previewDirection: Binding<AddDirection?> = .constant(nil)
    ) {
        self.content = content
        self.path = path
        self._selectedPath = selectedPath
        self.highlightContext = highlightContext
        self.fontScale = fontScale
        self.availableWidth = availableWidth
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
            onSelect: { selectZone() },
            previewDirection: previewDirection
        )
            .id(path.id)
    }

    // MARK: - Container Zone View

    @ViewBuilder
    private func containerZoneView(zone: ZoneModel) -> some View {
        let children = zone.children ?? []

        VStack(spacing: 8) {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, _ in
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
                    availableWidth: availableWidth,
                    previewDirection: maskedPreviewDirection(for: isChildSelected)
                )
                .frame(width: availableWidth, alignment: .topLeading)

                if isChildSelected, previewDirection.wrappedValue == .down {
                    FakeGhostBlockView()
                        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                }
            }
        }
        .frame(width: availableWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
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
        if !wasSelected {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// MARK: - Zone Content View (Leaf)

private enum ZoneResizeDragAxis {
    case horizontal
    case vertical
    case free
}

/// Renders the content of a single leaf zone: text editor, image, or sketch.
///
/// Handles:
/// - Focus negotiation with `ZoneFocusManager` and `ZoneController`
/// - Switching between `ZoneTextViewRepresentable` (edit mode) and
///   `MixedMathTextView` / `CodeSnippetView` (preview mode)
/// - Image long-press → full-screen `ImageCropEditorView`
/// - Ghost block overlays for vertical zone insertion
struct ZoneContentView: View {
    @Bindable var content: ZoneCardContent
    let path: ZonePath
    let isSelected: Bool
    var highlightContext: HighlightContext?
    var fontScale: CGFloat
    var availableWidth: CGFloat
    var onSelect: () -> Void
    @Binding var previewDirection: AddDirection?

    @State private var isFocused: Bool = false
    @State private var isCroppingImage: Bool = false
    @State private var isPressingImage: Bool = false
    @State private var renderedContentSize: CGSize = .zero
    @State private var resizeStartSize: CGSize?
    @State private var resizeLastCommittedSize: CGSize?
    @State private var resizeDragAxis: ZoneResizeDragAxis?
    @State private var liveResizeSize: CGSize?
    @State private var lastPostedCaretAnchorY: CGFloat?
    @State private var isResizingZone: Bool = false
    @State private var isTextViewFirstResponder: Bool = false
    @State private var resizeHeightRequirementCache: [Int: CGFloat] = [:]
    @State private var lastResizeFeedbackStep: CGSize?
    @State private var lastResizeFeedbackTime: TimeInterval = 0
    @State private var lastResizeScrollPostTime: TimeInterval = 0
    @State private var lastResizeScrollTranslationHeight: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppPreferences.self) private var appPreferences
    private var focusManager = ZoneFocusManager.shared
    private var zoneController = ZoneController.shared
    private var lineTracker = ZoneLineTracker.shared

    private var zone: ZoneModel? { content.zone(at: path) }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var currentZoneID: UUID? { zone?.id }
    private var locale: Locale { appPreferences.resolvedLocale }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    init(
        content: ZoneCardContent,
        path: ZonePath,
        isSelected: Bool,
        highlightContext: HighlightContext? = nil,
        fontScale: CGFloat = 1.0,
        availableWidth: CGFloat = 320,
        onSelect: @escaping () -> Void,
        previewDirection: Binding<AddDirection?> = .constant(nil)
    ) {
        self.content = content
        self.path = path
        self.isSelected = isSelected
        self.highlightContext = highlightContext
        self.fontScale = fontScale
        self.availableWidth = availableWidth
        self.onSelect = onSelect
        self._previewDirection = previewDirection
    }

    private var shouldShowHighlight: Bool {
        guard let highlightContext = highlightContext, let zone = zone else { return false }
        return highlightContext.shouldHighlight(text: zone.text)
    }

    var body: some View {
        if let zone {
            let layoutZone = normalizedLayoutZone(resizePreviewZone(for: zone))
            let measuredContentSize = measuredLayoutContentSize(
                for: zone,
                layoutZone: layoutZone
            )
            let layout = CardZoneLayoutEngine.leafLayout(
                for: layoutZone,
                spec: CardZoneLayoutSpec(
                    availableWidth: availableWidth,
                    fontScale: fontScale,
                    minimumAutoWidth: isSelected || isFocused ? 156 : 1
                ),
                measuredContentSize: measuredContentSize
            )

            ZStack(alignment: .topLeading) {
                blockFrameReporter(layout: layout, zoneID: zone.id)
                blockSurface(layout: layout, zone: zone)

                if isTextViewFirstResponder {
                    selectedOutline(layout: layout)
                } else if isSelected {
                    selectedIdleOutline(layout: layout)
                }

                contentView(layout: layout)
                    .frame(
                        width: layout.contentLayoutWidth,
                        height: layoutZone.sizeMode == .fixed ? layout.blockSize.height : nil,
                        alignment: .topLeading
                    )
                    .clipped()
                    .offset(x: layout.leadingInset)
                    .onGeometryChange(for: CGSize.self) { proxy in
                        CGSize(width: ceil(proxy.size.width), height: ceil(proxy.size.height))
                    } action: { newSize in
                        if !layout.usesIntrinsicTextMeasurement {
                            updateRenderedContentSize(newSize)
                        }
                    }

                if isSelected {
                    resizeHandle(layout: layout)
                }
            }
            .frame(width: availableWidth, height: layout.blockSize.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    guard !isResizingZone else { return }
                    onSelect()

                    let type = zone.contentType

                    if type == .text || type == .empty || type == .code {
                        if !isTextViewFirstResponder {
                            let cursorLocation = cursorLocation(
                                forTapAt: value.location,
                                layout: layout,
                                zone: zone
                            )
                            focusManager.requestCursorLocation(cursorLocation, for: zone.id)
                            ZoneEditorDebugStore.shared.recordTap(
                                "tap zone path=\(path.id) type=\(zone.contentType.rawValue) cursor=\(cursorLocation)"
                            )
                        } else {
                            ZoneEditorDebugStore.shared.recordTap(
                                "tap zone path=\(path.id) type=\(zone.contentType.rawValue)"
                            )
                        }
                        if !isTextViewFirstResponder {
                            focusManager.requestFocus(for: zone.id)
                            isFocused = true
                        }
                    } else {
                        ZoneEditorDebugStore.shared.recordTap("tap zone path=\(path.id) type=\(zone.contentType.rawValue)")
                        focusManager.updateFocusedZone(zone.id)
                        zoneController.updateFocusedZone(zone.id)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            )
            .onAppear {
                syncFocusState(with: focusManager.focusedZoneID)
                reportDebugZoneState(zone: zone, layout: layout)
            }
            .onChange(of: zoneDebugSignature(zone: zone, layout: layout)) { _, _ in
                reportDebugZoneState(zone: zone, layout: layout)
            }
            .onChange(of: isTextViewFirstResponder) { _, _ in
                reportDebugZoneState(zone: zone, layout: layout)
            }
            .onChange(of: isResizingZone) { _, _ in
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
                if pendingID == currentZoneID {
                    if zone.contentType == .text || zone.contentType == .empty {
                        if !isSelected {
                            onSelect()
                        }
                        isFocused = true
                    }
                    focusManager.clearPendingFocus()
                }
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

    private func selectedOutline(layout: CardZoneLayoutResult) -> some View {
        RoundedRectangle(cornerRadius: zoneCornerRadius, style: .continuous)
            .stroke(
                accent.opacity(0.95),
                style: StrokeStyle(lineWidth: 1.6, dash: [5, 4])
            )
            .frame(width: layout.blockSize.width, height: layout.blockSize.height)
            .offset(x: layout.leadingInset)
            .allowsHitTesting(false)
    }

    private func selectedIdleOutline(layout: CardZoneLayoutResult) -> some View {
        RoundedRectangle(cornerRadius: zoneCornerRadius, style: .continuous)
            .stroke(Color.gray.opacity(0.22), lineWidth: 1)
            .frame(width: layout.blockSize.width, height: layout.blockSize.height)
            .offset(x: layout.leadingInset)
            .allowsHitTesting(false)
    }

    private func blockFrameReporter(layout: CardZoneLayoutResult, zoneID: UUID) -> some View {
        Color.clear
            .frame(width: layout.blockSize.width, height: layout.blockSize.height)
            .offset(x: layout.leadingInset)
            .allowsHitTesting(false)
            .anchorPreference(key: ZoneEditorZoneBoundsPreferenceKey.self, value: .bounds) { anchor in
                [ZoneEditorZoneBounds(path: path, zoneID: zoneID, bounds: anchor)]
            }
    }

    private func blockSurface(layout: CardZoneLayoutResult, zone: ZoneModel) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: zoneCornerRadius, style: .continuous)
                .fill(Color.gray.opacity(0.05))
                .overlay(idleZoneStroke)
            if let highlight = zone.highlightColor.color {
                RoundedRectangle(cornerRadius: zoneCornerRadius, style: .continuous)
                    .fill(highlight)
            }
        }
        .frame(width: layout.blockSize.width, height: layout.blockSize.height)
        .offset(x: layout.leadingInset)
        .allowsHitTesting(false)
    }

    private func resizeHandle(layout: CardZoneLayoutResult) -> some View {
        let captureOutset: CGFloat = 36
        let cornerHitSize: CGFloat = 132
        let captureWidth = max(layout.blockSize.width + (captureOutset * 2), cornerHitSize)
        let captureHeight = max(layout.blockSize.height + (captureOutset * 2), cornerHitSize)
        let glyphSize: CGFloat = 13
        let glyphOutset: CGFloat = 3

        return ZStack(alignment: .topLeading) {
            ZoneResizeTouchCapture(
                cornerHitSize: cornerHitSize,
                onChanged: { translation in
                    handleResizeChange(
                        translation: translation,
                        startSize: layout.blockSize
                    )
                },
                onEnded: {
                    finishResize()
                }
            )
            .frame(width: captureWidth, height: captureHeight)
            .offset(x: layout.leadingInset + layout.blockSize.width - captureWidth + captureOutset,
                    y: layout.blockSize.height - captureHeight + captureOutset)

            ZoneResizeCornerHandle(accent: accent, isActive: isResizingZone)
                .frame(width: glyphSize, height: glyphSize)
                .offset(
                    x: layout.leadingInset + layout.blockSize.width - glyphSize + glyphOutset,
                    y: layout.blockSize.height - glyphSize + glyphOutset
                )
                .allowsHitTesting(false)
        }
        .frame(width: availableWidth, height: layout.blockSize.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .zIndex(10_000)
        .accessibilityLabel(localized("Resize Zone"))
        .onAppear {
            ZoneEditorDebugStore.shared.updateResizeHandle(
                blockSize: layout.blockSize,
                hitSize: CGSize(width: cornerHitSize, height: cornerHitSize),
                glyphSize: glyphSize,
                selected: isSelected
            )
        }
        .onChange(of: resizeHandleDebugSignature(layout: layout, hitWidth: cornerHitSize, hitHeight: cornerHitSize, glyphSize: glyphSize)) { _, _ in
            ZoneEditorDebugStore.shared.updateResizeHandle(
                blockSize: layout.blockSize,
                hitSize: CGSize(width: cornerHitSize, height: cornerHitSize),
                glyphSize: glyphSize,
                selected: isSelected
            )
        }
    }

    private func resizePreviewZone(for zone: ZoneModel) -> ZoneModel {
        guard let liveResizeSize else { return zone }
        var previewZone = zone
        previewZone.sizeMode = .fixed
        previewZone.fixedWidth = liveResizeSize.width
        previewZone.fixedHeight = liveResizeSize.height
        return previewZone
    }

    private func normalizedLayoutZone(_ zone: ZoneModel) -> ZoneModel {
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

    private func handleResizeChange(translation: CGSize, startSize: CGSize) {
        if resizeStartSize == nil {
            resizeStartSize = startSize
            resizeLastCommittedSize = startSize
            resizeDragAxis = nil
            isResizingZone = true
            resizeHeightRequirementCache.removeAll(keepingCapacity: true)
            lastResizeFeedbackStep = nil
            lastResizeFeedbackTime = 0
            lastResizeScrollPostTime = 0
            lastResizeScrollTranslationHeight = 0
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            ZoneEditorDebugStore.shared.recordEvent("resize start path=\(path.id)")
        }

        let baseSize = resizeStartSize ?? startSize
        let axis = resolvedResizeAxis(for: translation)
        let widthDelta = axis == .vertical ? 0 : translation.width
        let heightDelta = axis == .horizontal ? 0 : translation.height
        let maxWidth = max(availableWidth, 1)
        let rawWidth = min(
            max(baseSize.width + widthDelta, minimumResizableWidth),
            maxWidth
        )
        let nextWidth = snappedResizeWidth(rawWidth)
        let rawHeight = min(
            max(baseSize.height + heightDelta, baseMinimumResizableHeight),
            maximumResizableHeight
        )
        let proposedHeight = continuousResizeHeight(rawHeight)
        let requiredHeight = cachedMinimumContentHeight(forWidth: nextWidth)
        let nextHeight = min(
            max(proposedHeight, requiredHeight, baseMinimumResizableHeight),
            maximumResizableHeight
        )

        let nextSize = CGSize(width: nextWidth, height: nextHeight)
        ZoneEditorDebugStore.shared.updateResizeCalculation(
            axis: resizeAxisDebugName(axis),
            startSize: baseSize,
            nextSize: nextSize,
            translation: translation
        )

        if let last = resizeLastCommittedSize,
           abs(last.width - nextSize.width) < 2,
           abs(last.height - nextSize.height) < 2 {
            return
        }

        resizeLastCommittedSize = nextSize
        commitLiveResize(nextSize, translation: translation)
    }

    private func finishResize() {
        defer {
            resizeStartSize = nil
            resizeLastCommittedSize = nil
            resizeDragAxis = nil
            liveResizeSize = nil
            resizeHeightRequirementCache.removeAll(keepingCapacity: false)
            lastResizeFeedbackStep = nil
            lastResizeScrollTranslationHeight = 0
            isResizingZone = false
        }

        guard let finalSize = liveResizeSize else { return }
        let minimumWidth = minimumResizableWidth
        let minimumHeight = baseMinimumResizableHeight
        let maximumHeight = maximumResizableHeight
        let safeFinalSize = CGSize(
            width: min(max(finalSize.width, minimumWidth), availableWidth),
            height: min(max(finalSize.height, minimumHeight), maximumHeight)
        )
        let requiredFinalHeight = minimumContentHeight(forWidth: safeFinalSize.width)
        let finalFixedHeight = min(
            max(safeFinalSize.height, requiredFinalHeight, minimumHeight),
            maximumHeight
        )
        ZoneEditorDebugStore.shared.recordEvent(
            "resize finish final=\(Int(safeFinalSize.width))x\(Int(safeFinalSize.height)) requiredH=\(Int(requiredFinalHeight))"
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        content.updateZone(at: path) { zone in
            zone.sizeMode = .fixed
            zone.fixedWidth = safeFinalSize.width
            zone.fixedHeight = finalFixedHeight
        }
    }

    private func resolvedResizeAxis(for translation: CGSize) -> ZoneResizeDragAxis {
        .free
    }

    private func snappedResizeWidth(_ width: CGFloat) -> CGFloat {
        let grid: CGFloat = 4
        let maxWidth = max(availableWidth, minimumResizableWidth)
        if width >= maxWidth - (grid / 2) {
            return maxWidth
        }

        return min(max((width / grid).rounded() * grid, minimumResizableWidth), maxWidth)
    }

    private func continuousResizeHeight(_ height: CGFloat) -> CGFloat {
        return min(
            max(height, baseMinimumResizableHeight),
            maximumResizableHeight
        )
    }

    private func commitLiveResize(_ size: CGSize, translation: CGSize) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            liveResizeSize = size
        }
        triggerResizeFeedbackIfNeeded(for: size)
        postResizeScrollHintIfNeeded(translation: translation)
    }

    private func cachedMinimumContentHeight(forWidth width: CGFloat) -> CGFloat {
        let key = Int((width * 2).rounded())
        if let cached = resizeHeightRequirementCache[key] {
            return cached
        }

        let measuredHeight = minimumContentHeight(forWidth: width)
        resizeHeightRequirementCache[key] = measuredHeight
        return measuredHeight
    }

    private func triggerResizeFeedbackIfNeeded(for size: CGSize) {
        let feedbackStep = CGSize(
            width: floor(size.width / 24),
            height: floor(size.height / 24)
        )
        guard feedbackStep != lastResizeFeedbackStep else { return }

        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastResizeFeedbackTime >= 0.11 else { return }

        UISelectionFeedbackGenerator().selectionChanged()
        lastResizeFeedbackStep = feedbackStep
        lastResizeFeedbackTime = now
    }

    private func postResizeScrollHintIfNeeded(translation: CGSize) {
        let deltaY = translation.height - lastResizeScrollTranslationHeight
        guard abs(deltaY) >= 1.5 else { return }

        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastResizeScrollPostTime >= 0.04 else { return }
        lastResizeScrollPostTime = now
        lastResizeScrollTranslationHeight = translation.height

        let anchorY: CGFloat
        if translation.height > 12 {
            anchorY = 0.90
        } else if translation.height < -12 {
            anchorY = 0.12
        } else {
            anchorY = 0.55
        }

        NotificationCenter.default.post(
            name: .zoneEditorResizeHandleMoved,
            object: nil,
            userInfo: [
                ZoneEditorResizeScrollNotification.pathIDKey: path.id,
                ZoneEditorResizeScrollNotification.anchorYKey: anchorY,
                ZoneEditorResizeScrollNotification.deltaYKey: deltaY
            ]
        )
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
        max(36, fontSizeFor(zone) + 12)
    }

    private var maximumResizableHeight: CGFloat {
        max(availableWidth * 1.75, 520)
    }

    private func measuredLayoutContentSize(
        for zone: ZoneModel,
        layoutZone: ZoneModel
    ) -> CGSize {
        if layoutZone.sizeMode != .fixed,
           layoutZone.contentType == .empty,
           layoutZone.text.isEmpty {
            return renderedContentSize
        }

        guard isTextResizableZone(layoutZone) else {
            return renderedContentSize
        }

        if layoutZone.sizeMode != .fixed,
           usesDeterministicPlainTextLayout(layoutZone),
           !needsFocusedRawTextMeasurement(layoutZone) {
            return .zero
        }

        let estimatedSize = FlashcardGridContentEstimator.estimatedSize(
            for: layoutZone,
            fontScale: fontScale,
            availableWidth: availableWidth
        )
        let previewWidth = renderedContentSize.width > 0
            ? renderedContentSize.width
            : estimatedSize.width
        let previewHeight = renderedContentSize.height > 0
            ? renderedContentSize.height
            : estimatedSize.height

        let contentWidth: CGFloat
        if layoutZone.sizeMode == .fixed {
            contentWidth = min(
                max(layoutZone.fixedWidth ?? previewWidth, minimumResizableWidth(for: zone)),
                availableWidth
            )
        } else {
            contentWidth = min(max(previewWidth, 1), availableWidth)
        }

        let previewSize = CGSize(
            width: max(contentWidth, 1),
            height: max(previewHeight, 1)
        )

        guard layoutZone.sizeMode == .fixed || needsFocusedRawTextMeasurement(layoutZone) else {
            return previewSize
        }

        let editorRequiredHeight = minimumContentHeight(
            for: zone,
            width: contentWidth
        )

        return CGSize(
            width: max(contentWidth, 1),
            height: max(previewSize.height, editorRequiredHeight)
        )
    }

    private func cursorLocation(
        forTapAt point: CGPoint,
        layout: CardZoneLayoutResult,
        zone: ZoneModel
    ) -> Int {
        let nsText = zone.text as NSString
        guard nsText.length > 0 else { return 0 }

        let bulletOffset = zone.hasBullet
            ? CardZoneContentMetrics.bulletWidth + CardZoneContentMetrics.bulletSpacing
            : 0
        let textViewX = point.x
            - layout.leadingInset
            - bulletOffset
            - editorTextHorizontalPadding(for: zone)
        let textViewY = point.y
        let textViewWidth = max(
            layout.contentLayoutWidth
            - bulletOffset
            - (editorTextHorizontalPadding(for: zone) * 2),
            1
        )

        let textStorage = NSTextStorage(
            attributedString: NSAttributedString(
                string: zone.text,
                attributes: textMeasurementAttributes(for: zone)
            )
        )
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(width: textViewWidth, height: .greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0
        layoutManager.usesFontLeading = true
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let containerPoint = CGPoint(
            x: min(max(textViewX - editorTextContentInsets.left, 0), textViewWidth),
            y: max(textViewY - editorTextContentInsets.top, 0)
        )
        let characterIndex = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )

        return min(max(characterIndex, 0), nsText.length)
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
        let textViewWidth = max(width - (editorTextHorizontalPadding(for: zone) * 2), 1)
        let textContainerWidth = max(
            textViewWidth - editorTextContentInsets.left - editorTextContentInsets.right,
            1
        )
        let rawText = zone.text.isEmpty ? " " : zone.text
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

        return ceil(
            usedRect.height
            + editorTextContentInsets.top
            + editorTextContentInsets.bottom
            + 2
        )
    }

    private func textMeasurementAttributes(for zone: ZoneModel) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = zone.textAlignment.nsTextAlignment
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

    private func usesDeterministicPlainTextLayout(_ zone: ZoneModel) -> Bool {
        guard zone.contentType == .text else { return false }
        let text = MathTextSanitizer.stripTerminalZonePeriod(zone.text)
        return !MathTextSanitizer.containsMath(text)
            && !MathTextSanitizer.containsInlineCode(text)
            && !text.contains("**")
            && !text.hasPrefix("```")
    }

    private func needsFocusedRawTextMeasurement(_ zone: ZoneModel) -> Bool {
        guard isFocused || isTextViewFirstResponder else { return false }
        guard zone.contentType == .text || zone.contentType == .code else { return false }

        let text = MathTextSanitizer.stripTerminalZonePeriod(zone.text)
        return zone.contentType == .code
            || MathTextSanitizer.containsMath(text)
            || MathTextSanitizer.containsInlineCode(text)
            || text.contains("**")
            || text.hasPrefix("```")
    }

    private func updateRenderedContentSize(_ newSize: CGSize) {
        guard !isResizingZone else { return }
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
        guard !isResizingZone else { return }
        guard newHeight > 0 else { return }
        let clampedHeight = max(ceil(newHeight), 1)
        if abs(renderedContentSize.height - clampedHeight) > 0.5 {
            renderedContentSize = CGSize(
                width: renderedContentSize.width,
                height: clampedHeight
            )
        }
    }

    @ViewBuilder
    private func contentView(layout: CardZoneLayoutResult) -> some View {
        switch zone?.contentType ?? .empty {
        case .empty, .text, .code: textViewWithGhostOverlay(layout: layout)
        case .image: imageView
        case .sketch: sketchView
        }
    }

    // MARK: - textViewWithGhostOverlay

    @ViewBuilder
    private func textViewWithGhostOverlay(layout: CardZoneLayoutResult) -> some View {
        VStack(spacing: 8) {
            if isSelected, previewDirection == .up {
                FakeGhostBlockView()
                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
            }

            HStack(alignment: .top, spacing: 8) {
                if zone?.hasBullet == true {
                    Circle()
                        .fill(zone?.textColor.color ?? .primary)
                        .frame(width: 6, height: 6)
                        .padding(.top, 10)
                }

                if isFocused {
                    textEditorCore
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if zone?.text.isEmpty ?? true {
                    emptyZonePreview
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    renderedTextPreview(layout: layout)
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

    private var emptyZonePreview: some View {
        RoundedRectangle(cornerRadius: zoneCornerRadius, style: .continuous)
            .fill(Color.clear)
            .frame(height: minimumResizableHeight)
            .contentShape(Rectangle())
    }

    private func renderedTextPreview(layout: CardZoneLayoutResult) -> some View {
        let textInsets = editorTextContentInsets
        return Group {
            if zone?.contentType == .code || zone?.text.hasPrefix("```") == true {
                CodeSnippetView(rawText: zone?.text ?? "")
                    .padding(.top, textInsets.top)
                    .padding(.bottom, textInsets.bottom)
                    .padding(.leading, textInsets.left)
                    .padding(.trailing, textInsets.right)
                    .onGeometryChange(for: CGSize.self) { proxy in
                        CGSize(width: ceil(proxy.size.width), height: ceil(proxy.size.height))
                    } action: { size in
                        updateRenderedContentHeight(size.height)
                    }
            } else {
                renderedPlainOrRichTextPreview(textInsets: textInsets, layout: layout)
                    .background(Color.clear)
                    .onGeometryChange(for: CGSize.self) { proxy in
                        CGSize(width: ceil(proxy.size.width), height: ceil(proxy.size.height))
                    } action: { size in
                        updateRenderedContentHeight(size.height)
                    }
                    .contentShape(Rectangle())
            }
        }
    }

    @ViewBuilder
    private func renderedPlainOrRichTextPreview(
        textInsets: UIEdgeInsets,
        layout: CardZoneLayoutResult
    ) -> some View {
        if shouldUseRichTextPreview {
            let widthLimit = layout.textWidthLimit ?? max(
                layout.contentLayoutWidth
                - layout.textHorizontalInsets
                - layout.bulletHorizontalInset,
                1
            )
            MixedMathTextView(
                text: zone?.text ?? "",
                fontSize: fontSizeFor(zone),
                textColor: zone?.textColor.color ?? .primary,
                alignment: alignmentFor(zone).horizontalAlignment,
                isBold: zone?.isBold ?? false,
                isItalic: zone?.isItalic ?? false,
                isInteractive: false,
                intrinsicWidthLimit: widthLimit,
                onIntrinsicContentSizeChange: { size in
                    updateRenderedContentSize(
                        CGSize(
                            width: ceil(size.width + layout.textHorizontalInsets + layout.bulletHorizontalInset),
                            height: ceil(size.height + editorTextVerticalPadding)
                        )
                    )
                }
            )
            .padding(.top, textInsets.top)
            .padding(.bottom, textInsets.bottom)
            .padding(.leading, textInsets.left)
            .padding(.trailing, textInsets.right)
            .padding(.horizontal, editorTextHorizontalPadding)
        } else {
            ZonePlainTextViewRepresentable(
                text: zone?.text ?? "",
                font: textUIFont,
                textColor: UIColor(zone?.textColor.color ?? .primary),
                textAlignment: zone?.textAlignment.nsTextAlignment ?? .left,
                lineSpacing: editorTextLineSpacing,
                contentInset: textInsets
            )
            .padding(.horizontal, editorTextHorizontalPadding)
        }
    }

    private var shouldUseRichTextPreview: Bool {
        let text = zone?.text ?? ""
        return MathTextSanitizer.containsMath(text)
            || MathTextSanitizer.containsInlineCode(text)
            || text.contains("**")
    }

    private var highlightedBackground: some View {
        let rawText = zone?.text ?? ""
        let displayText = rawText.hasSuffix("\n") ? rawText + "\u{200B}" : (rawText.isEmpty ? "\u{200B}" : rawText)
        let attrString = highlightContext?.generateOverlay(for: displayText, font: textFont, highlightColor: ThemeManager.shared.accentColor.color) ?? AttributedString(displayText)
        return Text(attrString).multilineTextAlignment(zone?.textAlignment.alignment ?? .leading).allowsHitTesting(false)
    }

    private func fontSizeFor(_ zone: ZoneModel?) -> CGFloat {
        switch zone?.textStyle ?? .body {
        case .caption: return 16 * fontScale
        case .body: return 22 * fontScale
        case .headline: return 26 * fontScale
        case .title: return 32 * fontScale
        }
    }

    // MARK: - Text Editor Core

    @ViewBuilder
    private var textEditorCore: some View {
        let rawText = zone?.text ?? ""
        let dummyText = rawText.isEmpty ? " " : rawText
        let currentTextColor = zone?.textColor.color ?? .primary
        let currentTextAlignment = zone?.textAlignment.nsTextAlignment ?? .left
        let currentIsBold = zone?.isBold ?? false
        let currentIsItalic = zone?.isItalic ?? false
        let currentPath = path
        let zoneID = zone?.id ?? UUID()
        let currentContentType = zone?.contentType ?? .empty
        let textInsets = editorTextContentInsets

        ZStack(alignment: .topLeading) {
            ZonePlainTextViewRepresentable(
                text: dummyText,
                font: textUIFont,
                textColor: UIColor(currentTextColor),
                textAlignment: currentTextAlignment,
                lineSpacing: editorTextLineSpacing,
                contentInset: textInsets
            )
            .opacity(0)
            .frame(maxWidth: .infinity, alignment: topAlignmentFor(zone))
            .layoutPriority(1)
            .onGeometryChange(for: CGSize.self) { proxy in
                CGSize(width: ceil(proxy.size.width), height: ceil(proxy.size.height))
            } action: { size in
                updateRenderedContentHeight(size.height)
            }

            ZoneTextViewRepresentable(
                text: pureTextBinding, font: textUIFont, textColor: UIColor(currentTextColor), textAlignment: currentTextAlignment, isBold: currentIsBold, isItalic: currentIsItalic, lineSpacing: editorTextLineSpacing, contentInset: textInsets, cursorTintColor: UIColor(accent), extendsTextOnBlankTap: false, zoneID: zoneID, isFirstResponder: isFocused,
                onTextChange: { newText in
                    if currentContentType == .text || currentContentType == .empty {
                        highlightContext?.dismiss()
                        content.updateZone(at: currentPath) { z in z.text = newText; if z.contentType == .empty { z.contentType = .text } }
                    }
                },
                onCursorChange: { _, _ in },
                onFocusLineChange: { lineIndex, totalLines in
                    lineTracker.updateFocusedLine(for: zoneID, lineIndex: lineIndex, totalLines: totalLines)
                    zoneController.updateZoneHeightInfo(for: zoneID, lineCount: totalLines, focusedLineIndex: lineIndex)
                },
                onCaretAnchorChange: { anchorY in
                    postCaretScrollHint(anchorY: anchorY)
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

    private func triggerFocus() {
        if let zoneID = currentZoneID { focusManager.requestFocus(for: zoneID) }
        isFocused = true; onSelect()
    }

    private func postCaretScrollHint(anchorY: CGFloat) {
        let normalizedAnchorY = min(max(anchorY, 0.08), 0.92)

        if let lastPostedCaretAnchorY,
           abs(lastPostedCaretAnchorY - normalizedAnchorY) < 0.04 {
            return
        }

        lastPostedCaretAnchorY = normalizedAnchorY

        NotificationCenter.default.post(
            name: .zoneEditorCaretMoved,
            object: nil,
            userInfo: [
                ZoneEditorCaretScrollNotification.pathIDKey: path.id,
                ZoneEditorCaretScrollNotification.anchorYKey: normalizedAnchorY
            ]
        )
    }

    // MARK: - Debug Reporting

    private func reportDebugZoneState(zone: ZoneModel, layout: CardZoneLayoutResult) {
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
            isSelected: isSelected,
            isResizing: isResizingZone
        )
    }

    private func zoneDebugSignature(zone: ZoneModel, layout: CardZoneLayoutResult) -> String {
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

    private func resizeHandleDebugSignature(
        layout: CardZoneLayoutResult,
        hitWidth: CGFloat,
        hitHeight: CGFloat,
        glyphSize: CGFloat
    ) -> String {
        let parts: [String] = [
            String(Int(layout.blockSize.width)),
            String(Int(layout.blockSize.height)),
            String(Int(hitWidth)),
            String(Int(hitHeight)),
            String(Int(glyphSize)),
            isSelected ? "selected" : "idle"
        ]
        return parts.joined(separator: "|")
    }

    private func resizeAxisDebugName(_ axis: ZoneResizeDragAxis) -> String {
        switch axis {
        case .horizontal:
            return "horizontal"
        case .vertical:
            return "vertical"
        case .free:
            return "free"
        }
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
        let style = zone?.textStyle ?? .body; let family = zone?.fontFamily ?? .system
        let weight: Font.Weight = zone?.isBold == true ? .bold : (style == .title ? .bold : (style == .headline ? .semibold : .regular))
        let size: CGFloat; switch style { case .body: size = 22; case .title: size = 32; case .headline: size = 26; case .caption: size = 16 }
        return family.font(size: size * fontScale, weight: weight)
    }
    private var textUIFont: UIFont {
        textUIFont(for: zone)
    }

    private func textUIFont(for zone: ZoneModel?) -> UIFont {
        let style = zone?.textStyle ?? .body; let family = zone?.fontFamily ?? .system
        let weight: UIFont.Weight = zone?.isBold == true ? .bold : (style == .title ? .bold : (style == .headline ? .semibold : .regular))
        let size: CGFloat; switch style { case .body: size = 22; case .title: size = 32; case .headline: size = 26; case .caption: size = 16 }
        return family.uiFont(size: size * fontScale, weight: weight)
    }

    private var editorTextHorizontalPadding: CGFloat {
        editorTextHorizontalPadding(for: zone)
    }

    private func editorTextHorizontalPadding(for zone: ZoneModel?) -> CGFloat {
        zone?.highlightColor != HighlightColor.none ? 6 : 0
    }

    private var editorTextLineSpacing: CGFloat {
        max(floor(fontSizeFor(zone) * 0.26), 6)
    }

    private var editorTextVerticalPadding: CGFloat {
        editorTextContentInsets.top + editorTextContentInsets.bottom
    }

    private var editorTextContentInsets: UIEdgeInsets {
        UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
    }

    private var zoneCornerRadius: CGFloat {
        18
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
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: topAlignmentFor(zone))
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
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: topAlignmentFor(zone))
        }
    }

    // MARK: - Alignment Helper
    @ViewBuilder
    private var idleZoneStroke: some View {
        if !isSelected {
            RoundedRectangle(cornerRadius: zoneCornerRadius, style: .continuous)
                .stroke(Color.gray.opacity(0.18), lineWidth: 0.8)
        }
    }

    private func alignmentFor(_ zone: ZoneModel?) -> Alignment { switch zone?.textAlignment ?? .leading { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing } }
    private func topAlignmentFor(_ zone: ZoneModel?) -> Alignment { switch zone?.textAlignment ?? .leading { case .leading: return .topLeading; case .center: return .top; case .trailing: return .topTrailing } }
}

// MARK: - Zone Resize Handle

struct ZoneResizeCornerHandle: View {
    let accent: Color
    let isActive: Bool

    var body: some View {
        ZoneResizeCornerGlyph()
            .stroke(
                accent,
                style: StrokeStyle(
                    lineWidth: 3.2,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .padding(1)
            .shadow(color: accent.opacity(isActive ? 0.38 : 0.24), radius: isActive ? 4 : 2, y: 1)
    }
}

struct ZoneResizeCornerGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let radius = min(rect.width, rect.height) * 0.36

        path.move(to: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: maxX - radius, y: maxY))
        path.addQuadCurve(
            to: CGPoint(x: maxX, y: maxY - radius),
            control: CGPoint(x: maxX, y: maxY)
        )
        path.addLine(to: CGPoint(x: maxX, y: minY))

        return path
    }
}

struct ZoneResizeTouchCapture: UIViewRepresentable {
    var cornerHitSize: CGFloat = 132
    var onChanged: (CGSize) -> Void
    var onEnded: () -> Void

    func makeUIView(context: Context) -> TouchCaptureView {
        let view = TouchCaptureView()
        view.cornerHitSize = cornerHitSize
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateUIView(_ uiView: TouchCaptureView, context: Context) {
        uiView.cornerHitSize = cornerHitSize
        uiView.onChanged = onChanged
        uiView.onEnded = onEnded
    }

    final class ResizePanGestureRecognizer: UIPanGestureRecognizer {
        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }

    final class TouchCaptureView: UIView, UIGestureRecognizerDelegate {
        var cornerHitSize: CGFloat = 132
        var onChanged: ((CGSize) -> Void)?
        var onEnded: (() -> Void)?
        private var lastDeliveredTranslation: CGSize = .zero
        private var lastDeliveryTime: TimeInterval = 0
        private var startWindowLocation: CGPoint?
        private lazy var panGesture: ResizePanGestureRecognizer = {
            let recognizer = ResizePanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.minimumNumberOfTouches = 1
            recognizer.maximumNumberOfTouches = 1
            recognizer.cancelsTouchesInView = true
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            recognizer.name = "QuizFlash.ZoneResizeCornerPan"
            return recognizer
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = false
            backgroundColor = .clear
            isUserInteractionEnabled = true
            isMultipleTouchEnabled = false
            isExclusiveTouch = true
            layer.zPosition = 10_000
            addGestureRecognizer(panGesture)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            let hitSize = max(cornerHitSize, 44)
            let hitRect = CGRect(
                x: bounds.maxX - hitSize,
                y: bounds.maxY - hitSize,
                width: hitSize,
                height: hitSize
            )
            return hitRect.contains(point)
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            self.point(inside: point, with: event) ? self : nil
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let location = recognizer.location(in: self)
            let windowLocation = recognizer.location(in: nil)

            switch recognizer.state {
            case .began:
                startWindowLocation = windowLocation
                lastDeliveredTranslation = .zero
                lastDeliveryTime = 0
                reportTouch(phase: "began", location: location, translation: .zero)
                onChanged?(.zero)
            case .changed:
                let translation = stableTranslation(from: windowLocation)
                if shouldDeliver(translation: translation) {
                    lastDeliveredTranslation = translation
                    lastDeliveryTime = Date.timeIntervalSinceReferenceDate
                    reportTouch(phase: "moved", location: location, translation: translation)
                    onChanged?(translation)
                }
            case .ended:
                finish(phase: "ended", location: location, translation: stableTranslation(from: windowLocation))
            case .cancelled:
                finish(phase: "cancelled", location: location, translation: stableTranslation(from: windowLocation))
            case .failed:
                finish(phase: "failed", location: location, translation: stableTranslation(from: windowLocation))
            default:
                break
            }
        }

        private func stableTranslation(from windowLocation: CGPoint) -> CGSize {
            guard let startWindowLocation else { return .zero }
            return CGSize(
                width: windowLocation.x - startWindowLocation.x,
                height: windowLocation.y - startWindowLocation.y
            )
        }

        private func shouldDeliver(translation: CGSize) -> Bool {
            let dx = translation.width - lastDeliveredTranslation.width
            let dy = translation.height - lastDeliveredTranslation.height
            if hypot(dx, dy) >= 1.5 { return true }

            let elapsed = Date.timeIntervalSinceReferenceDate - lastDeliveryTime
            return elapsed >= 1.0 / 30.0
        }

        private func finish(phase: String, location: CGPoint, translation: CGSize) {
            if translation != lastDeliveredTranslation {
                onChanged?(translation)
            }
            reportTouch(phase: phase, location: location, translation: translation)
            lastDeliveredTranslation = .zero
            lastDeliveryTime = 0
            startWindowLocation = nil
            onEnded?()
        }

        private func reportTouch(phase: String, location: CGPoint, translation: CGSize) {
            Task { @MainActor in
                ZoneEditorDebugStore.shared.recordResizeTouch(
                    phase: phase,
                    x: location.x,
                    y: location.y,
                    dx: translation.width,
                    dy: translation.height
                )
            }
        }
    }
}

struct CardFaceView: View {
    let zone: ZoneModel
    let fontScale: CGFloat
    let displayTextAlignment: TextBlockAlignment?
    var onTap: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    init(
        zone: ZoneModel,
        fontScale: CGFloat = 1.0,
        displayTextAlignment: TextBlockAlignment? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.zone = zone
        self.fontScale = fontScale
        self.displayTextAlignment = displayTextAlignment
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
                let resolvedTextAlignment = displayTextAlignment ?? zone.textAlignment
                // Route to CodeSnippetView for fenced code blocks.
                if zone.contentType == .code || previewText.hasPrefix("```") {
                    CodeSnippetView(rawText: previewText)
                        .padding(.vertical, 4)
                }
                else {
                    HStack(alignment: .top, spacing: 8) {
                        if zone.hasBullet {
                            Circle()
                                .fill(zone.textColor.color)
                                .frame(width: 6, height: 6)
                                .padding(.top, 8)
                        }
                        MixedMathTextView(
                            text: previewText,
                            fontSize: fontSizeFor(zone),
                            textColor: zone.textColor.color,
                            alignment: resolvedTextAlignment.horizontalAlignment,
                            isBold: zone.isBold,
                            isItalic: zone.isItalic,
                            isInteractive: false,
                            allowsReadOnlyOverflowScrolling: true,
                            onTap: onTap
                        )
                            .padding(.vertical, 4)
                            .padding(.horizontal, zone.highlightColor != HighlightColor.none ? 6 : 0)
                            .background(
                            zone.highlightColor.color.map { color in
                                RoundedRectangle(cornerRadius: 4).fill(color)
                            }
                               
                        )
                    }
                        .frame(maxWidth: .infinity, alignment: alignmentFor(resolvedTextAlignment))
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

    @ViewBuilder
    private var containerPreview: some View {
        let children = zone.children ?? []
        if zone.direction == .horizontal {
            HStack(alignment: .top, spacing: 12) {
                ForEach(children) { child in
                    CardFaceView(
                        zone: child,
                        fontScale: fontScale,
                        displayTextAlignment: displayTextAlignment,
                        onTap: onTap
                    )
                }
            }
        } else {
            VStack(alignment: displayTextAlignment?.horizontalAlignment ?? .leading, spacing: 12) {
                ForEach(children) { child in
                    CardFaceView(
                        zone: child,
                        fontScale: fontScale,
                        displayTextAlignment: displayTextAlignment,
                        onTap: onTap
                    )
                }
            }
        }
    }

    private func alignmentFor(_ textAlignment: TextBlockAlignment) -> Alignment {
        switch textAlignment { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }

    private func previewFont(for zone: ZoneModel) -> Font {
        let style = zone.textStyle; let family = zone.fontFamily
        let weight: Font.Weight = zone.isBold ? .bold : (style == .title ? .bold : (style == .headline ? .semibold : .regular))
        let size: CGFloat
        switch style { case .body: size = 22; case .title: size = 32; case .headline: size = 26; case .caption: size = 16 }
        return family.font(size: size * fontScale, weight: weight)
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
                HStack(spacing: 0) {
                    if alignment == .trailing || alignment == .center { Spacer(minLength: 0) }
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: UIScreen.main.bounds.width * scale * 0.85)
                        .background { if isSketch { RoundedRectangle(cornerRadius: cornerRadius).fill(colorScheme == .dark ? Color.black : Color.white) } }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    if alignment == .leading || alignment == .center { Spacer(minLength: 0) }
                }
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

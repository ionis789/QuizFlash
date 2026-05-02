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
/// during a drag-to-add gesture. Rendered as a visual overlay only — never
/// mutates the zone data model.
struct FakeGhostBlockView: View {
    let isHorizontal: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.yellow.opacity(0.15))
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.yellow.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [6]))
        }
            .frame(minWidth: isHorizontal ? 40 : 0, maxWidth: .infinity)
            .frame(minHeight: isHorizontal ? 0 : 38, maxHeight: isHorizontal ? .infinity : 38)
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
/// - Container zones layout their children using `HStack` (horizontal) or
///   `VStack` (vertical) and inject ghost block overlays based on `previewDirection`.
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
        let isHorizontal = zone.direction == .horizontal

        if isHorizontal {
            let spacingTotal = CGFloat(max(children.count - 1, 0)) * UIConstants.Spacing.small
            let childWidth = max((availableWidth - spacingTotal) / CGFloat(max(children.count, 1)), 1)

            HStack(alignment: .center, spacing: 8) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, _ in
                    let childPath = path.appending(index)
                    let isChildSelected = (selectedPath == childPath)

                    if isChildSelected, previewDirection.wrappedValue == .left {
                        FakeGhostBlockView(isHorizontal: true)
                            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                    }

                    ZoneEditorView(
                        content: content,
                        path: childPath,
                        selectedPath: $selectedPath,
                        highlightContext: highlightContext,
                        fontScale: fontScale,
                        availableWidth: childWidth,
                        previewDirection: maskedPreviewDirection(for: isChildSelected, isHorizontal: true)
                    )
                        .frame(width: childWidth, alignment: .topLeading)

                    if isChildSelected, previewDirection.wrappedValue == .right {
                        FakeGhostBlockView(isHorizontal: true)
                            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                    }
                }
            }
                .frame(width: availableWidth, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 8) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, _ in
                    let childPath = path.appending(index)
                    let isChildSelected = (selectedPath == childPath)

                    if isChildSelected, previewDirection.wrappedValue == .up {
                        FakeGhostBlockView(isHorizontal: false)
                            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                    }

                    ZoneEditorView(
                        content: content,
                        path: childPath,
                        selectedPath: $selectedPath,
                        highlightContext: highlightContext,
                        fontScale: fontScale,
                        availableWidth: availableWidth,
                        previewDirection: maskedPreviewDirection(for: isChildSelected, isHorizontal: false)
                    )
                    .frame(width: availableWidth, alignment: .topLeading)

                    if isChildSelected, previewDirection.wrappedValue == .down {
                        FakeGhostBlockView(isHorizontal: false)
                            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                    }
                }
            }
                .frame(width: availableWidth, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func maskedPreviewDirection(for isChildSelected: Bool, isHorizontal: Bool) -> Binding<AddDirection?> {
        Binding<AddDirection?>(
            get: {
                guard isChildSelected, let direction = previewDirection.wrappedValue else {
                    return previewDirection.wrappedValue
                }
                if isHorizontal && (direction == .left || direction == .right) { return nil }
                if !isHorizontal && (direction == .up || direction == .down) { return nil }

                return direction
            },
            set: { previewDirection.wrappedValue = $0 }
        )
    }

    private func selectZone() {
        selectedPath = path
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Zone Content View (Leaf)

/// Renders the content of a single leaf zone: text editor, image, or sketch.
///
/// Handles:
/// - Focus negotiation with `ZoneFocusManager` and `ZoneController`
/// - Switching between `ZoneTextViewRepresentable` (edit mode) and
///   `MixedMathTextView` / `CodeSnippetView` (preview mode)
/// - Image long-press → full-screen `ImageCropEditorView`
/// - Ghost block overlays for all four add-directions
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
            let layout = CardZoneLayoutEngine.leafLayout(
                for: zone,
                spec: CardZoneLayoutSpec(
                    availableWidth: availableWidth,
                    fontScale: fontScale,
                    minimumAutoWidth: isSelected || isFocused ? 156 : 1
                ),
                measuredContentSize: renderedContentSize
            )

            ZStack(alignment: .topLeading) {
                blockFrameReporter(layout: layout, zoneID: zone.id)

                if isSelected {
                    selectedOutline(layout: layout)
                }

                contentView
                    .frame(
                        width: layout.contentLayoutWidth,
                        height: zone.sizeMode == .fixed ? layout.blockSize.height : nil,
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

                if isSelected {
                    resizeHandle(layout: layout)
                }
            }
            .frame(width: availableWidth, height: layout.blockSize.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    onSelect()

                    let type = zone.contentType

                    if type == .text || type == .empty {
                        if !isFocused {
                            focusManager.requestFocus(for: zone.id)
                        }
                    } else {
                        focusManager.updateFocusedZone(zone.id)
                        zoneController.updateFocusedZone(zone.id)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            )
            .onAppear {
                syncFocusState(with: focusManager.focusedZoneID)
            }
            .onChange(of: isFocused) { _, focused in
                handleFocusChange(focused)
            }
            .onChange(of: focusManager.focusedZoneID) { _, focusedID in
                syncFocusState(with: focusedID)
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
        RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
            .stroke(
                accent.opacity(0.95),
                style: StrokeStyle(lineWidth: 1.6, dash: [5, 4])
            )
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

    private func resizeHandle(layout: CardZoneLayoutResult) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ZoneResizeHandleGestureCapture(
                onChanged: { translation in
                    handleResizeChange(
                        translation: translation,
                        startSize: layout.blockSize
                    )
                },
                onEnded: {
                    resizeStartSize = nil
                    resizeLastCommittedSize = nil
                }
            )
            .frame(width: 64, height: 64)

            ZoneResizeCornerHandle(accent: accent)
                .frame(width: 30, height: 30)
                .padding(.trailing, 3)
                .padding(.bottom, 3)
                .allowsHitTesting(false)
        }
        .frame(width: 64, height: 64, alignment: .bottomTrailing)
        .offset(
            x: max(layout.leadingInset + layout.blockSize.width - 64, 0),
            y: max(layout.blockSize.height - 64, 0)
        )
        .zIndex(40)
        .accessibilityLabel(localized("Resize Zone"))
    }

    private func handleResizeChange(translation: CGSize, startSize: CGSize) {
        if resizeStartSize == nil {
            resizeStartSize = startSize
            resizeLastCommittedSize = startSize
            focusManager.forceReleaseKeyboard()
        }

        let baseSize = resizeStartSize ?? startSize
        let maxWidth = max(availableWidth, 1)
        let nextSize = CGSize(
            width: min(
                max(ceil(baseSize.width + translation.width), minimumResizableWidth),
                maxWidth
            ),
            height: max(ceil(baseSize.height + translation.height), minimumResizableHeight)
        )

        if let last = resizeLastCommittedSize,
           abs(last.width - nextSize.width) < 2,
           abs(last.height - nextSize.height) < 2 {
            return
        }

        resizeLastCommittedSize = nextSize
        content.updateZone(at: path) { zone in
            zone.sizeMode = .fixed
            zone.fixedWidth = nextSize.width
            zone.fixedHeight = nextSize.height
        }
    }

    private var minimumResizableWidth: CGFloat {
        min(max(72, availableWidth * 0.18), availableWidth)
    }

    private var minimumResizableHeight: CGFloat {
        max(36, fontSizeFor(zone) + 12)
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

    @ViewBuilder
    private var contentView: some View {
        switch zone?.contentType ?? .empty {
        case .empty, .text, .code: textViewWithGhostOverlay
        case .image: imageView
        case .sketch: sketchView
        }
    }

    // MARK: - textViewWithGhostOverlay

    @ViewBuilder
    private var textViewWithGhostOverlay: some View {
        HStack(alignment: .top, spacing: 8) {
            if zone?.hasBullet == true {
                Circle().fill(zone?.textColor.color ?? .primary).frame(width: 6, height: 6).padding(.top, 10)
            }

            VStack(spacing: 8) {
                if isSelected, previewDirection == .up { FakeGhostBlockView(isHorizontal: false).transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity)) }

                HStack(spacing: 8) {
                    if isSelected, previewDirection == .left { FakeGhostBlockView(isHorizontal: true).transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity)) }

                    if isFocused || ((zone?.text.isEmpty ?? true) && isSelected) {
                        textEditorCore
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                    } else if zone?.text.isEmpty ?? true {
                        emptyZonePreview
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                            .onTapGesture { triggerFocus() }
                    } else {
                        renderedTextPreview
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: alignmentFor(zone))
                            .onTapGesture { triggerFocus() }
                    }

                    if isSelected, previewDirection == .right { FakeGhostBlockView(isHorizontal: true).transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity)) }
                }

                if isSelected, previewDirection == .down { FakeGhostBlockView(isHorizontal: false).transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity)) }
            }
        }
    }

    private var emptyZonePreview: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.gray.opacity(0.05))
            .overlay(idleZoneStroke)
            .frame(height: minimumResizableHeight)
            .contentShape(Rectangle())
    }

    private var renderedTextPreview: some View {
        Group {
            if zone?.contentType == .code || zone?.text.hasPrefix("```") == true {
                CodeSnippetView(rawText: zone?.text ?? "")
                    .padding(.vertical, 4)
            } else {
                MixedMathTextView(
                    text: zone?.text ?? "",
                    fontSize: fontSizeFor(zone),
                    textColor: zone?.textColor.color ?? .primary,
                    alignment: alignmentFor(zone).horizontalAlignment,
                    isBold: zone?.isBold ?? false,
                    isItalic: zone?.isItalic ?? false
                )
                    .padding(.vertical, 4)
                    .padding(.horizontal, editorTextHorizontalPadding)
                    .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.05))
                            .overlay(idleZoneStroke)
                        if let highlight = zone?.highlightColor.color {
                            RoundedRectangle(cornerRadius: 4).fill(highlight)
                        }
                    }
                )
                    .contentShape(Rectangle())
            }
        }
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
        let dummyText = rawText.isEmpty ? " " : rawText + " "
        let currentTextColor = zone?.textColor.color ?? .primary
        let currentTextAlignment = zone?.textAlignment.nsTextAlignment ?? .left
        let currentIsBold = zone?.isBold ?? false
        let currentIsItalic = zone?.isItalic ?? false
        let currentPath = path
        let zoneID = zone?.id ?? UUID()
        let currentContentType = zone?.contentType ?? .empty

        ZStack(alignment: .topLeading) {
            Text(dummyText).font(textFont).lineLimit(nil).fixedSize(horizontal: false, vertical: true).opacity(0).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: alignmentFor(zone)).layoutPriority(1)

            ZoneTextViewRepresentable(
                text: pureTextBinding, font: textUIFont, textColor: UIColor(currentTextColor), textAlignment: currentTextAlignment, isBold: currentIsBold, isItalic: currentIsItalic, lineSpacing: editorTextLineSpacing, zoneID: zoneID, isFirstResponder: isFocused,
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
                onCommit: { },
                onFocusChange: { focused in if isFocused != focused { isFocused = focused } }
            )
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            if shouldShowHighlight { highlightedBackground }
        }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, editorTextHorizontalPadding)
            .background(
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05))
                    .overlay(idleZoneStroke)
                if let highlight = zone?.highlightColor.color { RoundedRectangle(cornerRadius: 4).fill(highlight) }
            }
        ).contentShape(Rectangle())
    }

    // MARK: - Focus Handling

    private func handleFocusChange(_ focused: Bool) {
        if focused {
            highlightContext?.dismiss()
            if !isSelected { onSelect() }
            if let zoneID = currentZoneID { focusManager.updateFocusedZone(zoneID); zoneController.updateFocusedZone(zoneID) }
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
        let style = zone?.textStyle ?? .body; let family = zone?.fontFamily ?? .system
        let weight: UIFont.Weight = zone?.isBold == true ? .bold : (style == .title ? .bold : (style == .headline ? .semibold : .regular))
        let size: CGFloat; switch style { case .body: size = 22; case .title: size = 32; case .headline: size = 26; case .caption: size = 16 }
        return family.uiFont(size: size * fontScale, weight: weight)
    }

    private var editorTextHorizontalPadding: CGFloat {
        zone?.highlightColor != HighlightColor.none ? 6 : 0
    }

    private var editorTextLineSpacing: CGFloat {
        max(floor(fontSizeFor(zone) * 0.26), 6)
    }

    // MARK: - Image View
    @ViewBuilder
    private var imageView: some View {
        if let data = zone?.imageData, let img = UIImage(data: data) {
            let scale = zone?.imageScale ?? 1.0
            let align = zone?.textAlignment ?? .leading

            HStack(spacing: 0) {
                if align == .trailing || align == .center { Spacer(minLength: 0) }

                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: UIScreen.main.bounds.width * scale * 0.8)
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
                }

                if align == .leading || align == .center { Spacer(minLength: 0) }
            }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05))
                        .overlay(idleZoneStroke)
                }
            )
        }
    }

    // MARK: - Sketch View
    @ViewBuilder
    private var sketchView: some View {
        if let data = zone?.imageData, let img = UIImage(data: data) {
            let scale = zone?.imageScale ?? 1.0; let align = zone?.textAlignment ?? .leading
            HStack(spacing: 0) {
                if align == .trailing || align == .center { Spacer(minLength: 0) }
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: UIScreen.main.bounds.width * scale * 0.8).background(colorScheme == .dark ? Color.black : Color.white).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if align == .leading || align == .center { Spacer(minLength: 0) }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(ZStack { RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)).overlay(idleZoneStroke) })
        }
    }

    // MARK: - Alignment Helper
    @ViewBuilder
    private var idleZoneStroke: some View {
        if !isSelected {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.18), lineWidth: 0.8)
        }
    }

    private func alignmentFor(_ zone: ZoneModel?) -> Alignment { switch zone?.textAlignment ?? .leading { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing } }
}

// MARK: - Zone Resize Handle

struct ZoneResizeCornerHandle: View {
    let accent: Color

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Capsule()
                .fill(accent)
                .frame(width: 24, height: 5)
                .padding(.bottom, 3)
                .padding(.trailing, 3)

            Capsule()
                .fill(accent)
                .frame(width: 5, height: 24)
                .padding(.bottom, 3)
                .padding(.trailing, 3)
        }
        .shadow(color: accent.opacity(0.45), radius: 6, y: 2)
    }
}

// MARK: - Zone Resize Gesture Capture

struct ZoneResizeHandleGestureCapture: UIViewRepresentable {
    var onChanged: (CGSize) -> Void
    var onEnded: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let recognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        recognizer.cancelsTouchesInView = true
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        view.addGestureRecognizer(recognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    final class Coordinator: NSObject {
        var onChanged: (CGSize) -> Void
        var onEnded: () -> Void

        init(
            onChanged: @escaping (CGSize) -> Void,
            onEnded: @escaping () -> Void
        ) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: recognizer.view)
            switch recognizer.state {
            case .began, .changed:
                onChanged(
                    CGSize(
                        width: translation.x,
                        height: translation.y
                    )
                )
            case .ended, .cancelled, .failed:
                onEnded()
            default:
                break
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

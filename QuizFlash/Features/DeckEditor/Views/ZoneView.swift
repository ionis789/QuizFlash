//
//  ZoneView.swift
//  QuizFlash
//
//  Recursive zone editor and read-only card face preview.
//  All zone mutations go through `ZoneCardContent`; views are read-only consumers.
//

import SwiftUI
import PhotosUI

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
    var previewDirection: Binding<AddDirection?>

    private var zone: ZoneModel? { content.zone(at: path) }
    private var isSelected: Bool { selectedPath == path }

    init(
        content: ZoneCardContent,
        path: ZonePath,
        selectedPath: Binding<ZonePath?>,
        highlightContext: HighlightContext?,
        fontScale: CGFloat = 1.0,
        previewDirection: Binding<AddDirection?> = .constant(nil)
    ) {
        self.content = content
        self.path = path
        self._selectedPath = selectedPath
        self.highlightContext = highlightContext
        self.fontScale = fontScale
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
                        previewDirection: maskedPreviewDirection(for: isChildSelected, isHorizontal: true)
                    )
                        .frame(maxHeight: .infinity)

                    if isChildSelected, previewDirection.wrappedValue == .right {
                        FakeGhostBlockView(isHorizontal: true)
                            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                    }
                }
            }
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
                        previewDirection: maskedPreviewDirection(for: isChildSelected, isHorizontal: false)
                    )

                    if isChildSelected, previewDirection.wrappedValue == .down {
                        FakeGhostBlockView(isHorizontal: false)
                            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                    }
                }
            }
                .frame(maxHeight: .infinity, alignment: .top)
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
    var onSelect: () -> Void
    @Binding var previewDirection: AddDirection?

    @State private var isFocused: Bool = false
    @State private var isCroppingImage: Bool = false
    @State private var isPressingImage: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    private var focusManager = ZoneFocusManager.shared
    private var zoneController = ZoneController.shared
    private var lineTracker = ZoneLineTracker.shared

    private var zone: ZoneModel? { content.zone(at: path) }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var currentZoneID: UUID? { zone?.id }

    init(
        content: ZoneCardContent,
        path: ZonePath,
        isSelected: Bool,
        highlightContext: HighlightContext? = nil,
        fontScale: CGFloat = 1.0,
        onSelect: @escaping () -> Void,
        previewDirection: Binding<AddDirection?> = .constant(nil)
    ) {
        self.content = content
        self.path = path
        self.isSelected = isSelected
        self.highlightContext = highlightContext
        self.fontScale = fontScale
        self.onSelect = onSelect
        self._previewDirection = previewDirection
    }

    private var shouldShowHighlight: Bool {
        guard let highlightContext = highlightContext, let zone = zone else { return false }
        return highlightContext.shouldHighlight(text: zone.text)
    }

    var body: some View {
        contentView
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignmentFor(zone))
            .contentShape(Rectangle())
            .simultaneousGesture(
            TapGesture().onEnded {
                onSelect()

                let type = zone?.contentType ?? .empty

                if type == .text || type == .empty {
                    if !isFocused {
                        if let id = currentZoneID { focusManager.requestFocus(for: id) }
                    }
                } else {
                    if let id = currentZoneID {
                        focusManager.updateFocusedZone(id)
                        zoneController.updateFocusedZone(id)
                    }
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        )
            .onChange(of: isFocused) { _, focused in
            handleFocusChange(focused)
        }
            .onChange(of: focusManager.pendingFocusZoneID) { _, pendingID in
            if pendingID == currentZoneID {
                if zone?.contentType == .text || zone?.contentType == .empty {
                    isFocused = true
                }
                focusManager.clearPendingFocus()
            }
        }
            .fullScreenCover(isPresented: $isCroppingImage) {
            if let data = zone?.imageData, let img = UIImage(data: data) {
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

                    if isFocused || (zone?.text.isEmpty ?? true) {
                        textEditorCore
                            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        renderedTextPreview
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: alignmentFor(zone))
                            .onTapGesture { triggerFocus() }
                    }

                    if isSelected, previewDirection == .right { FakeGhostBlockView(isHorizontal: true).transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity)) }
                }.frame(maxHeight: .infinity)

                if isSelected, previewDirection == .down { FakeGhostBlockView(isHorizontal: false).transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity)) }
            }.frame(maxHeight: .infinity)
        }.frame(maxHeight: .infinity)
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
                    .padding(.leading, zone?.highlightColor != HighlightColor.none ? 6 : 8)
                    .padding(.trailing, 0)
                    .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.05))
                            .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                isSelected ? accent : Color.gray.opacity(0.3),
                                style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: [4])
                            )
                        )
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
                text: pureTextBinding, font: textUIFont, textColor: UIColor(currentTextColor), textAlignment: currentTextAlignment, isBold: currentIsBold, isItalic: currentIsItalic, zoneID: zoneID, isFirstResponder: isFocused,
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
                .padding(.vertical, 4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if shouldShowHighlight { highlightedBackground }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.leading, zone?.highlightColor != HighlightColor.none ? 6 : 8).padding(.trailing, 0)
            .background(
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? accent : Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: [4])))
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
                .frame(maxHeight: .infinity, alignment: .top)
                .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05))
                        .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? accent : Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: [4]))
                    )
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
            }.padding(.vertical, 8).frame(maxHeight: .infinity, alignment: .top).background(ZStack { RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? accent : Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: [4]))) })
        }
    }

    // MARK: - Alignment Helper
    private func alignmentFor(_ zone: ZoneModel?) -> Alignment { switch zone?.textAlignment ?? .leading { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing } }
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

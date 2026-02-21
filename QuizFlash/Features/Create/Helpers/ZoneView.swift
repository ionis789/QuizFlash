//
//  ZoneView.swift
//  QuizFlash
//
//  Zone editor views with PURE VISUAL ghost previews using permanent structural wrappers.
//  UITextView identity is preserved - no data model mutation during drag.
//

import SwiftUI
import PhotosUI

// MARK: - Fake Ghost Block View (Visual Only - Seamless Dimension Match)

struct FakeGhostBlockView: View {
    let isHorizontal: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.yellow.opacity(0.15))
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.yellow.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [6]))
        }
        // Match standard UITextView line height + padding seamlessly
        .frame(minWidth: isHorizontal ? 40 : 0, maxWidth: .infinity)
            .frame(minHeight: isHorizontal ? 0 : 38, maxHeight: isHorizontal ? .infinity : 38)
    }
}

// MARK: - Zone Editor View (Recursive)

struct ZoneEditorView: View {
    @Bindable var content: ZoneCardContent
    let path: ZonePath
    @Binding var selectedPath: ZonePath?
    var highlightContext: HighlightContext?
    var previewDirection: Binding<AddDirection?>

    private var zone: ZoneModel? { content.zone(at: path) }
    private var isSelected: Bool { selectedPath == path }

    init(
        content: ZoneCardContent,
        path: ZonePath,
        selectedPath: Binding<ZonePath?>,
        highlightContext: HighlightContext?,
        previewDirection: Binding<AddDirection?> = .constant(nil)
    ) {
        self.content = content
        self.path = path
        self._selectedPath = selectedPath
        self.highlightContext = highlightContext
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
            onSelect: { selectZone() },
            previewDirection: previewDirection
        )
            .id(path.id)
    }

    // MARK: - Container Zone View (GLOBAL GHOST INJECTION AS TRUE SIBLING)

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

    // MARK: - Masked Preview Direction (Prevents Double Ghosts)

    private func maskedPreviewDirection(for isChildSelected: Bool, isHorizontal: Bool) -> Binding<AddDirection?> {
        Binding<AddDirection?>(
            get: {
                guard isChildSelected, let direction = previewDirection.wrappedValue else {
                    return previewDirection.wrappedValue
                }
                // Hide duplicate directions handled by parent containers
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




// MARK: - Zone Content View (Leaf)

struct ZoneContentView: View {
    @Bindable var content: ZoneCardContent
    let path: ZonePath
    let isSelected: Bool
    var highlightContext: HighlightContext?
    var onSelect: () -> Void
    @Binding var previewDirection: AddDirection?

    @State private var isFocused: Bool = false
    @State private var isCroppingImage: Bool = false
    @State private var isPressingImage: Bool = false // NEW: Tracks the active touch down state

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
        onSelect: @escaping () -> Void,
        previewDirection: Binding<AddDirection?> = .constant(nil)
    ) {
        self.content = content
        self.path = path
        self.isSelected = isSelected
        self.highlightContext = highlightContext
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
            .contentShape(Rectangle()) // Capture tap on entire zone area
        .simultaneousGesture(
            TapGesture().onEnded {
                onSelect()

                // Check is its a image or sketch so i will remove focus from old zone
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
        // NEW: Attach the Crop Editor
        .fullScreenCover(isPresented: $isCroppingImage) {
            if let data = zone?.imageData, let img = UIImage(data: data) {
                ImageCropEditorView(image: img) { croppedImage in
                    // Convert back to Data and save to Model
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
        case .empty, .text: textViewWithGhostOverlay
        case .image: imageView
        case .sketch: sketchView
        }
    }

    // MARK: - Text View cu Ghost Overlay
    // ... (Keep existing textViewWithGhostOverlay implementation exactly as it was) ...
    @ViewBuilder
    private var textViewWithGhostOverlay: some View {
        HStack(alignment: .top, spacing: 8) { // Am schimbat în .top ca să se alinieze bine la texte lungi
            if zone?.hasBullet == true {
                Circle().fill(zone?.textColor.color ?? .primary).frame(width: 6, height: 6).padding(.top, 10)
            }

            VStack(spacing: 8) {
                if isSelected, previewDirection == .up { FakeGhostBlockView(isHorizontal: false).transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity)) }

                HStack(spacing: 8) {
                    if isSelected, previewDirection == .left { FakeGhostBlockView(isHorizontal: true).transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity)) }

                    // SWAP-UL INTELIGENT:
                    if isFocused || (zone?.text.isEmpty ?? true) {
                        // Modul EDITARE (Apare cursorul, vezi textul brut)
                        textEditorCore
                            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Modul CITIRE (Arată LaTeX frumos, perfect formatat)
                        renderedTextPreview
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: alignmentFor(zone))
                            .onTapGesture {
                            triggerFocus() // Treci în modul editare la tap
                        }
                    }

                    if isSelected, previewDirection == .right { FakeGhostBlockView(isHorizontal: true).transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity)) }
                }.frame(maxHeight: .infinity)

                if isSelected, previewDirection == .down { FakeGhostBlockView(isHorizontal: false).transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity)) }
            }.frame(maxHeight: .infinity)
        }.frame(maxHeight: .infinity)
    }

    // NOU: Preview-ul vizual impecabil când zona nu e selectată
    private var renderedTextPreview: some View {
        Group {
            // ── CODE BLOCK ────────────────────────────────────────────────────
            if let z = zone, CodeZoneHelper.isCodeZone(z) {
                CodeBlockPreviewView(zoneText: z.text, showCopyButton: true)
            }
            // ── TEXT / MATH ───────────────────────────────────────────────────
                else {
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

    // MARK: - Highlight Overlay
    // ... (Keep existing highlightedBackground exactly as it was) ...
    private var highlightedBackground: some View {
        let rawText = zone?.text ?? ""
        let displayText = rawText.hasSuffix("\n") ? rawText + "\u{200B}" : (rawText.isEmpty ? "\u{200B}" : rawText)
        let attrString = highlightContext?.generateOverlay(for: displayText, font: textFont, highlightColor: ThemeManager.shared.accentColor.color) ?? AttributedString(displayText)
        return Text(attrString).multilineTextAlignment(zone?.textAlignment.alignment ?? .leading).allowsHitTesting(false)
    }

    private func fontSizeFor(_ zone: ZoneModel?) -> CGFloat {
        switch zone?.textStyle ?? .body {
        case .caption: return 14
        case .body: return 18
        case .headline: return 22
        case .title: return 28
        }
    }

    // MARK: - Text Editor Core
    // ... (Keep existing textEditorCore exactly as it was) ...
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
    // ... (Keep existing Focus logic exactly as it was) ...
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
    private var pureTextBinding: Binding<String> {
        Binding(get: {
            let rawText = zone?.text ?? ""
            let t = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

            // Auto-curățăm textul când intră în modul de editare
            if t.hasPrefix("$") && t.hasSuffix("$") && !t.hasPrefix("$$") {
                let inner = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                if inner.contains("$") || inner.contains(" ") {
                    return inner // Întoarce textul curat
                }
            }
            return rawText
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
        let size: CGFloat; switch style { case .body: size = 18; case .title: size = 28; case .headline: size = 22; case .caption: size = 14 }
        return family.font(size: size, weight: weight)
    }
    private var textUIFont: UIFont {
        let style = zone?.textStyle ?? .body; let family = zone?.fontFamily ?? .system
        let weight: UIFont.Weight = zone?.isBold == true ? .bold : (style == .title ? .bold : (style == .headline ? .semibold : .regular))
        let size: CGFloat; switch style { case .body: size = 18; case .title: size = 28; case .headline: size = 22; case .caption: size = 14 }
        return family.uiFont(size: size, weight: weight)
    }

    // MARK: - Image View (UPDATED)
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
                    // 1. Visual Feedback Modifiers
                    .scaleEffect(isPressingImage ? 0.95 : 1.0)
                        .opacity(isPressingImage ? 0.85 : 1.0)
                        .shadow(color: .black.opacity(isPressingImage ? 0.0 : 0.08), radius: 4, y: 2)
                        .contentShape(Rectangle())
                    // 2. Modern iOS 17 Long Press Gesture tracking
                    .onLongPressGesture(
                        minimumDuration: 0.5,
                        perform: {
                            // 3. Triggers when the 0.5s duration is met
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            isCroppingImage = true
                        },
                        onPressingChanged: { isPressing in
                            // 4. Triggers immediately on touch down and touch up/cancel
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
    // ... (Keep existing sketchView exactly as it was) ...
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

    // MARK: - Delete Button & Alignment Helper
    private var deleteButton: some View { Button { content.deleteZone(at: path) } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white, .red.opacity(0.8)) }.padding(8) }
    private func alignmentFor(_ zone: ZoneModel?) -> Alignment { switch zone?.textAlignment ?? .leading { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing } }
}



struct ZonePreviewView: View {
    let zone: ZoneModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if zone.isLeaf { leafPreview } else { containerPreview }
    }

    @ViewBuilder
    private var leafPreview: some View {
        switch zone.contentType {
        case .empty:
            Color.clear.frame(height: 28).padding(.vertical, 4)
        case .text:
            if !zone.text.isEmpty {
                // ── CODE BLOCK ──────────────────────────────────────────────────
                if CodeZoneHelper.isCodeZone(zone) {
                    CodeBlockPreviewView(zoneText: zone.text, showCopyButton: true)
                        .padding(.vertical, 4)
                }
                // ── TEXT / MATH ─────────────────────────────────────────────────
                    else {
                    HStack(alignment: .top, spacing: 8) {
                        if zone.hasBullet {
                            Circle()
                                .fill(zone.textColor.color)
                                .frame(width: 6, height: 6)
                                .padding(.top, 8)
                        }
                        MixedMathTextView(
                            text: zone.text,
                            fontSize: fontSizeFor(zone),
                            textColor: zone.textColor.color,
                            alignment: zone.textAlignment.horizontalAlignment,
                            isBold: zone.isBold,
                            isItalic: zone.isItalic
                        )
                            .padding(.vertical, 4)
                            .padding(.horizontal, zone.highlightColor != HighlightColor.none ? 6 : 0)
                            .background(
                            zone.highlightColor.color.map { color in
                                RoundedRectangle(cornerRadius: 4).fill(color)
                            }
                        )
                    }
                        .frame(maxWidth: .infinity, alignment: alignmentFor(zone))
                }
            }
        case .image:
            if let data = zone.imageData { CachedImageView(data: data, scale: zone.imageScale, alignment: zone.textAlignment, cornerRadius: 10) }
        case .sketch:
            if let data = zone.imageData { CachedImageView(data: data, scale: zone.imageScale, alignment: zone.textAlignment, cornerRadius: 10, isSketch: true) }
        }
    }
    private func fontSizeFor(_ zone: ZoneModel) -> CGFloat {
        switch zone.textStyle {
        case .caption: return 14
        case .body: return 18
        case .headline: return 22
        case .title: return 28
        }
    }

    @ViewBuilder
    private var containerPreview: some View {
        let children = zone.children ?? []
        if zone.direction == .horizontal {
            HStack(alignment: .top, spacing: 12) { ForEach(children) { child in ZonePreviewView(zone: child) } }
        } else {
            VStack(alignment: .leading, spacing: 12) { ForEach(children) { child in ZonePreviewView(zone: child) } }
        }
    }

    private func alignmentFor(_ zone: ZoneModel) -> Alignment {
        switch zone.textAlignment { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }

    private func previewFont(for zone: ZoneModel) -> Font {
        let style = zone.textStyle; let family = zone.fontFamily
        let weight: Font.Weight = zone.isBold ? .bold : (style == .title ? .bold : (style == .headline ? .semibold : .regular))
        let size: CGFloat
        switch style { case .body: size = 18; case .title: size = 28; case .headline: size = 22; case .caption: size = 14 }
        return family.font(size: size, weight: weight)
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
    }

    private func loadImage() {
        Task.detached {
            let optimizedImage = await ImageCache.shared.image(for: data, id: String(data.hashValue), targetSize: CGSize(width: 800, height: 800), scale: 1.0)
            await MainActor.run { self.uiImage = optimizedImage ?? UIImage(data: data) }
        }
    }
}

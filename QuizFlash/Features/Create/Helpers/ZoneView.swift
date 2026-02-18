//
//  ZoneView.swift
//  QuizFlash
//
//  Zone editor views with PURE VISUAL ghost overlay support.
//  NO data model mutation - ghost is rendered as overlay only.
//

import SwiftUI
import PhotosUI

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
    
    @ViewBuilder
    private func containerZoneView(zone: ZoneModel) -> some View {
        let children = zone.children ?? []
        let isHorizontal = zone.direction == .horizontal
        
        if isHorizontal {
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, _ in
                    ZoneEditorView(
                        content: content,
                        path: path.appending(index),
                        selectedPath: $selectedPath,
                        highlightContext: highlightContext,
                        previewDirection: previewDirection
                    )
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 8) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, _ in
                    ZoneEditorView(
                        content: content,
                        path: path.appending(index),
                        selectedPath: $selectedPath,
                        highlightContext: highlightContext,
                        previewDirection: previewDirection
                    )
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
    
    private func selectZone() {
        selectedPath = path
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Zone Content View (Leaf)

struct ZoneContentView: View {
    @Bindable var content: ZoneCardContent
    let path: ZonePath
    let isSelected: Bool
    var highlightContext: HighlightContext?
    var onSelect: () -> Void
    @Binding var previewDirection: AddDirection?
    
    @FocusState private var isFocused: Bool
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
        guard let highlightContext = highlightContext,
              let zone = zone else { return false }
        return highlightContext.shouldHighlight(text: zone.text)
    }
    
    var body: some View {
        contentView
            .frame(maxWidth: .infinity, alignment: alignmentFor(zone))
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(isSelected ? accent : Color.secondary.opacity(0.25))
                    .frame(width: isSelected ? 4 : 3)
                    .padding(.vertical, 8)
                    .offset(x: -10)
                    .animation(.spring(response: 0.3), value: isSelected)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
                if zone?.contentType == .text || zone?.contentType == .empty {
                    isFocused = true
                }
            }
            .onLongPressGesture {
                // Long press handled by ZoneFormatBar drag gesture
            }
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
            .onReceive(NotificationCenter.default.publisher(for: .focusNewZone)) { notification in
                if let targetID = notification.object as? UUID, targetID == currentZoneID {
                    if zone?.contentType == .text || zone?.contentType == .empty {
                        isFocused = true
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
    
    // MARK: - Text View with Ghost Overlay (PURE VISUAL)
    
    @ViewBuilder
    private var textViewWithGhostOverlay: some View {
        HStack(alignment: .top, spacing: 8) {
            if zone?.hasBullet == true {
                Circle()
                    .fill(zone?.textColor.color ?? .primary)
                    .frame(width: 6, height: 6)
                    .padding(.top, 8)
            }
            
            ZStack(alignment: ghostAlignment) {
                if shouldShowHighlight {
                    highlightedBackground
                }
                
                // Capture values for closure
                let zoneID = zone?.id ?? UUID()
                let currentTextColor = zone?.textColor.color ?? .primary
                let currentTextAlignment = zone?.textAlignment.nsTextAlignment ?? .left
                let currentIsBold = zone?.isBold ?? false
                let currentIsItalic = zone?.isItalic ?? false
                let currentPath = path
                let currentContentType = zone?.contentType ?? .empty
                
                ZoneTextViewRepresentable(
                    text: pureTextBinding,
                    font: textUIFont,
                    textColor: UIColor(currentTextColor),
                    textAlignment: currentTextAlignment,
                    isBold: currentIsBold,
                    isItalic: currentIsItalic,
                    zoneID: zoneID,
                    onTextChange: { newText in
                        if currentContentType == .text || currentContentType == .empty {
                            highlightContext?.dismiss()
                            content.updateZone(at: currentPath) { z in
                                z.text = newText
                                if z.contentType == .empty {
                                    z.contentType = .text
                                }
                            }
                        }
                    },
                    onCursorChange: { range, text in
                        // Track cursor for split operations
                    },
                    onFocusLineChange: { lineIndex, totalLines in
                        lineTracker.updateFocusedLine(
                            for: zoneID,
                            lineIndex: lineIndex,
                            totalLines: totalLines
                        )
                        zoneController.updateZoneHeightInfo(
                            for: zoneID,
                            lineCount: totalLines,
                            focusedLineIndex: lineIndex
                        )
                    },
                    onCommit: {}
                )
                .font(textFont)
                .foregroundStyle(zone?.textColor.color ?? .primary)
                .tint(accent)
                .multilineTextAlignment(zone?.textAlignment.alignment ?? .leading)
                .focused($isFocused)
                
                // PURE VISUAL GHOST OVERLAY - No data mutation!
                if let direction = previewDirection, isSelected {
                    ghostPreviewOverlay(direction: direction)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, zone?.highlightColor != HighlightColor.none ? 6 : 0)
            .background(
                zone?.highlightColor.color.map { color in
                    RoundedRectangle(cornerRadius: 4).fill(color)
                }
            )
        }
    }
    
    // MARK: - Ghost Preview Overlay (Visual Only)
    
    @ViewBuilder
    private func ghostPreviewOverlay(direction: AddDirection) -> some View {
        // Ghost appears adjacent to the current zone based on direction
        GhostZonePreview(direction: direction, accent: accent)
    }
    
    private var ghostAlignment: Alignment {
        switch previewDirection {
        case .left: return .trailing
        case .right: return .leading
        case .up: return .bottom
        case .down: return .top
        case .none: return .topLeading
        }
    }
    
    // MARK: - Focus Handling
    
    private func handleFocusChange(_ focused: Bool) {
        if focused {
            highlightContext?.dismiss()
            if !isSelected { onSelect() }
            if let zoneID = currentZoneID {
                focusManager.updateFocusedZone(zoneID)
                zoneController.updateFocusedZone(zoneID)
            }
        }
    }
    
    // MARK: - Highlight Overlay
    
    private var highlightedBackground: some View {
        let rawText = zone?.text ?? ""
        let displayText = rawText.hasSuffix("\n") 
            ? rawText + "\u{200B}" 
            : (rawText.isEmpty ? "\u{200B}" : rawText)
        
        let attrString = highlightContext?.generateOverlay(
            for: displayText,
            font: textFont,
            highlightColor: ThemeManager.shared.accentColor.color
        ) ?? AttributedString(displayText)
        
        return Text(attrString)
            .multilineTextAlignment(zone?.textAlignment.alignment ?? .leading)
            .allowsHitTesting(false)
    }
    
    // MARK: - Text Binding
    
    private var pureTextBinding: Binding<String> {
        Binding(
            get: { zone?.text ?? "" },
            set: { newValue in
                if self.zone?.text != newValue {
                    highlightContext?.dismiss()
                    content.updateZone(at: path) { zone in
                        zone.text = newValue
                        if zone.contentType == .empty {
                            zone.contentType = .text
                        }
                    }
                }
            }
        )
    }
    
    // MARK: - Font Helpers
    
    private var textFont: Font {
        let style = zone?.textStyle ?? .body
        let family = zone?.fontFamily ?? .system
        let weight: Font.Weight = zone?.isBold == true 
            ? .bold 
            : (style == .title ? .bold : (style == .headline ? .semibold : .regular))
        let size: CGFloat
        switch style {
        case .body: size = 18
        case .title: size = 28
        case .headline: size = 22
        case .caption: size = 14
        }
        return family.font(size: size, weight: weight)
    }
    
    private var textUIFont: UIFont {
        let style = zone?.textStyle ?? .body
        let family = zone?.fontFamily ?? .system
        let weight: UIFont.Weight = zone?.isBold == true 
            ? .bold 
            : (style == .title ? .bold : (style == .headline ? .semibold : .regular))
        let size: CGFloat
        switch style {
        case .body: size = 18
        case .title: size = 28
        case .headline: size = 22
        case .caption: size = 14
        }
        return family.uiFont(size: size, weight: weight)
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
                        .clipShape(RoundedRectangle(cornerRadius: 30))
                    if isSelected { deleteButton }
                }
                if align == .leading || align == .center { Spacer(minLength: 0) }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Sketch View
    
    @ViewBuilder
    private var sketchView: some View {
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
                        .background(colorScheme == .dark ? Color.black : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 30))
                    if isSelected { deleteButton }
                }
                if align == .leading || align == .center { Spacer(minLength: 0) }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Delete Button
    
    private var deleteButton: some View {
        Button {
            content.deleteZone(at: path)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.white, .red.opacity(0.8))
        }
        .padding(8)
    }
    
    // MARK: - Alignment Helper
    
    private func alignmentFor(_ zone: ZoneModel?) -> Alignment {
        switch zone?.textAlignment ?? .leading {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - Ghost Zone Preview (Visual Overlay Only)

struct GhostZonePreview: View {
    let direction: AddDirection
    let accent: Color
    
    var body: some View {
        HStack(spacing: 4) {
            if direction == .left {
                ghostBubble
                Spacer(minLength: 12)
            }
            
            VStack(spacing: 4) {
                if direction == .up {
                    ghostBubble
                    Spacer(minLength: 8)
                }
                
                Text("Release to Create")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                
                if direction == .down {
                    Spacer(minLength: 8)
                    ghostBubble
                }
            }
            
            if direction == .right {
                Spacer(minLength: 12)
                ghostBubble
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
    
    private var ghostBubble: some View {
        Image(systemName: "plus.circle.fill")
            .font(.title2)
            .foregroundStyle(accent)
            .frame(width: 44, height: 44)
            .background(
                Circle()
                    .fill(accent.opacity(0.15))
                    .overlay(
                        Circle()
                            .stroke(accent.opacity(0.5), lineWidth: 2)
                    )
            )
    }
    
    private var alignment: Alignment {
        switch direction {
        case .left: return .trailing
        case .right: return .leading
        case .up: return .bottom
        case .down: return .top
        }
    }
}

// MARK: - Zone Preview View (Read-only for Play Mode)

struct ZonePreviewView: View {
    let zone: ZoneModel
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        if zone.isLeaf {
            leafPreview
        } else {
            containerPreview
        }
    }
    
    @ViewBuilder
    private var leafPreview: some View {
        switch zone.contentType {
        case .empty:
            Color.clear.frame(height: 28).padding(.vertical, 4)
        case .text:
            if !zone.text.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    if zone.hasBullet {
                        Circle()
                            .fill(zone.textColor.color)
                            .frame(width: 6, height: 6)
                            .padding(.top, 8)
                    }
                    
                    Text(zone.text)
                        .font(previewFont(for: zone))
                        .fontWeight(zone.isBold ? .bold : .regular)
                        .italic(zone.isItalic)
                        .foregroundStyle(zone.textColor.color)
                        .multilineTextAlignment(zone.textAlignment.alignment)
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
        case .image:
            if let data = zone.imageData {
                CachedImageView(data: data, scale: zone.imageScale, alignment: zone.textAlignment, cornerRadius: 10)
            }
        case .sketch:
            if let data = zone.imageData {
                CachedImageView(data: data, scale: zone.imageScale, alignment: zone.textAlignment, cornerRadius: 10, isSketch: true)
            }
        }
    }
    
    @ViewBuilder
    private var containerPreview: some View {
        let children = zone.children ?? []
        if zone.direction == .horizontal {
            HStack(alignment: .top, spacing: 12) {
                ForEach(children) { child in
                    ZonePreviewView(zone: child)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(children) { child in
                    ZonePreviewView(zone: child)
                }
            }
        }
    }
    
    private func alignmentFor(_ zone: ZoneModel) -> Alignment {
        switch zone.textAlignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
    
    private func previewFont(for zone: ZoneModel) -> Font {
        let style = zone.textStyle
        let family = zone.fontFamily
        let weight: Font.Weight = zone.isBold 
            ? .bold 
            : (style == .title ? .bold : (style == .headline ? .semibold : .regular))
        let size: CGFloat
        switch style {
        case .body: size = 18
        case .title: size = 28
        case .headline: size = 22
        case .caption: size = 14
        }
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
                    if alignment == .trailing || alignment == .center {
                        Spacer(minLength: 0)
                    }
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: UIScreen.main.bounds.width * scale * 0.85)
                        .background {
                            if isSketch {
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .fill(colorScheme == .dark ? Color.black : Color.white)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    if alignment == .leading || alignment == .center {
                        Spacer(minLength: 0)
                    }
                }
            } else {
                ProgressView().frame(height: 100)
            }
        }
        .task { loadImage() }
    }
    
    private func loadImage() {
        Task.detached {
            let optimizedImage = await ImageCache.shared.image(
                for: data,
                id: String(data.hashValue),
                targetSize: CGSize(width: 800, height: 800),
                scale: 1.0
            )
            await MainActor.run {
                self.uiImage = optimizedImage ?? UIImage(data: data)
            }
        }
    }
}

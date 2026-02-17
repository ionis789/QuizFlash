//
//  ZoneView.swift
//  QuizFlash
//

import SwiftUI
import PhotosUI

// MARK: - Zone Editor View (Recursive)
struct ZoneEditorView: View {
    @Bindable var content: ZoneCardContent
    let path: ZonePath
    @Binding var selectedPath: ZonePath?
    var highlightContext: HighlightContext?

    private var zone: ZoneModel? { content.zone(at: path) }
    private var isSelected: Bool { selectedPath == path }

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
            onSelect: { selectZone() }
        )
        .id(path.id)
    }

    @ViewBuilder
    private func containerZoneView(zone: ZoneModel) -> some View {
        let children = zone.children ?? []
        let isHorizontal = zone.direction == .horizontal

        if isHorizontal {
            HStack(alignment: .top, spacing: 20) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, _ in
                    ZoneEditorView(content: content, path: path.appending(index), selectedPath: $selectedPath, highlightContext: highlightContext)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 8) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, _ in
                    ZoneEditorView(content: content, path: path.appending(index), selectedPath: $selectedPath, highlightContext: highlightContext)
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

    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    private var focusManager = ZoneFocusManager.shared

    private var zone: ZoneModel? { content.zone(at: path) }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var currentZoneID: UUID? { zone?.id }

    init(
        content: ZoneCardContent,
        path: ZonePath,
        isSelected: Bool,
        highlightContext: HighlightContext? = nil,
        onSelect: @escaping () -> Void
    ) {
        self.content = content
        self.path = path
        self.isSelected = isSelected
        self.highlightContext = highlightContext
        self.onSelect = onSelect
    }

    private var shouldShowHighlight: Bool {
        highlightContext?.shouldHighlight(text: zone?.text ?? "") ?? false
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
            .onChange(of: isFocused) { _, focused in
                if focused {
                    highlightContext?.dismiss()
                    if !isSelected { onSelect() }
                }
            }
            .onChange(of: focusManager.pendingFocusZoneID) { _, pendingID in
                if pendingID == currentZoneID {
                    if zone?.contentType == .text || zone?.contentType == .empty { isFocused = true }
                    focusManager.clearPendingFocus()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusNewZone)) { notification in
                if let targetID = notification.object as? UUID, targetID == currentZoneID {
                    if zone?.contentType == .text || zone?.contentType == .empty { isFocused = true }
                }
            }
    }

    @ViewBuilder
    private var contentView: some View {
        switch zone?.contentType ?? .empty {
        case .empty, .text: textView
        case .image: imageView
        case .sketch: sketchView
        }
    }

    // MARK: - Text View
    @ViewBuilder
    private var textView: some View {
        HStack(alignment: .top, spacing: 8) {
            if zone?.hasBullet == true {
                Circle().fill(zone?.textColor.color ?? .primary).frame(width: 6, height: 6).padding(.top, 8)
            }

            ZStack(alignment: .topLeading) {
                if shouldShowHighlight {
                    highlightedBackground
                }

                TextField("", text: pureTextBinding, axis: .vertical)
                    .font(textFont)
                    .fontWeight(zone?.isBold == true ? .bold : .regular)
                    .italic(zone?.isItalic == true)
                    .foregroundStyle(zone?.textColor.color ?? .primary)
                    .tint(accent)
                    .multilineTextAlignment(zone?.textAlignment.alignment ?? .leading)
                    .focused($isFocused)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, zone?.highlightColor != HighlightColor.none ? 6 : 0)
            .background(
                zone?.highlightColor.color.map { color in RoundedRectangle(cornerRadius: 4).fill(color) }
            )
        }
    }

    // MARK: - Safe MVVM Overlay Background
    private var highlightedBackground: some View {
        let rawText = zone?.text ?? ""
        let displayText = rawText.hasSuffix("\n") ? rawText + "\u{200B}" : (rawText.isEmpty ? "\u{200B}" : rawText)
        
        // Pure MVVM: View asks ViewModel for the fully formatted transparent string
        let attrString = highlightContext?.generateOverlay(
            for: displayText,
            font: textFont,
            highlightColor: ThemeManager.shared.accentColor.color
        ) ?? AttributedString(displayText)
        
        return Text(attrString)
            .multilineTextAlignment(zone?.textAlignment.alignment ?? .leading)
            .allowsHitTesting(false)
    }

    // MARK: - Pristine TextField Binding
    private var pureTextBinding: Binding<String> {
        Binding(
            get: { zone?.text ?? "" },
            set: { newValue in
                if self.zone?.text != newValue {
                    
                    // MARK: FIX - Instantly trigger global dismissal on ANY text mutation.
                    // This physically guarantees no highlight can ever lag at an "old position".
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

    private var textFont: Font {
        let style = zone?.textStyle ?? .body
        let family = zone?.fontFamily ?? .system
        let weight: Font.Weight = zone?.isBold == true ? .bold : (style == .title ? .bold : (style == .headline ? .semibold : .regular))
        let size: CGFloat
        switch style {
        case .body: size = 18
        case .title: size = 28
        case .headline: size = 22
        case .caption: size = 14
        }
        return family.font(size: size, weight: weight)
    }

    @ViewBuilder
    private var imageView: some View {
        if let data = zone?.imageData, let img = UIImage(data: data) {
            let scale = zone?.imageScale ?? 1.0
            let align = zone?.textAlignment ?? .leading
            HStack(spacing: 0) {
                if align == .trailing || align == .center { Spacer(minLength: 0) }
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: UIScreen.main.bounds.width * scale * 0.8).clipShape(RoundedRectangle(cornerRadius: 30))
                    if isSelected { deleteButton }
                }
                if align == .leading || align == .center { Spacer(minLength: 0) }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var sketchView: some View {
        if let data = zone?.imageData, let img = UIImage(data: data) {
            let scale = zone?.imageScale ?? 1.0
            let align = zone?.textAlignment ?? .leading
            HStack(spacing: 0) {
                if align == .trailing || align == .center { Spacer(minLength: 0) }
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: UIScreen.main.bounds.width * scale * 0.8).background(colorScheme == .dark ? Color.black : Color.white).clipShape(RoundedRectangle(cornerRadius: 30))
                    if isSelected { deleteButton }
                }
                if align == .leading || align == .center { Spacer(minLength: 0) }
            }
            .padding(.vertical, 8)
        }
    }

    private var deleteButton: some View {
        Button { content.deleteZone(at: path) } label: {
            Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white, .red.opacity(0.8))
        }
        .padding(8)
    }

    private func alignmentFor(_ zone: ZoneModel?) -> Alignment {
        switch zone?.textAlignment ?? .leading {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - Preview Components Abbreviated for space - Keep exact same preview code as before.

// MARK: - Zone Preview View (for play mode, read-only)
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
                            zone.highlightColor.color.map { color in RoundedRectangle(cornerRadius: 4).fill(color) }
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
                ForEach(children) { child in ZonePreviewView(zone: child) }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(children) { child in ZonePreviewView(zone: child) }
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
        let weight: Font.Weight = zone.isBold ? .bold : (style == .title ? .bold : (style == .headline ? .semibold : .regular))
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

// MARK: - Adaptive Zone Preview
struct AdaptiveZonePreview: View {
    let zone: ZoneModel
    let containerSize: CGSize

    private var isScreenLandscape: Bool { containerSize.width > containerSize.height }
    private var contentPreferredOrientation: CardOrientation { zone.preferredOrientation }

    private var needsAdaptation: Bool {
        switch contentPreferredOrientation {
        case .landscape: return !isScreenLandscape
        case .portrait: return isScreenLandscape
        case .adaptive: return false
        }
    }

    var body: some View {
        if needsAdaptation {
            adaptedView
        } else {
            ZonePreviewView(zone: zone)
        }
    }

    @ViewBuilder
    private var adaptedView: some View {
        switch contentPreferredOrientation {
        case .landscape:
            ScrollView(.horizontal, showsIndicators: false) {
                ZonePreviewView(zone: zone).frame(minWidth: containerSize.height * 1.5)
            }
        case .portrait:
            ScrollView(.vertical, showsIndicators: false) {
                ZonePreviewView(zone: zone).frame(minHeight: containerSize.width * 1.2)
            }
        case .adaptive:
            ZonePreviewView(zone: zone)
        }
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
                    if alignment == .leading || alignment == .center { Spacer(minLength: 0) }
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
                for: data, id: String(data.hashValue), targetSize: CGSize(width: 800, height: 800), scale: 1.0
            )
            await MainActor.run { self.uiImage = optimizedImage ?? UIImage(data: data) }
        }
    }
}

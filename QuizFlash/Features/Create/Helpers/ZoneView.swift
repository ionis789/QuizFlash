//
//  ZoneView.swift
//  QuizFlash
//
//  Recursive view that renders zones with proper width/height distribution.
//

import SwiftUI
import PhotosUI
import Combine

// MARK: - Notification for focus trigger
extension Notification.Name {
    static let focusNewZone = Notification.Name("focusNewZone")
    static let scrollToCursor = Notification.Name("scrollToCursor")
}

// MARK: - Zone Focus Manager
/// Singleton that manages focus for new zones and prevents keyboard flicker by syncing with SwiftUI render cycle.
@MainActor
final class ZoneFocusManager: ObservableObject {
    static let shared = ZoneFocusManager()

    @Published var pendingFocusZoneID: UUID?
    @Published var shouldRetainKeyboard: Bool = false

    /// Task reference so we can cancel if user taps again quickly.
    private var releaseTask: Task<Void, Never>?

    func requestFocus(for zoneID: UUID) {
        pendingFocusZoneID = zoneID
    }

    func clearPendingFocus() {
        pendingFocusZoneID = nil
        releaseTask?.cancel()
        releaseTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            if !Task.isCancelled {
                self.shouldRetainKeyboard = false
            }
        }
    }

    func prepareForInsertion() {
        releaseTask?.cancel()
        shouldRetainKeyboard = true
    }
}

// MARK: - Zone Editor View (Recursive)

struct ZoneEditorView: View {
    @Bindable var content: ZoneCardContent
    let path: ZonePath
    @Binding var selectedPath: ZonePath?

    @Environment(\.colorScheme) private var colorScheme

    private var zone: ZoneModel? { content.zone(at: path) }
    private var isSelected: Bool { selectedPath == path }
    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        if let zone = zone {
            if zone.isLeaf {
                leafZoneView(zone: zone)
            } else {
                containerZoneView(zone: zone)
            }
        }
    }

    // MARK: - Leaf Zone (Content)

    @ViewBuilder
    private func leafZoneView(zone: ZoneModel) -> some View {
        ZoneContentView(
            content: content,
            path: path,
            isSelected: isSelected,
            onSelect: { selectZone() }
        )
            .id(path.id) // For ScrollViewReader auto-scroll
    }

    // MARK: - Container Zone (Children)

    @ViewBuilder
    private func containerZoneView(zone: ZoneModel) -> some View {
        let children = zone.children ?? []
        let isHorizontal = zone.direction == .horizontal

        if isHorizontal {
            HStack(alignment: .top, spacing: 20) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, _ in
                    ZoneEditorView(
                        content: content,
                        path: path.appending(index),
                        selectedPath: $selectedPath
                    )
                }
            }
                .fixedSize(horizontal: false, vertical: true) // Force columns to match tallest sibling height
        } else {
            VStack(spacing: 8) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, _ in
                    ZoneEditorView(
                        content: content,
                        path: path.appending(index),
                        selectedPath: $selectedPath
                    )
                }
            }
                .frame(maxHeight: .infinity, alignment: .top) // Align to top when horizontal sibling is taller
        }
    }

    private func selectZone() {
        selectedPath = path
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Zone Content View (Leaf)

private struct ZoneContentView: View {
    @Bindable var content: ZoneCardContent
    let path: ZonePath
    let isSelected: Bool
    var onSelect: () -> Void
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var focusManager = ZoneFocusManager.shared
    @State private var cursorIndex: Int? = nil

    private var zone: ZoneModel? { content.zone(at: path) }
    private var accent: Color { ThemeManager.shared.accentColor.color }

    /// Current zone ID for comparison with pendingFocusZoneID.
    private var currentZoneID: UUID? { zone?.id }

    // MARK: - Dynamic Min Height (empty lines)
    private var dynamicMinHeight: CGFloat {
        let text = zone?.text ?? ""
        let lineCount = max(1, text.components(separatedBy: "\n").count)
        let style = zone?.textStyle ?? .body
        let lineHeight: CGFloat
        switch style {
        case .body: lineHeight = 22
        case .title: lineHeight = 34
        case .headline: lineHeight = 26
        case .caption: lineHeight = 17
        }

        return CGFloat(lineCount) * lineHeight
    }

    var body: some View {
        contentView
            .frame(maxWidth: .infinity, alignment: alignmentFor(zone))
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .leading) {
            // Selection indicator placed outside view via offset
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
        .onAppear {
            checkPendingFocus()
        }
            .onChange(of: focusManager.pendingFocusZoneID) { _, _ in
            checkPendingFocus()
        }
            .onChange(of: isFocused) { _, focused in
            if focused && !isSelected {
                onSelect()
            }
        }
            .onChange(of: isSelected) { _, selected in
            if !selected && isFocused {
                isFocused = false
            }
        }
            .onChange(of: focusManager.pendingFocusZoneID) { _, pendingID in
            if let pendingID, let currentID = currentZoneID, pendingID == currentID {
                if zone?.contentType == .text || zone?.contentType == .empty {
                    isFocused = true
                }
                focusManager.clearPendingFocus()
            }
        }
            .onReceive(NotificationCenter.default.publisher(for: .focusNewZone)) { notification in
            if let targetID = notification.object as? UUID {
                if let currentID = currentZoneID, targetID == currentID {
                    if zone?.contentType == .text || zone?.contentType == .empty {
                        isFocused = true
                    }
                }
            } else if isSelected && (zone?.contentType == .text || zone?.contentType == .empty) {
                isFocused = true
            }
        }
            .task(id: isSelected) {
            if isSelected && zone?.text.isEmpty == true {
                try? await Task.sleep(for: .milliseconds(80))
                if isSelected { isFocused = true }
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch zone?.contentType ?? .empty {
        case .empty, .text:
            textView
        case .image:
            imageView
        case .sketch:
            sketchView
        }
    }

    // MARK: - Text View


    @ViewBuilder
    private var textView: some View {
        HStack(alignment: .top, spacing: 8) {
            if zone?.hasBullet == true {
                Circle()
                    .fill(zone?.textColor.color ?? .primary)
                    .frame(width: 6, height: 6)
                    .padding(.top, 8)
            }

            // Native TextField; textBinding above keeps cursor from squashing
            TextField("", text: textBinding, axis: .vertical)
                .font(textFont)
                .fontWeight(zone?.isBold == true ? .bold : .regular)
                .italic(zone?.isItalic == true)
                .foregroundStyle(zone?.textColor.color ?? .primary)
                .multilineTextAlignment(zone?.textAlignment.alignment ?? .leading)
                .focused($isFocused)
                .padding(.vertical, 8)
                .padding(.horizontal, zone?.highlightColor != HighlightColor.none ? 6 : 0)
                .background(
                zone?.highlightColor.color.map { color in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                }
            )
                .onChange(of: zone?.text) { _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .scrollToCursor, object: nil)
                }
            }
        }
    }



    /// Computed font based on textStyle and fontFamily
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

    // MARK: - Image View

    @ViewBuilder
    private var imageView: some View {
        if let data = zone?.imageData, let img = UIImage(data: data) {
            let scale = zone?.imageScale ?? 1.0
            let align = zone?.textAlignment ?? .leading

            HStack(spacing: 0) {
                if align == .trailing || align == .center {
                    Spacer(minLength: 0)
                }

                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(maxWidth: UIScreen.main.bounds.width * scale * 0.8)
                        .clipShape(RoundedRectangle(cornerRadius: 30))
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                    if isSelected {
                        deleteButton
                    }
                }

                if align == .leading || align == .center {
                    Spacer(minLength: 0)
                }
            }
                .padding(.vertical, 8)
        } else {
            imagePlaceholder
        }
    }

    // MARK: - Sketch View

    @ViewBuilder
    private var sketchView: some View {
        if let data = zone?.imageData, let img = UIImage(data: data) {
            let scale = zone?.imageScale ?? 1.0
            let align = zone?.textAlignment ?? .leading
            HStack(spacing: 0) {
                if align == .trailing || align == .center {
                    Spacer(minLength: 0)
                }

                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(maxWidth: UIScreen.main.bounds.width * scale * 0.8)
                        .frame(maxHeight: UIScreen.main.bounds.height * scale * 0.8)
                        .background(colorScheme == .dark ? Color.black : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 30))
                        .overlay {
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    }

                    if isSelected {
                        deleteButton
                    }
                }

                if align == .leading || align == .center {
                    Spacer(minLength: 0)
                }
            }
                .padding(.vertical, 8)
        } else {
            sketchPlaceholder
        }
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondary.opacity(0.1))
            .frame(height: 100)
            .overlay {
            VStack(spacing: 4) {
                Image(systemName: "photo")
                    .font(.title2)
                Text("Add image")
                    .font(.caption)
            }
                .foregroundStyle(.secondary)
        }
            .padding(.vertical, 8)
    }

    private var sketchPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondary.opacity(0.1))
            .frame(height: 100)
            .overlay {
            VStack(spacing: 4) {
                Image(systemName: "scribble.variable")
                    .font(.title2)
                Text("Add sketch")
                    .font(.caption)
            }
                .foregroundStyle(.secondary)
        }
            .padding(.vertical, 8)
    }

    private var deleteButton: some View {
        Button {
            content.deleteZone(at: path)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.white, .red.opacity(0.8))
        }
            .padding(8)
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Helpers

    private var textBinding: Binding<String> {
        Binding(
            get: {
                var t = zone?.text ?? ""
                // If text ends with newline, append zero-width space so SwiftUI computes cursor height correctly
                if t.hasSuffix("\n") { t += "\u{200B}" }
                return t
            },
            set: { newValue in
                let cleanValue = newValue.replacingOccurrences(of: "\u{200B}", with: "")
                content.updateZone(at: path) { zone in
                    zone.text = cleanValue
                    if zone.contentType == .empty {
                        zone.contentType = .text
                    }
                }
            }
        )
    }

    private func alignmentFor(_ zone: ZoneModel?) -> Alignment {
        switch zone?.textAlignment ?? .leading {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
    private func checkPendingFocus() {
        if let pendingID = focusManager.pendingFocusZoneID,
            let currentID = currentZoneID,
            pendingID == currentID {

            if zone?.contentType == .text || zone?.contentType == .empty {
                isFocused = true
            }
            focusManager.clearPendingFocus()
        }
    }
}

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
//            EmptyView()
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
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color)
                        }
                    )
                }
                    .frame(maxWidth: .infinity, alignment: alignmentFor(zone))
            }

        case .image:
            if let data = zone.imageData {
                // Use cached/optimized image
                CachedImageView(
                    data: data,
                    scale: zone.imageScale,
                    alignment: zone.textAlignment,
                    cornerRadius: 10
                )
            }

        case .sketch:
            if let data = zone.imageData {
                // Use cached/optimized image with sketch background
                CachedImageView(
                    data: data,
                    scale: zone.imageScale,
                    alignment: zone.textAlignment,
                    cornerRadius: 10,
                    isSketch: true
                )
            }
        }
    }

    @ViewBuilder
    private var containerPreview: some View {
        let children = zone.children ?? []
        let isHorizontal = zone.direction == .horizontal

        if isHorizontal {
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

    /// Computed font for preview based on textStyle and fontFamily
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

// MARK: - Adaptive Zone Preview (handles orientation mismatches)

struct AdaptiveZonePreview: View {
    let zone: ZoneModel
    let containerSize: CGSize

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isScreenLandscape: Bool {
        containerSize.width > containerSize.height
    }

    private var contentPreferredOrientation: CardOrientation {
        zone.preferredOrientation
    }

    private var needsAdaptation: Bool {
        switch contentPreferredOrientation {
        case .landscape:
            return !isScreenLandscape // Content is landscape but screen is portrait
        case .portrait:
            return isScreenLandscape // Content is portrait but screen is landscape
        case .adaptive:
            return false
        }
    }

    var body: some View {
        if needsAdaptation {
            // Show adapted layout with scroll or scale
            adaptedView
        } else {
            // Normal display
            ZonePreviewView(zone: zone)
        }
    }

    @ViewBuilder
    private var adaptedView: some View {
        switch contentPreferredOrientation {
        case .landscape:
            // Landscape content on portrait screen - make scrollable horizontally
            ScrollView(.horizontal, showsIndicators: false) {
                ZonePreviewView(zone: zone)
                    .frame(minWidth: containerSize.height * 1.5) // Give it landscape-like width
            }

        case .portrait:
            // Portrait content on landscape screen - make scrollable vertically
            ScrollView(.vertical, showsIndicators: false) {
                ZonePreviewView(zone: zone)
                    .frame(minHeight: containerSize.width * 1.2) // Give it portrait-like height
            }

        case .adaptive:
            ZonePreviewView(zone: zone)
        }
    }
}

// MARK: - Cached Image View (Optimized)

/// Image view that uses cache and respects scale/alignment
struct CachedImageView: View {
    let data: Data
    let scale: CGFloat
    let alignment: TextBlockAlignment
    let cornerRadius: CGFloat
    var isSketch: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var uiImage: UIImage?

    private var horizontalAlignment: HorizontalAlignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var body: some View {
        Group {
            if let image = uiImage {
                imageContent(image: image)
            } else {
                ProgressView()
                    .frame(height: 100)
            }
        }
            .task {
            loadImage()
        }
    }

    @ViewBuilder
    private func imageContent(image: UIImage) -> some View {
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
    }

    private func loadImage() {
        // Use cache for better performance
        if let cached = ImageCache.shared.image(for: data, scale: 1.0) {
            uiImage = cached
        } else {
            Task.detached {
                let image = UIImage(data: data)
                await MainActor.run {
                    uiImage = image
                }
            }
        }
    }
}

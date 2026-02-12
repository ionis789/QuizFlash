//
//  ZoneView.swift
//  QuizFlash
//
//  Recursive view that renders zones with proper width/height distribution.
//

import SwiftUI
import PhotosUI

// MARK: - Notification for focus trigger
extension Notification.Name {
    static let focusNewZone = Notification.Name("focusNewZone")
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
            HStack(spacing: 8) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, _ in
                    ZoneEditorView(
                        content: content,
                        path: path.appending(index),
                        selectedPath: $selectedPath
                    )
                }
            }
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
    
    private var zone: ZoneModel? { content.zone(at: path) }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Vertical line indicator
            Capsule()
                .fill(isSelected ? accent : Color.secondary.opacity(0.25))
                .frame(width: isSelected ? 4 : 3)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 8)
                .padding(.trailing, 10)
                .animation(.spring(response: 0.3), value: isSelected)
            
            // Content based on type
            contentView
                .frame(maxWidth: .infinity, alignment: alignmentFor(zone))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
            if zone?.contentType == .text || zone?.contentType == .empty {
                isFocused = true
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused { onSelect() }
        }
        // Listen for focus trigger notification (for new zones)
        .onReceive(NotificationCenter.default.publisher(for: .focusNewZone)) { _ in
            if isSelected && (zone?.contentType == .text || zone?.contentType == .empty) {
                isFocused = true
            }
        }
        // Auto-focus when this zone becomes selected and is empty
        .onChange(of: isSelected) { _, selected in
            if selected && zone?.text.isEmpty == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
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
            
            TextField("Type here...", text: textBinding, axis: .vertical)
                .font(zone?.textStyle.font ?? .system(size: 17))
                .fontWeight(zone?.isBold == true ? .bold : .regular)
                .italic(zone?.isItalic == true)
                .foregroundStyle(zone?.textColor.color ?? .primary)
                .multilineTextAlignment(zone?.textAlignment.alignment ?? .leading)
                .focused($isFocused)
                .padding(.vertical, 8)
        }
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
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                        .background(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    
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
            get: { zone?.text ?? "" },
            set: { newValue in
                content.updateZone(at: path) { zone in
                    zone.text = newValue
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
            EmptyView()
            
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
                        .font(zone.textStyle.font)
                        .fontWeight(zone.isBold ? .bold : .regular)
                        .italic(zone.isItalic)
                        .foregroundStyle(zone.textColor.color)
                        .multilineTextAlignment(zone.textAlignment.alignment)
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
        // Simple approach: use frame with alignment
        HStack(spacing: 0) {
            if alignment == .trailing || alignment == .center {
                Spacer(minLength: 0)
            }
            
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: UIScreen.main.bounds.width * scale * 0.85) // 85% of screen * scale
                .background {
                    if isSketch {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.white)
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

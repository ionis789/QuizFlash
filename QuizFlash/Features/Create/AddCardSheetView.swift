//
//  AddCardSheetView.swift
//  QuizFlash
//
//  Card editor with zone-based layout, image resize, split, and adaptive sizing.
//

import SwiftUI
import PhotosUI

struct AddCardSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // NEW: Save zones directly to preserve layout structure
    var onSaveZones: (ZoneModel, ZoneModel) -> Void
    
    // Zone-based content
    @State private var frontZoneContent: ZoneCardContent
    @State private var backZoneContent: ZoneCardContent
    @State private var activeSide = 0
    
    // FAB Menu
    @State private var showFABMenu = false
    
    // Keyboard tracking
    @State private var keyboardHeight: CGFloat = 0
    
    // Modals
    @State private var showPhotoPicker = false
    @State private var showSketchModal = false
    @State private var showPreview = false
    @State private var selectedPhoto: PhotosPickerItem?
    
    // Selection
    @State private var selectedPath: ZonePath? = .root
    
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var currentContent: ZoneCardContent { activeSide == 0 ? frontZoneContent : backZoneContent }
    private var canSave: Bool { frontZoneContent.hasContent || backZoneContent.hasContent }
    
    // MARK: - Init
    
    init(onSave: @escaping (ZoneModel, ZoneModel) -> Void) {
        self.onSaveZones = onSave
        _frontZoneContent = State(initialValue: ZoneCardContent(rootZone: .text()))
        _backZoneContent = State(initialValue: ZoneCardContent(rootZone: .text()))
    }
    
    init(frontZone: ZoneModel, backZone: ZoneModel, onSave: @escaping (ZoneModel, ZoneModel) -> Void) {
        self.onSaveZones = onSave
        _frontZoneContent = State(initialValue: ZoneCardContent(rootZone: frontZone))
        _backZoneContent = State(initialValue: ZoneCardContent(rootZone: backZone))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Main content
                VStack(spacing: 0) {
                    sidePicker
                    Divider()
                    editorArea
                    
                    // Format bar at the bottom (when zone selected)
                    if let path = selectedPath, currentContent.zone(at: path) != nil {
                        ZoneFormatBar(
                            content: currentContent,
                            path: path,
                            onAddZone: { direction in addZoneWithFocus(in: direction) },
                            onSplit: { splitZone() },
                            onClose: { selectedPath = nil }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                
                // Dismiss overlay when FAB menu is open
                fabDismissOverlay
                
                // FAB - ALWAYS visible, positioned above keyboard
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        fabOverlay
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { _, item in addPhoto(item) }
            .fullScreenCover(isPresented: $showSketchModal) {
                CanvasModalView { data in addSketch(data) }
            }
            .sheet(isPresented: $showPreview) {
                ZonePreviewSheet(front: frontZoneContent, back: backZoneContent)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedPath)
            // Keyboard observer
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    withAnimation(.spring(response: 0.3)) {
                        keyboardHeight = frame.height
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.spring(response: 0.3)) {
                    keyboardHeight = 0
                }
            }
        }
    }
    
    // MARK: - Side Picker
    
    private var sidePicker: some View {
        Picker("Side", selection: $activeSide) {
            Text("Question").tag(0)
            Text("Answer").tag(1)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onChange(of: activeSide) { _, _ in
            (activeSide == 0 ? backZoneContent : frontZoneContent).cleanup()
            selectedPath = .root
        }
    }
    
    // MARK: - Editor Area
    
    private var editorArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if activeSide == 0 {
                        ZoneEditorView(
                            content: frontZoneContent,
                            path: .root,
                            selectedPath: $selectedPath
                        )
                    } else {
                        ZoneEditorView(
                            content: backZoneContent,
                            path: .root,
                            selectedPath: $selectedPath
                        )
                    }
                    
                    // Tap below to add new zone at bottom
                    Color.clear
                        .frame(height: 100)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            addZoneAtBottom()
                        }
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                // Add bottom padding when format bar or FAB is visible
                .padding(.bottom, selectedPath != nil ? 80 : 100)
            }
            .scrollDismissesKeyboard(.interactively)
            // Auto-scroll when selected zone changes
            .onChange(of: selectedPath) { _, newPath in
                if let path = newPath {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            proxy.scrollTo(path.id, anchor: .center)
                        }
                    }
                }
            }
            // Auto-scroll when keyboard appears to keep selected zone visible
            .onChange(of: keyboardHeight) { oldHeight, newHeight in
                if newHeight > oldHeight, let path = selectedPath {
                    // Keyboard appearing - scroll to keep zone visible
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            proxy.scrollTo(path.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - FAB
    
    private var fabOverlay: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if showFABMenu {
                // Menu items
                VStack(spacing: 8) {
                    FABMenuItem(icon: "photo", label: "Photo") {
                        showFABMenu = false
                        showPhotoPicker = true
                    }
                    FABMenuItem(icon: "scribble.variable", label: "Sketch") {
                        showFABMenu = false
                        hideKeyboard()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { showSketchModal = true }
                    }
                }
                .transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity))
            }
            
            // Main FAB button - always visible
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { showFABMenu.toggle() }
            } label: {
                Image(systemName: showFABMenu ? "xmark" : "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                    .frame(width: 56, height: 56)
                    .background(accent)
                    .clipShape(Circle())
                    .shadow(color: accent.opacity(0.4), radius: 8, y: 4)
                    .rotationEffect(.degrees(showFABMenu ? 45 : 0))
            }
        }
        .padding(.trailing, 20)
        // FAB sits above format bar (which handles keyboard), not above keyboard directly
        // Format bar height is ~55px, so FAB just needs small offset above it
        .padding(.bottom, selectedPath != nil ? 65 : 30)
    }
    
    // Background overlay when FAB menu is open
    private var fabDismissOverlay: some View {
        Group {
            if showFABMenu {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) { showFABMenu = false }
                    }
            }
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 16) {
                Button {
                    hideKeyboard()
                    showPreview = true
                } label: {
                    Image(systemName: "eye")
                }
                .disabled(!canSave)
                
                Button("Save") {
                    frontZoneContent.cleanup()
                    backZoneContent.cleanup()
                    // Save zones directly to preserve layout structure
                    onSaveZones(frontZoneContent.rootZone, backZoneContent.rootZone)
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(!canSave)
            }
        }
    }
    
    // MARK: - Actions
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func addZone(in direction: AddDirection) {
        guard let path = selectedPath else { return }
        currentContent.addZone(relativeTo: path, direction: direction)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    /// Add zone and automatically focus on it
    private func addZoneWithFocus(in direction: AddDirection) {
        guard let path = selectedPath else { return }
        
        // Get info about structure before adding
        let parentPath = path.parent
        let childIndex = path.lastIndex ?? 0
        let parentZone = parentPath != nil ? currentContent.zone(at: parentPath!) : nil
        let parentDirection = parentZone?.direction
        let isRoot = path.indices.isEmpty
        
        // Add the zone
        currentContent.addZone(relativeTo: path, direction: direction)
        
        // Calculate new zone path based on how it was added
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if isRoot {
                // Root was wrapped in container
                switch direction {
                case .left, .up:
                    selectedPath = ZonePath(indices: [0])
                case .right, .down:
                    selectedPath = ZonePath(indices: [1])
                }
            } else if let parentPath = parentPath, parentDirection == direction.zoneDirection {
                // Same direction as parent - sibling was added
                switch direction {
                case .left, .up:
                    selectedPath = parentPath.appending(childIndex)
                case .right, .down:
                    selectedPath = parentPath.appending(childIndex + 1)
                }
            } else {
                // Different direction - current zone was wrapped in container
                switch direction {
                case .left, .up:
                    selectedPath = path.appending(0)
                case .right, .down:
                    selectedPath = path.appending(1)
                }
            }
            
            // Trigger keyboard for new zone
            triggerKeyboardForNewZone()
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    private func addZoneAtBottom() {
        // Add a new text zone at the bottom of root
        currentContent.addZone(relativeTo: .root, direction: .down)
        
        // Select the new zone (last child of root if it's a container, or the new root)
        if let children = currentContent.rootZone.children, !children.isEmpty {
            selectedPath = ZonePath(indices: [children.count - 1])
        } else {
            selectedPath = .root
        }
        
        // Trigger keyboard for new zone
        triggerKeyboardForNewZone()
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    /// Trigger keyboard focus for newly created zone
    private func triggerKeyboardForNewZone() {
        // Post notification to focus the text field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .focusNewZone, object: nil)
        }
    }
    
    private func splitZone() {
        guard let path = selectedPath,
              let zone = currentContent.zone(at: path),
              zone.contentType == .text && !zone.text.isEmpty else { return }
        
        let text = zone.text
        let lines = text.components(separatedBy: "\n")
        
        // Need at least 2 lines to split
        guard lines.count >= 2 else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        
        // Split in half by lines
        let midPoint = lines.count / 2
        let firstPart = lines[0..<midPoint].joined(separator: "\n")
        let secondPart = lines[midPoint...].joined(separator: "\n")
        
        // Update current zone with first part
        currentContent.updateZone(at: path) { z in
            z.text = firstPart
        }
        
        // Add new zone below with second part
        currentContent.addZone(relativeTo: path, direction: .down)
        
        // Find the new zone and set its text
        if let parent = path.parent {
            if let children = currentContent.zone(at: parent)?.children,
               let lastIndex = path.lastIndex,
               lastIndex + 1 < children.count {
                let newPath = parent.appending(lastIndex + 1)
                currentContent.updateZone(at: newPath) { z in
                    z.text = secondPart
                    z.contentType = .text
                    z.textStyle = zone.textStyle
                    z.textAlignment = zone.textAlignment
                    z.textColor = zone.textColor
                    z.isBold = zone.isBold
                    z.isItalic = zone.isItalic
                    z.hasBullet = zone.hasBullet
                }
                // Select the new zone
                selectedPath = newPath
            }
        } else {
            // Root was split
            if let children = currentContent.rootZone.children, children.count > 1 {
                let newPath = ZonePath(indices: [1])
                currentContent.updateZone(at: newPath) { z in
                    z.text = secondPart
                    z.contentType = .text
                }
            }
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    private func addPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                // Compress image for better performance
                let compressedData = data.compressedImageData(maxDimension: 1200, compressionQuality: 0.7) ?? data
                
                await MainActor.run {
                    if let path = selectedPath, currentContent.zone(at: path) != nil {
                        // Add to selected zone
                        currentContent.updateZone(at: path) { zone in
                            zone.contentType = .image
                            zone.imageData = compressedData
                        }
                    } else {
                        // No selection - add at bottom
                        currentContent.addZone(relativeTo: .root, direction: .down)
                        if let children = currentContent.rootZone.children, !children.isEmpty {
                            let newPath = ZonePath(indices: [children.count - 1])
                            currentContent.updateZone(at: newPath) { zone in
                                zone.contentType = .image
                                zone.imageData = compressedData
                            }
                            selectedPath = newPath
                        }
                    }
                }
            }
            selectedPhoto = nil
        }
    }
    
    private func addSketch(_ data: Data) {
        // Compress sketch for better performance
        let compressedData = data.compressedImageData(maxDimension: 1200, compressionQuality: 0.8) ?? data
        
        if let path = selectedPath, currentContent.zone(at: path) != nil {
            currentContent.updateZone(at: path) { zone in
                zone.contentType = .sketch
                zone.imageData = compressedData
            }
        } else {
            // No selection - add at bottom
            currentContent.addZone(relativeTo: .root, direction: .down)
            if let children = currentContent.rootZone.children, !children.isEmpty {
                let newPath = ZonePath(indices: [children.count - 1])
                currentContent.updateZone(at: newPath) { zone in
                    zone.contentType = .sketch
                    zone.imageData = compressedData
                }
                selectedPath = newPath
            }
        }
    }
}

// MARK: - FAB Menu Item

private struct FABMenuItem: View {
    let icon: String
    let label: String
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label).font(.subheadline.weight(.medium))
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: .tertiarySystemBackground))
                    .clipShape(Circle())
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Zone Format Bar

private struct ZoneFormatBar: View {
    @Bindable var content: ZoneCardContent
    let path: ZonePath
    var onAddZone: (AddDirection) -> Void
    var onSplit: () -> Void
    var onClose: () -> Void
    
    private var zone: ZoneModel? { content.zone(at: path) }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    
    private var canSplit: Bool {
        guard let zone = zone else { return false }
        // Can only split text zones with at least 2 lines
        guard zone.contentType == .text && !zone.text.isEmpty else { return false }
        let lines = zone.text.components(separatedBy: "\n")
        return lines.count >= 2
    }
    
    private var isTextZone: Bool {
        zone?.contentType == .text || zone?.contentType == .empty
    }
    
    private var isMediaZone: Bool {
        zone?.contentType == .image || zone?.contentType == .sketch
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // LEFT: Add Zone button - FIXED
            addZoneMenu
                .padding(.leading, 12)
                .padding(.trailing, 8)
            
            Divider().frame(height: 28)
            
            // CENTER: Scrollable formatting tools
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Split (for text)
                    if canSplit {
                        ToolbarButton(icon: "rectangle.split.1x2") { onSplit() }
                    }
                    
                    // Text/media specific tools
                    if isTextZone {
                        textTools
                    } else if isMediaZone {
                        mediaTools
                    }
                    
                    // Delete
                    ToolbarButton(icon: "trash", tint: .red) { deleteZone() }
                }
                .padding(.horizontal, 8)
            }
            
            Divider().frame(height: 28)
            
            // RIGHT: Done button - FIXED
            Button {
                onClose()
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(accent, in: Capsule())
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Add Zone Menu (Visual direction picker)
    
    private var addZoneMenu: some View {
        Menu {
            Section("Horizontal") {
                Button { onAddZone(.left) } label: {
                    Label("Left", systemImage: "arrow.left")
                }
                Button { onAddZone(.right) } label: {
                    Label("Right", systemImage: "arrow.right")
                }
            }
            Section("Vertical") {
                Button { onAddZone(.up) } label: {
                    Label("Above", systemImage: "arrow.up")
                }
                Button { onAddZone(.down) } label: {
                    Label("Below", systemImage: "arrow.down")
                }
            }
        } label: {
            Image(systemName: "plus.square.dashed")
                .font(.body.weight(.medium))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }
    
    // MARK: - Text Tools
    
    private var textTools: some View {
        HStack(spacing: 8) {
            // Style menu
            Menu {
                ForEach([TextBlockStyle.title, .headline, .body, .caption], id: \.self) { style in
                    Button { setStyle(style) } label: {
                        HStack {
                            Text(style.rawValue.capitalized)
                            if zone?.textStyle == style { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                ToolbarButton(icon: "textformat.size")
            }
            
            // Bold/Italic
            ToolbarButton(icon: "bold", isActive: zone?.isBold == true) { toggleBold() }
            ToolbarButton(icon: "italic", isActive: zone?.isItalic == true) { toggleItalic() }
            
            // Alignment
            alignmentMenu
            
            // Color
            Menu {
                ForEach(TextBlockColor.allCases, id: \.self) { color in
                    Button { setColor(color) } label: {
                        HStack {
                            Circle().fill(color.color).frame(width: 14, height: 14)
                            Text(color.name)
                        }
                    }
                }
            } label: {
                ToolbarButton(icon: "paintpalette", tint: zone?.textColor.color ?? .primary)
            }
            
            // Bullet
            ToolbarButton(icon: "list.bullet", isActive: zone?.hasBullet == true) { toggleBullet() }
        }
    }
    
    // MARK: - Media Tools
    
    private var mediaTools: some View {
        HStack(spacing: 8) {
            // Alignment
            alignmentMenu
            
            // Size
            Menu {
                Section("Image Size") {
                    Button { setImageScale(0.3) } label: { Label("Small (30%)", systemImage: "square.resize.down") }
                    Button { setImageScale(0.5) } label: { Label("Medium (50%)", systemImage: "square.resize") }
                    Button { setImageScale(0.7) } label: { Label("Large (70%)", systemImage: "square.resize.up") }
                    Button { setImageScale(1.0) } label: { Label("Full Width", systemImage: "arrow.left.and.right") }
                }
            } label: {
                ToolbarButton(icon: "aspectratio")
            }
        }
    }
    
    // MARK: - Alignment Menu
    
    private var alignmentMenu: some View {
        Menu {
            Button { setAlignment(.leading) } label: {
                HStack {
                    Label("Left", systemImage: "text.alignleft")
                    if zone?.textAlignment == .leading { Image(systemName: "checkmark") }
                }
            }
            Button { setAlignment(.center) } label: {
                HStack {
                    Label("Center", systemImage: "text.aligncenter")
                    if zone?.textAlignment == .center { Image(systemName: "checkmark") }
                }
            }
            Button { setAlignment(.trailing) } label: {
                HStack {
                    Label("Right", systemImage: "text.alignright")
                    if zone?.textAlignment == .trailing { Image(systemName: "checkmark") }
                }
            }
        } label: {
            ToolbarButton(icon: alignmentIcon)
        }
    }
    
    private var alignmentIcon: String {
        switch zone?.textAlignment ?? .leading {
        case .leading: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }
    
    // MARK: - Actions
    
    private func updateZone(_ update: (inout ZoneModel) -> Void) {
        content.updateZone(at: path, with: update)
    }
    
    private func setStyle(_ style: TextBlockStyle) { updateZone { $0.textStyle = style } }
    private func toggleBold() { updateZone { $0.isBold.toggle() } }
    private func toggleItalic() { updateZone { $0.isItalic.toggle() } }
    private func setColor(_ color: TextBlockColor) { updateZone { $0.textColor = color } }
    private func toggleBullet() { updateZone { $0.hasBullet.toggle() } }
    private func setAlignment(_ alignment: TextBlockAlignment) { updateZone { $0.textAlignment = alignment } }
    private func setImageScale(_ scale: CGFloat) { updateZone { $0.imageScale = scale } }
    
    private func deleteZone() {
        content.deleteZone(at: path)
        onClose()
    }
}

// MARK: - Toolbar Button

private struct ToolbarButton: View {
    let icon: String
    var label: String? = nil
    var isActive: Bool = false
    var tint: Color = .primary
    var action: (() -> Void)? = nil
    
    private var accent: Color { ThemeManager.shared.accentColor.color }
    
    var body: some View {
        Button { action?() } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                if let label = label {
                    Text(label)
                        .font(.caption.weight(.medium))
                }
            }
            .foregroundStyle(isActive ? accent : tint)
            .frame(height: 34)
            .padding(.horizontal, label != nil ? 10 : 0)
            .frame(minWidth: 34)
            .background(isActive ? accent.opacity(0.12) : Color(uiColor: .tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Zone Preview Sheet

private struct ZonePreviewSheet: View {
    let front: ZoneCardContent
    let back: ZoneCardContent
    @Environment(\.dismiss) private var dismiss
    @State private var showBack = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Text(showBack ? "ANSWER" : "QUESTION")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(uiColor: .systemBackground))
                            .shadow(radius: 8)
                        
                        ScrollView {
                            ZonePreviewView(zone: showBack ? back.rootZone : front.rootZone)
                                .padding(20)
                        }
                    }
                    .frame(height: 380)
                    .padding(.horizontal, 24)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) { showBack.toggle() }
                    }
                    
                    Text("Tap to flip").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.top, 20)
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    AddCardSheetView { _, _ in }
}

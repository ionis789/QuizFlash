//
//
//  AddCardSheetView.swift
//  QuizFlash
//

import SwiftUI
import PhotosUI
import SwiftData

struct AddCardSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: Architectural Fix - Required to flush memory to disk for immediate Search Sync
    @Environment(\.modelContext) private var context

    var onSaveZones: (ZoneModel, ZoneModel) -> Void
    
    // Unified Card-Level Highlight Context
    @State private var highlightContext: HighlightContext?

    // Zone-based content
    @State private var frontZoneContent: ZoneCardContent
    @State private var backZoneContent: ZoneCardContent
    @State private var activeSide = 0
    @State private var layoutTask: Task<Void, Never>? = nil
    @State private var frontSavedPath: ZonePath? = .root
    @State private var backSavedPath: ZonePath? = .root
    @State private var showFABMenu = false
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var isRetainerFocused: Bool
    @State private var retainerText: String = ""
    @State private var showPhotoPicker = false
    @State private var showSketchModal = false
    @State private var showPreview = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedPath: ZonePath? = .root
    @State private var currentCursorIndex: Int? = nil

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var currentContent: ZoneCardContent { activeSide == 0 ? frontZoneContent : backZoneContent }
    private var canSave: Bool { frontZoneContent.hasContent || backZoneContent.hasContent }
    private var focusManager = ZoneFocusManager.shared

    // MARK: - Init
    init(searchQuery: String? = nil, onSave: @escaping (ZoneModel, ZoneModel) -> Void) {
        self.onSaveZones = onSave
        _frontZoneContent = State(initialValue: ZoneCardContent(rootZone: .text()))
        _backZoneContent = State(initialValue: ZoneCardContent(rootZone: .text()))
        
        if let query = searchQuery, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            _highlightContext = State(initialValue: HighlightContext(query: query))
        } else {
            _highlightContext = State(initialValue: nil)
        }
    }

    init(frontZone: ZoneModel, backZone: ZoneModel, searchQuery: String? = nil, onSave: @escaping (ZoneModel, ZoneModel) -> Void) {
        self.onSaveZones = onSave
        _frontZoneContent = State(initialValue: ZoneCardContent(rootZone: frontZone))
        _backZoneContent = State(initialValue: ZoneCardContent(rootZone: backZone))
        
        if let query = searchQuery, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            _highlightContext = State(initialValue: HighlightContext(query: query))
        } else {
            _highlightContext = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient.ignoresSafeArea()

                TextField("", text: $retainerText)
                    .focused($isRetainerFocused)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    sidePicker
                    Divider()
                    editorArea

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

                fabDismissOverlay

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        fabOverlay
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { _, item in addPhoto(item) }
            .fullScreenCover(isPresented: $showSketchModal) { CanvasModalView { data in addSketch(data) } }
            .onChange(of: focusManager.shouldRetainKeyboard) { _, shouldRetain in
                if shouldRetain { isRetainerFocused = true }
            }
            .fullScreenCover(isPresented: $showPreview) { ZonePreviewSheet(front: frontZoneContent, back: backZoneContent) }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedPath)

            // MARK: - Observers
            .onAppear {
                if selectedPath == nil { selectedPath = .root }
                
                // MARK: Fix - Prevent programmatic auto-focus from destroying highlight context
                if highlightContext == nil || highlightContext?.isDismissed == true {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        if let rootZoneID = currentContent.rootZone.id as UUID? {
                            ZoneFocusManager.shared.requestFocus(for: rootZoneID)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    withAnimation(.spring(response: 0.3)) { keyboardHeight = frame.height }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.spring(response: 0.3)) { keyboardHeight = 0 }
                if showPhotoPicker || showSketchModal || showFABMenu { return }
                if let path = selectedPath,
                   let zone = currentContent.zone(at: path),
                   (zone.contentType == .text || zone.contentType == .empty) {
                    selectedPath = nil
                }
            }
        }
    }

    // MARK: - Editor Area
    private var editorArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(activeSide == 0 ? "QUESTION" : "ANSWER")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.bottom, 16)

                    // Pass shared HighlightContext down to the editors
                    if activeSide == 0 {
                        ZoneEditorView(content: frontZoneContent, path: .root, selectedPath: $selectedPath, highlightContext: highlightContext)
                    } else {
                        ZoneEditorView(content: backZoneContent, path: .root, selectedPath: $selectedPath, highlightContext: highlightContext)
                    }

                    Color.clear
                        .frame(height: 100)
                        .contentShape(Rectangle())
                        .onTapGesture { addZoneAtBottom() }
                        .id("bottom")
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(cardBackground).shadow(color: shadowColor, radius: 16, y: 8))
                .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(borderColor, lineWidth: 1))
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .padding(.bottom, max((selectedPath != nil ? 80 : 100), keyboardHeight + 20))
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: selectedPath) { _, newPath in
                if let path = newPath {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.6, dampingFraction: 1.0)) {
                            proxy.scrollTo(path.id, anchor: .center)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scrollToCursor)) { _ in
                if let path = selectedPath {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(path.id)
                        }
                    }
                }
            }
            .onChange(of: keyboardHeight) { oldHeight, newHeight in
                if newHeight > oldHeight, let path = selectedPath {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { proxy.scrollTo(path.id) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UpdateCursorIndex"))) { notification in
                if let index = notification.object as? Int { self.currentCursorIndex = index }
            }
        }
    }

    private var sidePicker: some View {
        Picker("Side", selection: $activeSide) {
            Text("Question").tag(0)
            Text("Answer").tag(1)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onChange(of: activeSide) { oldSide, newSide in
            if oldSide == 0 { frontSavedPath = selectedPath }
            else { backSavedPath = selectedPath }
            executeWithKeyboardRetention {
                (newSide == 0 ? backZoneContent : frontZoneContent).cleanup()
                selectedPath = newSide == 0 ? frontSavedPath : backSavedPath
            } afterLayout: {
                // MARK: Fix - Prevent programmatic auto-focus from destroying highlight context when flipping card
                if highlightContext == nil || highlightContext?.isDismissed == true {
                    let targetContent = newSide == 0 ? frontZoneContent : backZoneContent
                    if let path = selectedPath, let zoneID = targetContent.zone(at: path)?.id {
                        ZoneFocusManager.shared.requestFocus(for: zoneID)
                    } else {
                        selectedPath = .root
                        ZoneFocusManager.shared.requestFocus(for: targetContent.rootZone.id)
                    }
                }
            }
        }
    }
    /// Robust add-zone logic that computes path immediately.
    private func addZoneWithFocus(in direction: AddDirection) {
        guard let path = selectedPath else { return }

        let parentPath = path.parent
        let childIndex = path.lastIndex ?? 0
        let parentZone = parentPath != nil ? currentContent.zone(at: parentPath!) : nil
        let parentDirection = parentZone?.direction
        let isRoot = path.indices.isEmpty

        var newZoneID: UUID?
        var newPath: ZonePath = .root

        executeWithKeyboardRetention {
            newZoneID = self.currentContent.addZone(relativeTo: path, direction: direction)

            if isRoot {
                switch direction {
                case .left, .up: newPath = ZonePath(indices: [0])
                case .right, .down: newPath = ZonePath(indices: [1])
                }
            } else if let pPath = parentPath, parentDirection == direction.zoneDirection {
                switch direction {
                case .left, .up: newPath = pPath.appending(childIndex)
                case .right, .down: newPath = pPath.appending(childIndex + 1)
                }
            } else {
                switch direction {
                case .left, .up: newPath = path.appending(0)
                case .right, .down: newPath = path.appending(1)
                }
            }
            self.selectedPath = newPath
        } afterLayout: {
            if let zoneID = newZoneID {
                ZoneFocusManager.shared.requestFocus(for: zoneID)
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func addZoneAtBottom() {
        let root = currentContent.rootZone
        var newZoneID: UUID?

        executeWithKeyboardRetention {
            if !root.isLeaf && root.direction == .vertical {
                let newIndex = root.children?.count ?? 0
                let newZone = ZoneModel.empty()
                newZoneID = newZone.id

                self.currentContent.updateZone(at: .root) { rootZone in
                    var kids = rootZone.children ?? []
                    kids.append(newZone)
                    rootZone.children = kids
                }
                self.selectedPath = ZonePath(indices: [newIndex])
            } else {
                newZoneID = self.currentContent.addZone(relativeTo: .root, direction: .down)
                self.selectedPath = ZonePath(indices: [1])
            }
        } afterLayout: {
            if let zoneID = newZoneID {
                ZoneFocusManager.shared.requestFocus(for: zoneID)
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func triggerKeyboardForNewZone(zoneID: UUID) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            ZoneFocusManager.shared.requestFocus(for: zoneID)
        }
    }

    /// Fallback when zoneID is not available.
    private func triggerKeyboardForNewZoneLegacy() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .focusNewZone, object: nil)
        }
    }

    private func addPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }

        let targetPath = selectedPath

        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let compressedData = data.compressedImageData(maxDimension: 1200, compressionQuality: 0.7) ?? data

                await MainActor.run {
                    if let path = targetPath, currentContent.zone(at: path) != nil {
                        currentContent.updateZone(at: path) { zone in
                            zone.contentType = .image
                            zone.imageData = compressedData
                        }
                    } else {
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
        let targetPath = selectedPath

        Task {

            await MainActor.run {
                if let path = targetPath, currentContent.zone(at: path) != nil {
                    currentContent.updateZone(at: path) { zone in
                        zone.contentType = .sketch
                        zone.imageData = data
                    }
                } else {
                    currentContent.addZone(relativeTo: .root, direction: .down)
                    if let children = currentContent.rootZone.children, !children.isEmpty {
                        let newPath = ZonePath(indices: [children.count - 1])
                        currentContent.updateZone(at: newPath) { zone in
                            zone.contentType = .sketch
                            zone.imageData = data
                        }
                        selectedPath = newPath
                    }
                }
            }



        }
    }

    private func splitZone() {
        guard let path = selectedPath,
            let zone = currentContent.zone(at: path),
            zone.contentType == .text else { return }

        let text = zone.text
        let lines = text.components(separatedBy: "\n")

        if lines.count >= 2 {
            executeWithKeyboardRetention {
                let midPoint = lines.count / 2
                let firstPart = lines[0..<midPoint].joined(separator: "\n")
                let secondPart = lines[midPoint...].joined(separator: "\n")

                self.currentContent.updateZone(at: path) { z in z.text = firstPart }
                self.currentContent.addZone(relativeTo: path, direction: .down)

                let newPath: ZonePath
                if let parent = path.parent {
                    newPath = parent.appending((path.lastIndex ?? 0) + 1)
                } else {
                    newPath = ZonePath(indices: [1])
                }

                self.updateSplitZoneContent(at: newPath, text: secondPart, original: zone)
                self.selectedPath = path
            } afterLayout: {
                if let topZoneID = self.currentContent.zone(at: path)?.id {
                    ZoneFocusManager.shared.requestFocus(for: topZoneID)
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            return
        }
        executeWithKeyboardRetention {
            self.currentContent.addZone(relativeTo: path, direction: .down)
        } afterLayout: {
            if let topZoneID = self.currentContent.zone(at: path)?.id {
                ZoneFocusManager.shared.requestFocus(for: topZoneID)
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func updateSplitZoneContent(at path: ZonePath, text: String, original: ZoneModel) {
        currentContent.updateZone(at: path) { z in
            z.text = text
            z.contentType = .text
            z.textStyle = original.textStyle
            z.textAlignment = original.textAlignment
            z.textColor = original.textColor
            z.isBold = original.isBold
            z.isItalic = original.isItalic
            z.hasBullet = original.hasBullet
        }
    }

    private func executeWithKeyboardRetention(action: @escaping () -> Void, afterLayout: @escaping () -> Void) {
            if keyboardHeight > 0 { focusManager.shouldRetainKeyboard = true }
            action()
            layoutTask?.cancel()
            layoutTask = Task {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    afterLayout()
                    focusManager.shouldRetainKeyboard = false
                    isRetainerFocused = false
                }
            }
        }
        
        private func hideKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }

        private var fabOverlay: some View {
            VStack(alignment: .trailing, spacing: 12) {
                if showFABMenu {
                    VStack(spacing: 8) {
                        FABMenuItem(icon: "photo", label: "Photo") { showFABMenu = false; showPhotoPicker = true }
                        FABMenuItem(icon: "scribble.variable", label: "Sketch") { showFABMenu = false; showSketchModal = true; hideKeyboard() }
                    }
                    .transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity))
                }
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { showFABMenu.toggle() }
                } label: {
                    Image(systemName: "plus").font(.title3.bold()).foregroundStyle(accent).padding(10).background(.ultraThinMaterial, in: Circle()).rotationEffect(.degrees(showFABMenu ? 135 : 0))
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, selectedPath != nil ? 65 : 30)
        }

        private var fabDismissOverlay: some View {
            Group {
                if showFABMenu {
                    Color.black.opacity(0.3).ignoresSafeArea().onTapGesture {
                        withAnimation(.spring(response: 0.3)) { showFABMenu = false }
                    }
                }
            }
        }

        @ToolbarContentBuilder
        private var toolbarContent: some ToolbarContent {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 16) {
                    Button { hideKeyboard(); showPreview = true } label: { Image(systemName: "eye") }.disabled(!canSave)
                    Button("Save") {
                        frontZoneContent.cleanup()
                        backZoneContent.cleanup()
                        onSaveZones(frontZoneContent.rootZone, backZoneContent.rootZone)
                        
                        // MARK: Architectural Fix - Persist immediately so SearchEngine sees fresh data
                        try? context.save()
                        
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }

        private var backgroundGradient: some View { LinearGradient(colors: colorScheme == .dark ? [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)] : [Color(uiColor: .systemGray6), Color(uiColor: .systemBackground)], startPoint: .top, endPoint: .bottom) }
        private var cardBackground: some ShapeStyle { colorScheme == .dark ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(Color.white) }
        private var shadowColor: Color { colorScheme == .dark ? Color.black.opacity(0.5) : Color.black.opacity(0.15) }
        private var borderColor: Color { colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08) }
    }

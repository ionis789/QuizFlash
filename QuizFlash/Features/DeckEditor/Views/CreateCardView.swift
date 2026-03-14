//
//  AddCardSheetView.swift
//  QuizFlash
//
//  Card editor with zone-based content and PURE VISUAL ghost previews.
//  NO data model mutation during drag - ghost is rendered as overlay only.
//

import SwiftUI
import PhotosUI
import SwiftData

// MARK: - Add Card Sheet View

struct CreateCardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var context

    var onSaveZones: (ZoneModel, ZoneModel) -> Void

    // MARK: - State

    @State private var highlightContext: HighlightContext?
    @State private var frontZoneContent: ZoneCardContent
    @State private var backZoneContent: ZoneCardContent
    @State private var activeSide = 0
    @State private var selectedPath: ZonePath? = .root
    @State private var focusSnapshot = FocusStateSnapshot()
    @State private var showSketchModal = false
    @State private var showPreview = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false


    // PURE VISUAL GHOST - No data mutation
    @State private var previewDirection: AddDirection? = nil

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var currentContent: ZoneCardContent { activeSide == 0 ? frontZoneContent : backZoneContent }
    private var canSave: Bool { frontZoneContent.hasContent || backZoneContent.hasContent }

    private var focusManager = ZoneFocusManager.shared
    private var zoneController = ZoneController.shared
    private var lineTracker = ZoneLineTracker.shared

    // MARK: - Initialization

    init(
        searchQuery: String? = nil,onSave: @escaping (ZoneModel, ZoneModel) -> Void
    ) {
        self.onSaveZones = onSave
        _frontZoneContent = State(initialValue: ZoneCardContent(rootZone: .text()))
        _backZoneContent = State(initialValue: ZoneCardContent(rootZone: .text()))
       
        if let query = searchQuery, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            _highlightContext = State(initialValue: HighlightContext(query: query))
        } else {
            _highlightContext = State(initialValue: nil)
        }

    }

    init(
        frontZone: ZoneModel,
        backZone: ZoneModel,
        searchQuery: String? = nil,
      
          onSave: @escaping (ZoneModel, ZoneModel) -> Void
    ) {

        self.onSaveZones = onSave
        _frontZoneContent = State(initialValue: ZoneCardContent(rootZone: frontZone))
        _backZoneContent = State(initialValue: ZoneCardContent(rootZone: backZone))

        if let query = searchQuery, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            _highlightContext = State(initialValue: HighlightContext(query: query))
        } else {
            _highlightContext = State(initialValue: nil)
        }

    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sidePicker
                Divider().background(accent.opacity(0.2))
                editorArea
            }
                .background(backgroundGradient.ignoresSafeArea())
                .safeAreaInset(edge: .bottom) {
                if let path = selectedPath {
                    formatBar(for: path)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .images)
                .onChange(of: selectedPhoto) { _, item in addPhoto(item) }
                .fullScreenCover(isPresented: $showSketchModal) { CanvasModalView { data in addSketch(data) } }
                .fullScreenSheet(
                    ignoresSafeArea: true,
                    isPresented: $showPreview,
                    backgroundReceivesDragProgress: true,
                    dragDismissActivationHeight: 180
                ) { safeArea in
                    CardPreviewModeView(
                        front: frontZoneContent,
                        back: backZoneContent,
                        safeAreaInsets: safeArea
                    )
                } background: {
                    CardPreviewModeBackground()
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedPath)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: previewDirection)
                .onAppear {
                if selectedPath == nil {
                    selectedPath = .root
                }

                // Delayed focus for initial zone
                if highlightContext == nil || highlightContext?.isDismissed == true {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        if let rootZoneID = currentContent.rootZone.id as UUID? {
                            focusManager.requestFocus(for: rootZoneID)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func formatBar(for path: ZonePath) -> some View {
        EditorFormatMenuBar(
            content: currentContent,
            path: path,
            onAddZoneAction: { direction in
                focusManager.prepareForZoneInsertion()
                addZoneWithFocus(in: direction)
            },
            onPreviewDirection: { direction in
                // PURE VISUAL - Only updates overlay state, no data mutation
                previewDirection = direction
            },
            onSplit: { splitZone() },
            onClose: {
                focusManager.forceReleaseKeyboard()
                selectedPath = nil
                previewDirection = nil
            }
        )
    }

    private var editorArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image(systemName: activeSide == 0 ? "questionmark.circle.fill" : "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(accent)
                        Text(activeSide == 0 ? "QUESTION" : "ANSWER")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                        .padding(.bottom, 16)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Pass previewDirection down for visual overlay rendering
                    ZoneEditorView(
                        content: currentContent,
                        path: .root,
                        selectedPath: $selectedPath,
                        highlightContext: highlightContext,
                        previewDirection: $previewDirection
                    )

                    Color.clear
                        .frame(height: 80)
                        .contentShape(Rectangle())
                        .onTapGesture { addZoneAtBottom() }
                        .id("bottom")
                }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(cardBackground)
                        .shadow(color: shadowColor, radius: 12, y: 6)
                )
                    .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 60)
            }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: selectedPath) { _, newPath in
                if let path = newPath {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                            proxy.scrollTo(path.id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var sidePicker: some View {
        Picker("Side", selection: $activeSide) {
            Label("Question", systemImage: "questionmark.circle").tag(0)
            Label("Answer", systemImage: "checkmark.circle").tag(1)
        }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .onChange(of: activeSide) { oldSide, newSide in
            handleSideChange(from: oldSide, to: newSide)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }.tint(.secondary)
        }
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 12) {
                Button { isPhotoPickerPresented = true }
                label: { Image(systemName: "photo.on.rectangle").font(.body.weight(.medium)) }
                    .tint(accent)

                Button { showSketchModal = true }
                label: { Image(systemName: "pencil.and.scribble").font(.body.weight(.medium)) }
                    .tint(accent)

                Divider().frame(height: 24)

                Button { showPreview = true }
                label: { Image(systemName: "eye").font(.body.weight(.medium)) }
                    .disabled(!canSave)

                Button("Save") { saveCard() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
    }

    // MARK: - Side Change Handling

    private func handleSideChange(from oldSide: Int, to newSide: Int) {
        if let path = selectedPath, let zone = currentContent.zone(at: path) {
            focusSnapshot.saveForSide(oldSide, zoneID: zone.id, path: path)
        }

        focusManager.retainFocusForTransition()
        zoneController.retainFocusDuringTransition()

        if newSide == 0 {
            backZoneContent.cleanup()
        } else {
            frontZoneContent.cleanup()
        }

        zoneController.setActiveSide(newSide)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let targetContent = newSide == 0 ? frontZoneContent : backZoneContent
            let restored = focusSnapshot.restoreForSide(newSide)

            if let zoneID = restored.zoneID,
                let path = restored.path,
                targetContent.zone(at: path) != nil {
                selectedPath = path
                focusManager.requestFocus(for: zoneID)
            } else {
                selectedPath = .root
                focusManager.requestFocus(for: targetContent.rootZone.id)
            }

            focusManager.releaseFocusAfterTransition()
            zoneController.releaseFocusAfterTransition()
        }
    }

    // MARK: - Zone Operations (NO GHOST LOGIC)

    private func addZoneWithFocus(in direction: AddDirection) {
        guard let path = selectedPath else { return }

        var newZoneID: UUID?
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            newZoneID = currentContent.addZone(relativeTo: path, direction: direction)
            if let newID = newZoneID, let p = findPath(for: newID, in: currentContent.rootZone) {
                selectedPath = p
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let id = newZoneID {
                focusManager.requestFocus(for: id)
            }
            focusManager.releaseKeyboardRetention(afterDelay: 0.1)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func splitZone() {
        guard let path = selectedPath,
            let zone = currentContent.zone(at: path),
            zone.contentType == .text,
            let zoneID = zone.id as UUID? else { return }

        let heightInfo = zoneController.zoneHeightInfo(for: zoneID)
        let lines = zone.text.components(separatedBy: "\n")
        guard lines.count >= 2 else { return }

        let focusedLineIndex = heightInfo?.focusedLineIndex ?? 0
        guard focusedLineIndex >= 0 && focusedLineIndex < lines.count - 1 else { return }

        let splitResult = zone.text.splitAtLine(focusedLineIndex)
        focusManager.prepareForZoneInsertion()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentContent.updateZone(at: path) { z in
                z.text = splitResult.before
            }

            let newID = currentContent.addZone(relativeTo: path, direction: .down)
            if let newPath = findPath(for: newID, in: currentContent.rootZone) {
                currentContent.updateZone(at: newPath) { z in
                    z.text = splitResult.after
                    z.contentType = .text
                    z.textStyle = zone.textStyle
                    z.textAlignment = zone.textAlignment
                    z.textColor = zone.textColor
                    z.isBold = zone.isBold
                    z.isItalic = zone.isItalic
                    z.hasBullet = zone.hasBullet
                    z.fontFamily = zone.fontFamily
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusManager.requestFocus(for: zoneID) // Focus stays on TOP zone
            focusManager.releaseKeyboardRetention(afterDelay: 0.1)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func addZoneAtBottom() {
        let root = currentContent.rootZone
        var newZoneID: UUID?

        focusManager.prepareForZoneInsertion()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if !root.isLeaf && root.direction == .vertical {
                let newIndex = root.children?.count ?? 0
                let newZone = ZoneModel.empty()
                newZoneID = newZone.id

                currentContent.updateZone(at: .root) { rootZone in
                    var kids = rootZone.children ?? []
                    kids.append(newZone)
                    rootZone.children = kids
                }
                selectedPath = ZonePath(indices: [newIndex])
            } else {
                newZoneID = currentContent.addZone(relativeTo: .root, direction: .down)
                selectedPath = ZonePath(indices: [1])
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let id = newZoneID {
                focusManager.requestFocus(for: id)
            }
            focusManager.releaseKeyboardRetention()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    // MARK: - Photo/Sketch

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

    // MARK: - Save

    private func saveCard() {
        frontZoneContent.cleanup()
        backZoneContent.cleanup()
        onSaveZones(frontZoneContent.rootZone, backZoneContent.rootZone)
        try? context.save()
        focusManager.forceReleaseKeyboard()
        lineTracker.clearAll()
        zoneController.clearHeightCache()
        dismiss()
    }

    // MARK: - Helpers

    private func findPath(for id: UUID, in zone: ZoneModel, currentIndices: [Int] = []) -> ZonePath? {
        if zone.id == id { return ZonePath(indices: currentIndices) }
        guard let kids = zone.children else { return nil }
        for (index, child) in kids.enumerated() {
            if let found = findPath(for: id, in: child, currentIndices: currentIndices + [index]) {
                return found
            }
        }
        return nil
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)]
            : [Color(uiColor: .systemGray6), Color(uiColor: .systemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
        : AnyShapeStyle(Color.white)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.5) : Color.black.opacity(0.12)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
    }
}

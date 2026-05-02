//
//  FlashcardEditorView.swift
//  QuizFlash
//
//  Zone-based flashcard editor for manual front/back authoring.
//  Drag previews are visual only and do not mutate the card model.
//

import SwiftUI
import PhotosUI
import SwiftData
import OSLog

// MARK: - Flashcard Editor View

struct FlashcardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(KeyboardMonitor.self) private var keyboardMonitor

    var onSaveZones: (ZoneModel, ZoneModel) -> Void
    private let contentAlignment: FlashcardContentAlignment

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
    @State private var scheduledFocusTask: Task<Void, Never>?
    @State private var showSaveErrorAlert = false
    @State private var saveErrorMessage = ""


    // Visual-only ghost preview. The model changes only after the user commits.
    @State private var previewDirection: AddDirection? = nil

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var currentContent: ZoneCardContent { activeSide == 0 ? frontZoneContent : backZoneContent }
    private var canSave: Bool { frontZoneContent.hasContent || backZoneContent.hasContent }
    private var locale: Locale { appPreferences.resolvedLocale }
    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var topChromeHorizontalInset: CGFloat {
        isCompact ? UIConstants.Layout.compactScreenEdgeInset : UIConstants.Layout.screenEdgeInset
    }
    private var editorTextScale: CGFloat { CGFloat(FlashcardTextSize.large.playModeScale) }
    private var verticalAlignmentFallback: ZoneVerticalAlignment {
        ZoneVerticalAlignment(fallbackContentAlignment: contentAlignment)
    }
    private var canUseInteractiveDismiss: Bool {
        !showSketchModal && !showPreview && !isPhotoPickerPresented
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private var focusManager = ZoneFocusManager.shared
    private var zoneController = ZoneController.shared
    private var lineTracker = ZoneLineTracker.shared
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuizFlash",
        category: "FlashcardEditorView"
    )

    // MARK: - Initialization

    init(
        searchQuery: String? = nil,
        contentAlignment: FlashcardContentAlignment = .center,
        onSave: @escaping (ZoneModel, ZoneModel) -> Void
    ) {
        self.onSaveZones = onSave
        self.contentAlignment = contentAlignment
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
        contentAlignment: FlashcardContentAlignment = .center,
        onSave: @escaping (ZoneModel, ZoneModel) -> Void
    ) {

        self.onSaveZones = onSave
        self.contentAlignment = contentAlignment
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
        ZStack(alignment: .top) {
            editorBackground.ignoresSafeArea()

            VStack(spacing: UIConstants.Spacing.small) {
                topChrome
                editorArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            floatingFormatBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, item in addPhoto(item) }
        .fullScreenCover(isPresented: $showSketchModal) { CanvasModalView { data in addSketch(data) } }
        .fullScreenSheet(
            isPresented: $showPreview,
            configuration: .sheet(showsDefaultTopProgressiveBlur: false)
        ) { safeArea in
            CardPreviewModeView(
                front: frontZoneContent,
                back: backZoneContent,
                safeAreaInsets: safeArea,
                contentAlignment: contentAlignment
            )
        } background: {
            CardPreviewModeBackground()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedPath)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: previewDirection)
        .swipeBack(enabled: canUseInteractiveDismiss) {
            dismiss()
        }
        .alert(localized("Save Error"), isPresented: $showSaveErrorAlert) {
            Button(localized("OK"), role: .cancel) { }
        } message: {
            Text(saveErrorMessage.isEmpty ? localized("Your card changes couldn't be saved right now.") : saveErrorMessage)
        }
        .onAppear {
            if selectedPath == nil {
                selectedPath = .root
            }
            focusManager.forceReleaseKeyboard()
        }
        .onDisappear {
            cancelScheduledEditorTasks()
        }
    }

    @ViewBuilder
    private var floatingFormatBar: some View {
        if let path = selectedPath {
            VStack {
                Spacer(minLength: 0)
                formatBar(for: path)
                    .padding(.horizontal, topChromeHorizontalInset)
                    .padding(.bottom, floatingToolbarBottomInset)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(30)
        }
    }

    private var floatingToolbarBottomInset: CGFloat {
        let base = UIConstants.Spacing.standard
        guard keyboardMonitor.isVisible else {
            return base
        }

        return keyboardMonitor.visibleHeight + base
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
            onDuplicate: { duplicateSelectedZone() },
            onMoveUp: { moveSelectedZoneUp() },
            onMoveDown: { moveSelectedZoneDown() },
            onChoosePhoto: {
                isPhotoPickerPresented = true
            },
            onSketch: {
                showSketchModal = true
            },
            canPreview: canSave,
            onPreview: {
                openPreview()
            },
            onClose: {
                focusManager.forceReleaseKeyboard()
                selectedPath = nil
                previewDirection = nil
            }
        )
    }

    private var editorArea: some View {
        ZoneEditorCanvas(
            content: currentContent,
            selectedPath: $selectedPath,
            previewDirection: $previewDirection,
            highlightContext: highlightContext,
            fontScale: editorTextScale,
            verticalAlignmentFallback: verticalAlignmentFallback,
            onEmptySpaceTap: handleCanvasEmptySpaceTap
        )
    }

    private func handleCanvasEmptySpaceTap(_ context: ZoneEditorCanvasTapContext) {
        focusManager.prepareForZoneInsertion()

        if !currentContent.rootZone.hasContent, currentContent.rootZone.isLeaf {
            selectedPath = .root
            currentContent.updateZone(at: .root) { zone in
                zone.contentType = .text
                zone.sizeMode = .auto
                zone.blockAlignment = .auto
                zone.textAlignment = .leading
            }
            scheduleFocusAction(after: .milliseconds(80)) {
                focusManager.requestFocus(for: currentContent.rootZone.id)
                focusManager.releaseKeyboardRetention(afterDelay: 0.1)
            }
            return
        }

        let insertion = insertionPoint(for: context)
        insertTextZoneWithFocus(relativeTo: insertion.path, direction: insertion.direction)
    }

    private func insertionPoint(for context: ZoneEditorCanvasTapContext) -> (path: ZonePath, direction: AddDirection) {
        let sortedFrames = context.zoneFrames
            .filter { currentContent.zone(at: $0.path) != nil }
            .sorted {
                if abs($0.frame.midY - $1.frame.midY) > 1 {
                    return $0.frame.midY < $1.frame.midY
                }
                return $0.frame.midX < $1.frame.midX
            }

        guard let first = sortedFrames.first else {
            return (.root, .down)
        }

        if context.location.y < first.frame.midY {
            return (first.path, .up)
        }

        if let horizontalInsertion = horizontalInsertionPoint(for: context.location, in: sortedFrames) {
            return horizontalInsertion
        }

        for frame in sortedFrames {
            if context.location.y < frame.frame.midY {
                return (frame.path, .up)
            }
        }

        return (sortedFrames.last?.path ?? .root, .down)
    }

    private func horizontalInsertionPoint(
        for location: CGPoint,
        in frames: [ZoneEditorResolvedZoneFrame]
    ) -> (path: ZonePath, direction: AddDirection)? {
        let verticalTolerance: CGFloat = 10
        let candidates = frames.filter {
            location.y >= $0.frame.minY - verticalTolerance
                && location.y <= $0.frame.maxY + verticalTolerance
        }

        guard let nearest = candidates.min(by: {
            abs($0.frame.midY - location.y) < abs($1.frame.midY - location.y)
        }) else {
            return nil
        }

        if location.x < nearest.frame.minX {
            return (nearest.path, .left)
        }

        if location.x > nearest.frame.maxX {
            return (nearest.path, .right)
        }

        return nil
    }

    private func insertTextZoneWithFocus(relativeTo path: ZonePath?, direction: AddDirection) {
        var newZoneID: UUID?

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            newZoneID = currentContent.addTextZone(relativeTo: path, direction: direction)
            if let newID = newZoneID, let newPath = findPath(for: newID, in: currentContent.rootZone) {
                selectedPath = newPath
            }
        }

        scheduleFocusAction(after: .milliseconds(150)) {
            if let id = newZoneID {
                focusManager.requestFocus(for: id)
            }
            focusManager.releaseKeyboardRetention(afterDelay: 0.1)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func scheduleFocusAction(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        scheduledFocusTask?.cancel()
        scheduledFocusTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    private func cancelScheduledEditorTasks() {
        scheduledFocusTask?.cancel()
        scheduledFocusTask = nil
    }

    private var topChrome: some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
            ChromeSoftCircleSymbolButton(
                systemName: "xmark",
                accessibilityLabel: localized("Cancel"),
                action: closeEditor,
                size: UIConstants.Size.actionButton
            )

            Spacer(minLength: 0)

            sideSwitch

            Spacer(minLength: 0)

            Button(action: saveCard) {
                ChromeSoftCircleSymbol(
                    systemName: "checkmark",
                    size: UIConstants.Size.actionButton,
                    symbolSize: 24,
                    tint: canSave ? .white : .secondary,
                    backgroundTint: canSave ? accent : Color(uiColor: .tertiarySystemFill)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.55)
            .accessibilityLabel(localized("Save"))
        }
        .topNavigationChrome(horizontalInset: topChromeHorizontalInset)
    }

    private var sideSwitch: some View {
        HStack(spacing: 0) {
            sideSwitchButton(title: localized("Question"), side: 0)
            sideSwitchButton(title: localized("Answer"), side: 1)
        }
        .padding(3)
        .frame(width: isCompact ? 218 : 244, height: 42)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.72))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.45), lineWidth: 0.7)
        )
    }

    private func sideSwitchButton(title: String, side: Int) -> some View {
        Button {
            guard activeSide != side else { return }
            let oldSide = activeSide
            activeSide = side
            handleSideChange(from: oldSide, to: side)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(activeSide == side ? .primary : .secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if activeSide == side {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.95))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func openPreview() {
        guard canSave else { return }
        focusManager.forceReleaseKeyboard()
        selectedPath = nil
        previewDirection = nil
        showPreview = true
    }

    private func closeEditor() {
        focusManager.forceReleaseKeyboard()
        dismiss()
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

        scheduleFocusAction(after: .milliseconds(150)) {
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
        insertTextZoneWithFocus(relativeTo: path, direction: direction)
    }

    private func duplicateSelectedZone() {
        guard let path = selectedPath else { return }

        var newZoneID: UUID?
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            newZoneID = currentContent.duplicateZone(at: path)
            if let newID = newZoneID,
               let newPath = findPath(for: newID, in: currentContent.rootZone) {
                selectedPath = newPath
            }
        }

        scheduleFocusAction(after: .milliseconds(120)) {
            if let id = newZoneID {
                focusManager.requestFocus(for: id)
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func moveSelectedZoneUp() {
        guard let path = selectedPath else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if let newPath = currentContent.moveZoneUp(at: path) {
                selectedPath = newPath
            }
        }
    }

    private func moveSelectedZoneDown() {
        guard let path = selectedPath else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if let newPath = currentContent.moveZoneDown(at: path) {
                selectedPath = newPath
            }
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
                    z.sizeMode = zone.sizeMode
                    z.blockAlignment = zone.blockAlignment
                    z.fixedWidth = zone.fixedWidth
                    z.fixedHeight = zone.fixedHeight
                    z.textColor = zone.textColor
                    z.isBold = zone.isBold
                    z.isItalic = zone.isItalic
                    z.hasBullet = zone.hasBullet
                    z.fontFamily = zone.fontFamily
                }
            }
        }

        scheduleFocusAction(after: .milliseconds(100)) {
            focusManager.requestFocus(for: zoneID) // Focus stays on TOP zone
            focusManager.releaseKeyboardRetention(afterDelay: 0.1)
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
        do {
            try context.save()
        } catch {
            Self.logger.error(
                "Failed to save card editor changes: \(error.localizedDescription, privacy: .public)"
            )
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
            return
        }
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

    private var editorBackground: Color {
        colorScheme == .dark ? .black : Color(uiColor: .systemGray6)
    }

}

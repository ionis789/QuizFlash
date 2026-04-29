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
    @State private var scheduledFocusTask: Task<Void, Never>?
    @State private var scheduledScrollTask: Task<Void, Never>?
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
    private var editorCardCornerRadius: CGFloat { isCompact ? 42 : 52 }
    private var editorCardHorizontalPadding: CGFloat { isCompact ? 20 : 28 }
    private var editorCardVerticalPadding: CGFloat { isCompact ? 20 : 24 }
    private var editorTextScale: CGFloat { CGFloat(FlashcardTextSize.large.playModeScale) }
    private static let playModeCardAspectRatio: CGFloat = 369.0 / 613.0
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
        onSave: @escaping (ZoneModel, ZoneModel) -> Void
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
        ZStack(alignment: .top) {
            editorBackground.ignoresSafeArea()

            VStack(spacing: UIConstants.Spacing.medium) {
                topChrome
                sideSwitch
                editorArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .safeAreaInset(edge: .bottom) {
                if let path = selectedPath {
                    formatBar(for: path)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
                safeAreaInsets: safeArea
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

            // Delayed focus for initial zone.
            if highlightContext == nil || highlightContext?.isDismissed == true {
                scheduleFocusAction(after: .milliseconds(400)) {
                    if let rootZoneID = currentContent.rootZone.id as UUID? {
                        focusManager.requestFocus(for: rootZoneID)
                    }
                }
            }
        }
        .onDisappear {
            cancelScheduledEditorTasks()
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
        GeometryReader { geometry in
            let horizontalInset: CGFloat = 20
            let maxEditorWidth: CGFloat = isCompact ? .infinity : 620
            let proposedWidth = max(geometry.size.width - (horizontalInset * 2), 1)
            let cardWidth = min(proposedWidth, maxEditorWidth)
            let cardHeight = cardWidth / Self.playModeCardAspectRatio
            let contentWidth = max(cardWidth - (editorCardHorizontalPadding * 2), 1)
            let contentHeight = max(cardHeight - (editorCardVerticalPadding * 2), 1)
            let estimatedContentSize = FlashcardGridContentEstimator.estimatedSize(
                for: currentContent.rootZone,
                fontScale: editorTextScale,
                availableWidth: contentWidth
            )
            let editorContentWidth = editorBlockWidth(
                estimatedWidth: estimatedContentSize.width,
                availableWidth: contentWidth
            )
            let contentFitsVertically = estimatedContentSize.height <= contentHeight
            let contentFrameAlignment: Alignment = contentFitsVertically ? .center : .top

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .center, spacing: 0) {
                        // Pass previewDirection down for visual overlay rendering.
                        ZoneEditorView(
                            content: currentContent,
                            path: .root,
                            selectedPath: $selectedPath,
                            highlightContext: highlightContext,
                            fontScale: editorTextScale,
                            previewDirection: $previewDirection
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: editorContentWidth, alignment: .center)
                    }
                    .padding(.horizontal, editorCardHorizontalPadding)
                    .padding(.vertical, editorCardVerticalPadding)
                    .frame(width: cardWidth, alignment: .topLeading)
                    .frame(minHeight: cardHeight, alignment: contentFrameAlignment)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedPath == nil {
                            selectedPath = .root
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: editorCardCornerRadius, style: .continuous)
                        .fill(cardBackground)
                        .shadow(color: shadowColor, radius: 12, y: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: editorCardCornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: editorCardCornerRadius, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, horizontalInset)
                .padding(.top, 16)
                .padding(.bottom, 60)
                .onChange(of: selectedPath) { _, newPath in
                    if let path = newPath {
                        scheduleSelectionScroll(after: .milliseconds(100), to: path, in: proxy)
                    }
                }
            }
        }
    }

    private func editorBlockWidth(estimatedWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        guard currentContent.rootZone.hasContent else { return availableWidth }
        let minimumComfortWidth = min(availableWidth, isCompact ? 220 : 280)
        return min(max(ceil(estimatedWidth), minimumComfortWidth), availableWidth)
    }

    private func scheduleSelectionScroll(after delay: Duration, to path: ZonePath, in proxy: ScrollViewProxy) {
        scheduledScrollTask?.cancel()
        scheduledScrollTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                proxy.scrollTo(path.id, anchor: .center)
            }
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
        scheduledScrollTask?.cancel()
        scheduledFocusTask = nil
        scheduledScrollTask = nil
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

            HStack(spacing: UIConstants.Spacing.small) {
                topActionButton(
                    systemName: "photo.on.rectangle",
                    accessibilityLabel: localized("Choose Photos"),
                    isEnabled: true
                ) {
                    isPhotoPickerPresented = true
                }

                topActionButton(
                    systemName: "pencil.and.scribble",
                    accessibilityLabel: localized("Sketch"),
                    isEnabled: true
                ) {
                    showSketchModal = true
                }

                topActionButton(
                    systemName: "eye",
                    accessibilityLabel: localized("Preview"),
                    isEnabled: canSave
                ) {
                    openPreview()
                }

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
        }
        .topNavigationChrome(horizontalInset: topChromeHorizontalInset)
    }

    private func topActionButton(
        systemName: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ChromeSoftCircleSymbol(
                systemName: systemName,
                size: UIConstants.Size.actionButton,
                symbolSize: 22,
                tint: isEnabled ? accent : .secondary,
                backgroundTint: Color(uiColor: .tertiarySystemFill)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(accessibilityLabel)
    }

    private var sideSwitch: some View {
        HStack(spacing: 0) {
            sideSwitchButton(title: localized("Question"), side: 0)
            sideSwitchButton(title: localized("Answer"), side: 1)
        }
        .padding(4)
        .frame(height: 62)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.72))
        )
        .padding(.horizontal, topChromeHorizontalInset)
    }

    private func sideSwitchButton(title: String, side: Int) -> some View {
        Button {
            guard activeSide != side else { return }
            let oldSide = activeSide
            activeSide = side
            handleSideChange(from: oldSide, to: side)
        } label: {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
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

        var newZoneID: UUID?
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            newZoneID = currentContent.addZone(relativeTo: path, direction: direction)
            if let newID = newZoneID, let p = findPath(for: newID, in: currentContent.rootZone) {
                selectedPath = p
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

        scheduleFocusAction(after: .milliseconds(100)) {
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

        scheduleFocusAction(after: .milliseconds(150)) {
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

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(red: 0.068, green: 0.068, blue: 0.068))
            : AnyShapeStyle(Color(red: 0.92, green: 0.92, blue: 0.91))
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.42) : Color.black.opacity(0.12)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.08)
    }
}

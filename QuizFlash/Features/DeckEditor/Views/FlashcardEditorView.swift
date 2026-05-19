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
import UIKit

// MARK: - Flashcard Editor View

struct FlashcardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(DevelopmentPreferences.self) private var developmentPreferences
    @Environment(KeyboardMonitor.self) private var keyboardMonitor

    var onSaveZones: (ZoneModel, ZoneModel) -> Void
    private let contentAlignment: FlashcardContentAlignment
    private let textSize: FlashcardTextSize

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
    @State private var floatingFormatBarTopY: CGFloat?
    @State private var floatingFormatBarTopUpdateCount = 0
    @State private var floatingFormatBarKeyboardHeight: CGFloat = 0
    @State private var isFloatingFormatBarPresented = false
    @State private var floatingFormatBarPresentationTask: Task<Void, Never>?
    @State private var keyboardDebugRevision = 0
    @State private var toolbarVisibilityDebugRevision = 0


    // Visual-only ghost preview. The model changes only after the user commits.
    @State private var previewDirection: AddDirection? = nil

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var currentContent: ZoneCardContent { activeSide == 0 ? frontZoneContent : backZoneContent }
    private var canSave: Bool { frontZoneContent.hasContent || backZoneContent.hasContent }
    private var locale: Locale { appPreferences.resolvedLocale }
    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var topChromeActionSize: CGFloat { isCompact ? 40 : 44 }
    private var topChromeHorizontalInset: CGFloat {
        isCompact ? UIConstants.Layout.compactScreenEdgeInset : UIConstants.Layout.screenEdgeInset
    }
    private var editorTextScale: CGFloat {
        CGFloat(textSize.playModeScale) * appPreferences.cardContentFontScale
    }
    private var verticalAlignmentFallback: ZoneVerticalAlignment {
        ZoneVerticalAlignment(fallbackContentAlignment: contentAlignment)
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
        textSize: FlashcardTextSize = .large,
        onSave: @escaping (ZoneModel, ZoneModel) -> Void
    ) {
        self.onSaveZones = onSave
        self.contentAlignment = contentAlignment
        self.textSize = textSize
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
        textSize: FlashcardTextSize = .large,
        onSave: @escaping (ZoneModel, ZoneModel) -> Void
    ) {

        self.onSaveZones = onSave
        self.contentAlignment = contentAlignment
        self.textSize = textSize
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
            floatingFormatBarDebugOverlay
        }
        .toolbar(.hidden, for: .navigationBar)
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, item in addPhoto(item) }
        .onChange(of: keyboardMonitor.isVisible) { _, isVisible in
            keyboardDebugRevision += 1
            toolbarVisibilityDebugRevision += 1
            updateFloatingFormatBarPresentation(isKeyboardVisible: isVisible)
            updateToolbarDebugLine()
        }
        .onChange(of: keyboardMonitor.visibleHeight) { _, _ in
            updateFloatingFormatBarKeyboardHeight()
            updateToolbarDebugLine()
        }
        .fullScreenCover(isPresented: $showSketchModal) { CanvasModalView { data in addSketch(data) } }
        .fullScreenSheet(
            isPresented: $showPreview,
            configuration: .sheet(
                heightMode: .fullScreen,
                showsDefaultTopProgressiveBlur: false
            )
        ) { safeArea in
            CardPreviewModeView(
                front: frontZoneContent,
                back: backZoneContent,
                safeAreaInsets: safeArea,
                contentAlignment: contentAlignment,
                textSize: textSize
            )
        } background: {
            Color.clear
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: previewDirection)
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
        ZStack {
            if let path = formatBarPath {
                VStack {
                    Spacer(minLength: 0)

                    formatBar(for: path)
                        .padding(.vertical, 4)
                        .padding(.horizontal, isCompact ? 16 : topChromeHorizontalInset)
                        .padding(.bottom, floatingToolbarBaseBottomInset)
                        .offset(y: floatingFormatBarYOffset)
                        .bottomChromeVisibility(
                            isFloatingFormatBarVisible,
                            hiddenOffset: floatingFormatBarHiddenOffset
                        )
                        .accessibilityHidden(!isFloatingFormatBarVisible)
                        .background {
                            if isFloatingFormatBarVisible {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: FloatingFormatBarTopPreferenceKey.self,
                                        value: proxy.frame(in: .global).minY
                                    )
                                }
                            }
                        }
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .onPreferenceChange(FloatingFormatBarTopPreferenceKey.self) { topY in
                    handleFloatingFormatBarTopChange(topY)
                }
            }
        }
        .zIndex(30)
    }

    private var isFloatingFormatBarVisible: Bool {
        isFloatingFormatBarPresented
    }

    private var floatingFormatBarScale: CGFloat {
        isFloatingFormatBarVisible ? 1 : 0.98
    }

    private var floatingFormatBarOpacity: Double {
        isFloatingFormatBarVisible ? 1 : 0
    }

    private var floatingFormatBarHiddenOffset: CGFloat {
        80
    }

    private var formatBarPath: ZonePath? {
        if let selectedPath, currentContent.zone(at: selectedPath) != nil {
            return selectedPath
        }

        return firstLeafPath(in: currentContent.rootZone, currentPath: .root) ?? .root
    }

    private func firstLeafPath(in zone: ZoneModel, currentPath: ZonePath) -> ZonePath? {
        guard !zone.isLeaf else { return currentPath }
        guard let children = zone.children else { return nil }

        for (index, child) in children.enumerated() {
            if let path = firstLeafPath(in: child, currentPath: currentPath.appending(index)) {
                return path
            }
        }

        return nil
    }

    private var floatingToolbarBaseBottomInset: CGFloat {
        keyboardMonitor.isVisible || isFloatingFormatBarPresented
            ? 4
            : UIConstants.Spacing.standard
    }

    private var floatingFormatBarYOffset: CGFloat {
        -floatingFormatBarKeyboardHeight
    }

    private var floatingFormatBarRenderedTopY: CGFloat? {
        floatingFormatBarTopY.map { $0 + floatingFormatBarYOffset }
    }

    private var floatingToolbarAccessoryHeight: CGFloat {
        isFloatingFormatBarVisible ? 76 : 0
    }

    @ViewBuilder
    private var floatingFormatBarDebugOverlay: some View {
        if showsEditorPerformanceDebug {
            VStack {
                HStack {
                    Spacer(minLength: 0)
                    EditorToolbarPerformanceOverlay(snapshot: toolbarPerformanceSnapshot)
                        .frame(width: 214, height: 92)
                        .padding(.top, 58)
                        .padding(.trailing, 12)
                }
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)
            .zIndex(40)
        }
    }

    private var showsEditorPerformanceDebug: Bool {
        AppFeatures.current.showsVisualDebugOverlays
            && developmentPreferences.zoneEditorDebugHUDEnabled
    }

    private var toolbarPerformanceSnapshot: EditorToolbarPerformanceOverlay.Snapshot {
        EditorToolbarPerformanceOverlay.Snapshot(
            keyboardVisible: keyboardMonitor.isVisible,
            keyboardHeight: keyboardMonitor.visibleHeight,
            keyboardDuration: keyboardMonitor.animationDuration,
            toolbarVisible: isFloatingFormatBarVisible,
            toolbarTopY: floatingFormatBarTopY,
            toolbarScale: floatingFormatBarScale,
            toolbarOpacity: floatingFormatBarOpacity,
            topUpdateCount: floatingFormatBarTopUpdateCount,
            keyboardRevision: keyboardDebugRevision,
            toolbarRevision: toolbarVisibilityDebugRevision,
            pathID: formatBarPath?.id ?? "nil"
        )
    }

    private func handleFloatingFormatBarTopChange(_ topY: CGFloat?) {
        guard isFloatingFormatBarVisible else { return }
        guard let topY else { return }

        if let floatingFormatBarTopY, abs(floatingFormatBarTopY - topY) < 0.5 {
            return
        }

        floatingFormatBarTopY = topY
        floatingFormatBarTopUpdateCount += 1
        updateToolbarDebugLine()
    }

    private func updateFloatingFormatBarPresentation(isKeyboardVisible: Bool) {
        floatingFormatBarPresentationTask?.cancel()

        if isKeyboardVisible {
            updateFloatingFormatBarKeyboardHeight()
            floatingFormatBarPresentationTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled, keyboardMonitor.isVisible else { return }
                withBottomChromeAnimation {
                    isFloatingFormatBarPresented = true
                }
                updateToolbarDebugLine()
            }
        } else {
            withBottomChromeAnimation {
                isFloatingFormatBarPresented = false
                floatingFormatBarKeyboardHeight = 0
            }
            floatingFormatBarTopY = nil

            floatingFormatBarPresentationTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled, !keyboardMonitor.isVisible else { return }
                updateToolbarDebugLine()
            }
        }
    }

    private func updateFloatingFormatBarKeyboardHeight() {
        guard keyboardMonitor.isVisible else { return }
        let height = keyboardMonitor.visibleHeight
        guard abs(floatingFormatBarKeyboardHeight - height) > 0.5 else { return }

        withTransaction(Transaction(animation: nil)) {
            floatingFormatBarKeyboardHeight = height
        }
    }

    private func updateToolbarDebugLine() {
        guard AppFeatures.current.showsVisualDebugOverlays else { return }

        ZoneEditorDebugStore.shared.updateToolbar(
            isVisible: isFloatingFormatBarVisible,
            keyboardHeight: keyboardMonitor.visibleHeight,
            toolbarTopY: floatingFormatBarTopY,
            toolbarScale: floatingFormatBarScale,
            toolbarOpacity: floatingFormatBarOpacity,
            topUpdateCount: floatingFormatBarTopUpdateCount
        )
    }

    @ViewBuilder
    private func formatBar(for path: ZonePath) -> some View {
        EditorFormatMenuBar(
            content: currentContent,
            path: path,
            onChoosePhoto: {
                isPhotoPickerPresented = true
            },
            onSketch: {
                showSketchModal = true
            },
            canPreview: canSave,
            showsPrimaryActions: false,
            onPreview: {
                openPreview()
            },
            onClose: {
                focusManager.forceReleaseKeyboard()
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
            bottomAccessoryHeight: floatingToolbarAccessoryHeight,
            bottomAccessoryTopY: keyboardMonitor.isVisible ? floatingFormatBarRenderedTopY : nil,
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

        if let emptyPath = blockingEmptyTextZonePath(
            relativeTo: insertion.path,
            direction: insertion.direction
        ),
           let emptyZone = currentContent.zone(at: emptyPath) {
            selectedPath = emptyPath
            scheduleFocusAction(after: .milliseconds(80)) {
                focusManager.requestFocus(for: emptyZone.id)
                focusManager.releaseKeyboardRetention(afterDelay: 0.1)
            }
            return
        }

        insertTextZoneWithFocus(relativeTo: insertion.path, direction: insertion.direction)
    }

    private func blockingEmptyTextZonePath(
        relativeTo path: ZonePath,
        direction: AddDirection
    ) -> ZonePath? {
        if isEmptyTextZone(at: path) {
            return path
        }

        guard let siblingPath = siblingPath(adjacentTo: path, direction: direction),
              isEmptyTextZone(at: siblingPath) else {
            return nil
        }

        return siblingPath
    }

    private func siblingPath(adjacentTo path: ZonePath, direction: AddDirection) -> ZonePath? {
        guard let parentPath = path.parent,
              let childIndex = path.lastIndex,
              let siblingCount = currentContent.zone(at: parentPath)?.children?.count else {
            return nil
        }

        let siblingIndex: Int
        switch direction {
        case .up:
            siblingIndex = childIndex - 1
        case .down:
            siblingIndex = childIndex + 1
        }

        guard siblingIndex >= 0, siblingIndex < siblingCount else {
            return nil
        }

        return ZonePath(indices: parentPath.indices + [siblingIndex])
    }

    private func isEmptyTextZone(at path: ZonePath) -> Bool {
        guard let zone = currentContent.zone(at: path),
              zone.isLeaf,
              zone.contentType == .text || zone.contentType == .empty || zone.contentType == .code else {
            return false
        }

        return zone.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func insertZoneFromToolbar(relativeTo path: ZonePath, direction: AddDirection) {
        focusManager.prepareForZoneInsertion()

        if let emptyPath = blockingEmptyTextZonePath(relativeTo: path, direction: direction),
           let emptyZone = currentContent.zone(at: emptyPath) {
            selectedPath = emptyPath
            scheduleFocusAction(after: .milliseconds(80)) {
                focusManager.requestFocus(for: emptyZone.id)
                focusManager.releaseKeyboardRetention(afterDelay: 0.1)
            }
            return
        }

        insertTextZoneWithFocus(relativeTo: path, direction: direction)
    }

    private func setSelectedZoneAutoSize(at path: ZonePath) {
        selectedPath = path
        currentContent.updateZone(at: path) {
            $0.sizeMode = .auto
            if $0.blockAlignment == .center {
                $0.blockAlignment = .auto
            }
            $0.fixedWidth = nil
            $0.fixedHeight = nil
        }
    }

    private func setSelectedZoneFillWidth(at path: ZonePath) {
        selectedPath = path
        currentContent.updateZone(at: path) {
            if $0.contentType == .image || $0.contentType == .sketch {
                $0.imageScale = 1
                $0.sizeMode = .auto
                $0.fixedWidth = nil
                $0.fixedHeight = nil
                return
            }

            $0.sizeMode = .fillWidth
            $0.blockAlignment = .leading
            $0.fixedWidth = nil
            $0.fixedHeight = nil
        }
    }

    private func setSelectedZoneBlockAlignment(_ alignment: ZoneBlockAlignment, at path: ZonePath) {
        selectedPath = path
        currentContent.updateZone(at: path) {
            if $0.sizeMode == .fillWidth {
                $0.sizeMode = .auto
                $0.fixedWidth = nil
                $0.fixedHeight = nil
            }
            $0.blockAlignment = alignment
        }
    }

    private func setCardVerticalAlignment(_ alignment: ZoneVerticalAlignment) {
        currentContent.updateZone(at: .root) {
            $0.verticalAlignment = alignment
        }
    }

    private func deleteSelectedZone(at path: ZonePath) {
        currentContent.deleteZone(at: path)
        focusManager.forceReleaseKeyboard()
        selectedPath = nil
        previewDirection = nil
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

        for frame in sortedFrames {
            if context.location.y < frame.frame.midY {
                return (frame.path, .up)
            }
        }

        return (sortedFrames.last?.path ?? .root, .down)
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
        floatingFormatBarPresentationTask?.cancel()
        floatingFormatBarPresentationTask = nil
    }

    private var topChrome: some View {
        HStack(alignment: .center, spacing: 8) {
            ChromeSoftCircleSymbolButton(
                systemName: "xmark",
                accessibilityLabel: localized("Cancel"),
                action: closeEditor,
                size: topChromeActionSize
            )

            Spacer(minLength: 0)

            sideSwitch

            Spacer(minLength: 0)

            Button(action: openPreview) {
                ChromeSoftCircleSymbol(
                    systemName: "eye",
                    size: topChromeActionSize,
                    symbolSize: 18,
                    tint: canSave ? nil : .secondary,
                    backgroundTint: Color(uiColor: .tertiarySystemFill)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.55)
            .accessibilityLabel(localized("Preview"))

            topOptionsMenu

            Button(action: saveCard) {
                ChromeSoftCircleSymbol(
                    systemName: "checkmark",
                    size: topChromeActionSize,
                    symbolSize: 21,
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

    @ViewBuilder
    private var topOptionsMenu: some View {
        if let path = formatBarPath {
            Menu {
                Section {
                    Button {
                        setCardVerticalAlignment(.top)
                    } label: {
                        optionsMenuRow(
                            title: localized("Align Top"),
                            systemImage: "align.vertical.top",
                            isSelected: resolvedVerticalAlignment == .top
                        )
                    }

                    Button {
                        setCardVerticalAlignment(.center)
                    } label: {
                        optionsMenuRow(
                            title: localized("Align Middle"),
                            systemImage: "align.vertical.center",
                            isSelected: resolvedVerticalAlignment == .center
                        )
                    }

                    Button {
                        setCardVerticalAlignment(.bottom)
                    } label: {
                        optionsMenuRow(
                            title: localized("Align Bottom"),
                            systemImage: "align.vertical.bottom",
                            isSelected: resolvedVerticalAlignment == .bottom
                        )
                    }
                }

                Section {
                    Button {
                        setSelectedZoneAutoSize(at: path)
                    } label: {
                        optionsMenuRow(
                            title: localized("Auto Size"),
                            systemImage: "arrow.up.left.and.down.right.magnifyingglass",
                            isSelected: currentContent.zone(at: path)?.sizeMode == .auto
                        )
                    }

                    Button {
                        setSelectedZoneFillWidth(at: path)
                    } label: {
                        optionsMenuRow(
                            title: localized("Fill Width"),
                            systemImage: "arrow.left.and.right",
                            isSelected: currentContent.zone(at: path)?.sizeMode == .fillWidth
                        )
                    }

                    if currentContent.zone(at: path)?.sizeMode == .fixed {
                        Button { } label: {
                            optionsMenuRow(
                                title: localized("Fixed Size"),
                                systemImage: "rectangle.resize",
                                isSelected: true
                            )
                        }
                        .disabled(true)
                    }
                }

                Section {
                    Button {
                        setSelectedZoneBlockAlignment(.auto, at: path)
                    } label: {
                        optionsMenuRow(
                            title: localized("Auto Block"),
                            systemImage: "sparkles",
                            isSelected: isSelectedZoneAutoBlock(at: path)
                        )
                    }

                    Button {
                        setSelectedZoneBlockAlignment(.leading, at: path)
                    } label: {
                        optionsMenuRow(
                            title: localized("Block Left"),
                            systemImage: "rectangle.leadinghalf.inset.filled",
                            isSelected: currentContent.zone(at: path)?.blockAlignment == .leading
                        )
                    }

                    Button {
                        setSelectedZoneBlockAlignment(.center, at: path)
                    } label: {
                        optionsMenuRow(
                            title: localized("Block Center"),
                            systemImage: "rectangle.center.inset.filled",
                            isSelected: currentContent.zone(at: path)?.blockAlignment == .center
                        )
                    }

                    Button {
                        setSelectedZoneBlockAlignment(.trailing, at: path)
                    } label: {
                        optionsMenuRow(
                            title: localized("Block Right"),
                            systemImage: "rectangle.trailinghalf.inset.filled",
                            isSelected: currentContent.zone(at: path)?.blockAlignment == .trailing
                        )
                    }
                }

                Section {
                    Button {
                        insertZoneFromToolbar(relativeTo: path, direction: .up)
                    } label: {
                        Label(localized("Add Zone Above"), systemImage: "plus.rectangle.on.rectangle")
                    }

                    Button {
                        insertZoneFromToolbar(relativeTo: path, direction: .down)
                    } label: {
                        Label(localized("Add Zone Below"), systemImage: "rectangle.on.rectangle.badge.plus")
                    }

                    Button {
                        duplicateSelectedZone()
                    } label: {
                        Label(localized("Duplicate"), systemImage: "doc.on.doc")
                    }

                    Button(role: .destructive) {
                        deleteSelectedZone(at: path)
                    } label: {
                        Label(localized("Delete"), systemImage: "trash")
                    }
                }

                Section {
                    Button {
                        isPhotoPickerPresented = true
                    } label: {
                        Label(localized("Choose Photos"), systemImage: "photo.on.rectangle")
                    }

                    Button {
                        showSketchModal = true
                    } label: {
                        Label(localized("Sketch"), systemImage: "pencil.and.scribble")
                    }
                }
            } label: {
                ChromeSoftCircleSymbol(
                    systemName: "ellipsis",
                    size: topChromeActionSize,
                    symbolSize: 19,
                    backgroundTint: Color(uiColor: .tertiarySystemFill)
                )
            }
            .accessibilityLabel(localized("More Options"))
        }
    }

    private var resolvedVerticalAlignment: ZoneVerticalAlignment {
        currentContent.rootZone.verticalAlignment.resolved(fallback: .center)
    }

    private func isSelectedZoneAutoBlock(at path: ZonePath) -> Bool {
        guard let zone = currentContent.zone(at: path) else { return true }
        return zone.blockAlignment == .auto
    }

    private func optionsMenuRow(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }

    private var sideSwitch: some View {
        Button {
            toggleActiveSide()
        } label: {
            HStack(spacing: 8) {
                Text(activeSideAbbreviation)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(accent, in: Circle())
                    .contentTransition(.opacity)

//                Text(activeSideTitle)
//                    .font(.system(size: 14, weight: .bold, design: .rounded))
//                    .foregroundStyle(.primary)
//                    .lineLimit(1)
//                    .contentTransition(.opacity)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(accent)
                    .rotationEffect(.degrees(activeSide == 0 ? 0 : 180))
                    .symbolEffect(.bounce, value: activeSide)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.76))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.45), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: activeSide)
        .accessibilityLabel(activeSideTitle)
        .accessibilityAddTraits(.isButton)
    }

    private var activeSideTitle: String {
        activeSide == 0 ? localized("Question") : localized("Answer")
    }

    private var activeSideAbbreviation: String {
        activeSide == 0 ? "Q" : "A"
    }

    private func toggleActiveSide() {
        let oldSide = activeSide
        let newSide = activeSide == 0 ? 1 : 0
        activeSide = newSide
        handleSideChange(from: oldSide, to: newSide)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func openPreview() {
        guard canSave else { return }
        focusManager.forceReleaseKeyboard()
        zoneController.forceReleaseKeyboard()
        zoneController.updateFocusedZone(nil)
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

    // MARK: - Zone Operations

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
                            zone.imageScale = 1.0
                            zone.sizeMode = .auto
                            zone.fixedWidth = nil
                            zone.fixedHeight = nil
                        }
                    } else {
                        currentContent.addZone(relativeTo: .root, direction: .down)
                        if let children = currentContent.rootZone.children, !children.isEmpty {
                            let newPath = ZonePath(indices: [children.count - 1])
                            currentContent.updateZone(at: newPath) { zone in
                                zone.contentType = .image
                                zone.imageData = compressedData
                                zone.imageScale = 1.0
                                zone.sizeMode = .auto
                                zone.fixedWidth = nil
                                zone.fixedHeight = nil
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
                        zone.imageScale = 1.0
                        zone.sizeMode = .auto
                        zone.fixedWidth = nil
                        zone.fixedHeight = nil
                    }
                } else {
                    currentContent.addZone(relativeTo: .root, direction: .down)
                    if let children = currentContent.rootZone.children, !children.isEmpty {
                        let newPath = ZonePath(indices: [children.count - 1])
                        currentContent.updateZone(at: newPath) { zone in
                            zone.contentType = .sketch
                            zone.imageData = data
                            zone.imageScale = 1.0
                            zone.sizeMode = .auto
                            zone.fixedWidth = nil
                            zone.fixedHeight = nil
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

private struct FloatingFormatBarTopPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat?

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

// MARK: - Toolbar Performance Debug Overlay

private struct EditorToolbarPerformanceOverlay: UIViewRepresentable {
    let snapshot: Snapshot

    struct Snapshot: Equatable {
        var keyboardVisible: Bool
        var keyboardHeight: CGFloat
        var keyboardDuration: TimeInterval
        var toolbarVisible: Bool
        var toolbarTopY: CGFloat?
        var toolbarScale: CGFloat
        var toolbarOpacity: Double
        var topUpdateCount: Int
        var keyboardRevision: Int
        var toolbarRevision: Int
        var pathID: String
    }

    func makeUIView(context: Context) -> EditorToolbarPerformanceOverlayView {
        let view = EditorToolbarPerformanceOverlayView()
        view.update(snapshot)
        return view
    }

    func updateUIView(_ uiView: EditorToolbarPerformanceOverlayView, context: Context) {
        uiView.update(snapshot)
    }
}

private final class EditorToolbarPerformanceOverlayView: UIView {
    private let label = UILabel()
    private var displayLink: CADisplayLink?
    private var snapshot: EditorToolbarPerformanceOverlay.Snapshot?
    private var frameCount = 0
    private var fpsWindowStart: CFTimeInterval = 0
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var maxFrameMilliseconds: Double = 0
    private var slowFrameCount = 0
    private var keyboardRevisionTime = CFAbsoluteTimeGetCurrent()
    private var toolbarRevisionTime = CFAbsoluteTimeGetCurrent()
    private var topUpdateTime = CFAbsoluteTimeGetCurrent()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 8
        layer.masksToBounds = true
        backgroundColor = UIColor.black.withAlphaComponent(0.72)

        label.numberOfLines = 5
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        label.textColor = .systemOrange
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    func update(_ nextSnapshot: EditorToolbarPerformanceOverlay.Snapshot) {
        let now = CFAbsoluteTimeGetCurrent()
        if snapshot?.keyboardRevision != nextSnapshot.keyboardRevision {
            keyboardRevisionTime = now
        }
        if snapshot?.toolbarRevision != nextSnapshot.toolbarRevision {
            toolbarRevisionTime = now
        }
        if snapshot?.topUpdateCount != nextSnapshot.topUpdateCount {
            topUpdateTime = now
        }
        snapshot = nextSnapshot
        render(currentFPS: nil)
    }

    @objc private func tick(_ link: CADisplayLink) {
        if fpsWindowStart == 0 {
            fpsWindowStart = link.timestamp
            lastFrameTimestamp = link.timestamp
            return
        }

        frameCount += 1
        let frameMilliseconds = (link.timestamp - lastFrameTimestamp) * 1_000
        lastFrameTimestamp = link.timestamp
        maxFrameMilliseconds = max(maxFrameMilliseconds, frameMilliseconds)
        if frameMilliseconds > 20 {
            slowFrameCount += 1
        }

        let elapsed = link.timestamp - fpsWindowStart
        if elapsed >= 0.5 {
            let fps = Int((Double(frameCount) / elapsed).rounded())
            render(currentFPS: fps)
            frameCount = 0
            fpsWindowStart = link.timestamp
            maxFrameMilliseconds = 0
            slowFrameCount = 0
        }
    }

    private func render(currentFPS: Int?) {
        guard let snapshot else { return }

        let now = CFAbsoluteTimeGetCurrent()
        let fpsText = currentFPS.map(String.init) ?? "--"
        let topText = snapshot.toolbarTopY.map { String(format: "%.0f", Double($0)) } ?? "nil"
        let keyboardDelta = now - keyboardRevisionTime
        let toolbarDelta = now - toolbarRevisionTime
        let topDelta = now - topUpdateTime

        label.text = """
        fps \(fpsText) max \(String(format: "%.1f", maxFrameMilliseconds))ms slow \(slowFrameCount)
        kb \(flag(snapshot.keyboardVisible)) h \(format(snapshot.keyboardHeight)) dur \(String(format: "%.2f", snapshot.keyboardDuration)) +\(String(format: "%.2f", keyboardDelta))s
        bar \(flag(snapshot.toolbarVisible)) top \(topText) scale \(format(snapshot.toolbarScale)) op \(String(format: "%.2f", snapshot.toolbarOpacity)) +\(String(format: "%.2f", toolbarDelta))s
        topUpd \(snapshot.topUpdateCount) +\(String(format: "%.2f", topDelta))s path \(snapshot.pathID)
        """

        if maxFrameMilliseconds > 33 {
            label.textColor = .systemRed
            backgroundColor = UIColor.black.withAlphaComponent(0.82)
        } else if maxFrameMilliseconds > 20 || slowFrameCount > 0 {
            label.textColor = .systemOrange
            backgroundColor = UIColor.black.withAlphaComponent(0.76)
        } else {
            label.textColor = .systemGreen
            backgroundColor = UIColor.black.withAlphaComponent(0.70)
        }
    }

    private func flag(_ value: Bool) -> String {
        value ? "1" : "0"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.0f", Double(value))
    }
}

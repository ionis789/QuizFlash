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
    @State private var initialFrontZone: ZoneModel
    @State private var initialBackZone: ZoneModel
    @State private var activeSide = 0
    @State private var frontSelectedPath: ZonePath? = .root
    @State private var backSelectedPath: ZonePath? = .root
    @State private var showSketchModal = false
    @State private var showPreview = false
    @State private var showUnsavedChangesDialog = false
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
    @State private var showsRenderedContent = false
    @State private var showsEditorDebugOverlays = true
    @State private var scrollRestorationRequest: ZoneEditorScrollRestorationRequest?
    @State private var scrollTransition = FlashcardEditorScrollTransitionState()


    // Visual-only ghost preview. The model changes only after the user commits.
    @State private var previewDirection: AddDirection? = nil

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var successAccent: Color { ThemeManager.shared.successPrimary }
    private var topChromeUtilityFill: Color { Color(uiColor: .secondarySystemFill) }
    private var topChromeUtilityBorder: Color { Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.10) }
    private var topChromeUtilityForeground: Color { accent }
    private var topChromeDisabledFill: Color { Color(uiColor: .tertiarySystemFill) }
    private var currentContent: ZoneCardContent { activeSide == 0 ? frontZoneContent : backZoneContent }
    private var selectedPath: ZonePath? {
        get { activeSide == 0 ? frontSelectedPath : backSelectedPath }
        nonmutating set {
            if activeSide == 0 {
                frontSelectedPath = newValue
            } else {
                backSelectedPath = newValue
            }
        }
    }
    private var frontSelectedPathBinding: Binding<ZonePath?> {
        Binding(
            get: { frontSelectedPath },
            set: { frontSelectedPath = $0 }
        )
    }
    private var backSelectedPathBinding: Binding<ZonePath?> {
        Binding(
            get: { backSelectedPath },
            set: { backSelectedPath = $0 }
        )
    }
    private var selectedPathBinding: Binding<ZonePath?> {
        activeSide == 0 ? frontSelectedPathBinding : backSelectedPathBinding
    }
    private var hasSavableContent: Bool { frontZoneContent.hasContent || backZoneContent.hasContent }
    private var hasUnsavedChanges: Bool {
        frontZoneContent.rootZone != initialFrontZone || backZoneContent.rootZone != initialBackZone
    }
    private var canSave: Bool { hasUnsavedChanges && hasSavableContent }
    private var locale: Locale { appPreferences.resolvedLocale }
    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var topChromeHorizontalInset: CGFloat {
        isCompact ? UIConstants.Layout.compactScreenEdgeInset : UIConstants.Layout.screenEdgeInset
    }
    private var topChromeReservedHeight: CGFloat {
        UIConstants.Layout.deckNavigationTopPadding + UIConstants.Size.actionButton
    }
    private func editorTopBlurHeight(safeTopInset: CGFloat) -> CGFloat {
        safeTopInset + topChromeReservedHeight
    }

    private func editorBottomBlurHeight(safeBottomInset: CGFloat) -> CGFloat {
        safeBottomInset
    }

    private func editorTopContentInset(safeTopInset: CGFloat) -> CGFloat {
        safeTopInset + topChromeReservedHeight + UIConstants.Spacing.medium
    }
    private var sideSwitchWidth: CGFloat {
        UIConstants.Size.actionButton * 2
    }
    private var sideSwitchSegmentWidth: CGFloat {
        (sideSwitchWidth - UIConstants.Spacing.standard * 2 - UIConstants.Spacing.medium) / 2
    }
    private var sideSwitchIndicatorWidth: CGFloat { 16 }
    private var sideSwitchIndicatorX: CGFloat {
        let baseX = UIConstants.Spacing.standard + (sideSwitchSegmentWidth - sideSwitchIndicatorWidth) / 2
        guard activeSide == 1 else { return baseX }
        return baseX + sideSwitchSegmentWidth + UIConstants.Spacing.medium
    }
    private var editorTextScale: CGFloat {
        CGFloat(textSize.playModeScale)
    }
    private var verticalAlignmentFallback: ZoneVerticalAlignment {
        ZoneVerticalAlignment(fallbackContentAlignment: contentAlignment)
    }
    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private static func initialSelectedPath(in zone: ZoneModel) -> ZonePath {
        firstLeafPath(in: zone, currentPath: .root) ?? .root
    }

    private static func firstLeafPath(in zone: ZoneModel, currentPath: ZonePath) -> ZonePath? {
        guard !zone.isLeaf else { return currentPath }
        guard let children = zone.children else { return nil }

        for (index, child) in children.enumerated() {
            if let path = firstLeafPath(in: child, currentPath: currentPath.appending(index)) {
                return path
            }
        }

        return nil
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
        let frontContent = ZoneCardContent(rootZone: .text(), stableAuthoringRoot: true)
        let backContent = ZoneCardContent(rootZone: .text(), stableAuthoringRoot: true)
        _frontZoneContent = State(initialValue: frontContent)
        _backZoneContent = State(initialValue: backContent)
        _initialFrontZone = State(initialValue: frontContent.rootZone)
        _initialBackZone = State(initialValue: backContent.rootZone)
        _frontSelectedPath = State(initialValue: Self.initialSelectedPath(in: frontContent.rootZone))
        _backSelectedPath = State(initialValue: Self.initialSelectedPath(in: backContent.rootZone))
       
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
        let frontContent = ZoneCardContent(rootZone: frontZone, stableAuthoringRoot: true)
        let backContent = ZoneCardContent(rootZone: backZone, stableAuthoringRoot: true)
        _frontZoneContent = State(initialValue: frontContent)
        _backZoneContent = State(initialValue: backContent)
        _initialFrontZone = State(initialValue: frontContent.rootZone)
        _initialBackZone = State(initialValue: backContent.rootZone)
        _frontSelectedPath = State(initialValue: Self.initialSelectedPath(in: frontContent.rootZone))
        _backSelectedPath = State(initialValue: Self.initialSelectedPath(in: backContent.rootZone))

        if let query = searchQuery, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            _highlightContext = State(initialValue: HighlightContext(query: query))
        } else {
            _highlightContext = State(initialValue: nil)
        }

    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let safeTopInset = proxy.safeAreaInsets.top
            let safeBottomInset = proxy.safeAreaInsets.bottom

            ZStack(alignment: .top) {
                editorBackground.ignoresSafeArea()

                editorArea(safeTopInset: safeTopInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(.container, edges: .vertical)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .screenEdgeShadow(
                        topHeight: editorTopBlurHeight(safeTopInset: safeTopInset),
                        bottomHeight: editorBottomBlurHeight(safeBottomInset: safeBottomInset),
                        debugScreenID: "flashcard.editor",
                        style: .progressiveBlur()
                    )

                topChrome
                    .zIndex(20)
                floatingFormatBar
                floatingFormatBarDebugOverlay
                editorDebugVisibilityButton(safeBottomInset: safeBottomInset)
            }
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
        .confirmationDialog(
            localized("Save changes before leaving?"),
            isPresented: $showUnsavedChangesDialog,
            titleVisibility: .visible
        ) {
            if canSave {
                Button(localized("Save Changes")) {
                    saveCard()
                }
            }
            Button(localized("Discard Changes"), role: .destructive) {
                closeEditorDiscardingChanges()
            }
            Button(localized("Cancel"), role: .cancel) { }
        }
        .onAppear {
            if selectedPath == nil {
                selectedPath = Self.initialSelectedPath(in: currentContent.rootZone)
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
        isFloatingFormatBarPresented && selectedPath != nil
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
            ? UIConstants.Spacing.tiny
            : UIConstants.Spacing.standard
    }

    private var floatingFormatBarYOffset: CGFloat {
        -floatingFormatBarKeyboardHeight
    }

    private var floatingFormatBarRenderedTopY: CGFloat? {
        floatingFormatBarTopY.map { $0 + floatingFormatBarYOffset }
    }

    private var floatingToolbarAccessoryHeight: CGFloat {
        isFloatingFormatBarVisible ? 96 : 0
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
            && showsEditorDebugOverlays
            && developmentPreferences.zoneEditorDebugHUDEnabled
    }

    @ViewBuilder
    private func editorDebugVisibilityButton(safeBottomInset: CGFloat) -> some View {
        if AppFeatures.current.showsVisualDebugOverlays {
            VStack {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        showsEditorDebugOverlays.toggle()
                    } label: {
                        Image(systemName: showsEditorDebugOverlays ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(showsEditorDebugOverlays ? Color.orange : Color.secondary)
                            .frame(width: 32, height: 32)
                            .background(.black.opacity(0.78), in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        showsEditorDebugOverlays
                            ? "Hide debug overlays"
                            : "Show debug overlays"
                    )
                    .padding(.trailing, 12)
                    .padding(.bottom, max(safeBottomInset, 8) + 4)
                }
            }
            .zIndex(60)
        }
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
            onInsertForcedLineBreak: {
                insertForcedLineBreak(at: path)
            },
            onDuplicateZone: {
                duplicateSelectedZone()
            },
            onDeleteZone: {
                deleteSelectedZone(at: path)
            },
            canPreview: hasSavableContent,
            showsPrimaryActions: false,
            showsZoneActions: true,
            onPreview: {
                openPreview()
            },
            onClose: {
                dismissFloatingFormatMenu()
            }
        )
    }

    @ViewBuilder
    private func editorArea(safeTopInset: CGFloat) -> some View {
        if showsRenderedContent {
            ZStack {
                renderedEditorCanvas(
                    content: frontZoneContent,
                    selectedPath: frontSelectedPathBinding,
                    side: 0,
                    safeTopInset: safeTopInset
                )
                renderedEditorCanvas(
                    content: backZoneContent,
                    selectedPath: backSelectedPathBinding,
                    side: 1,
                    safeTopInset: safeTopInset
                )
            }
            .transition(editorModeTransition(insertingRenderedContent: true))
        } else {
            editorCanvas(
                content: currentContent,
                selectedPath: selectedPathBinding,
                side: activeSide,
                safeTopInset: safeTopInset,
                rendersRichText: false
            )
            .transition(editorModeTransition(insertingRenderedContent: false))
        }
    }

    private var editorModeAnimation: Animation {
        .smooth(duration: UIConstants.Animation.medium, extraBounce: 0)
    }

    private func editorModeTransition(insertingRenderedContent: Bool) -> AnyTransition {
        let incomingScale: CGFloat = insertingRenderedContent ? 1.012 : 0.988
        let outgoingScale: CGFloat = insertingRenderedContent ? 0.988 : 1.012

        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: incomingScale, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: outgoingScale, anchor: .top))
        )
    }

    private func renderedEditorCanvas(
        content: ZoneCardContent,
        selectedPath: Binding<ZonePath?>,
        side: Int,
        safeTopInset: CGFloat
    ) -> some View {
        editorCanvas(
            content: content,
            selectedPath: selectedPath,
            side: side,
            safeTopInset: safeTopInset,
            rendersRichText: true
        )
        .opacity(activeSide == side ? 1 : 0)
        .allowsHitTesting(activeSide == side)
        .disabled(activeSide != side)
        .accessibilityHidden(activeSide != side)
        .zIndex(activeSide == side ? 1 : 0)
    }

    private func editorCanvas(
        content: ZoneCardContent,
        selectedPath: Binding<ZonePath?>,
        side: Int,
        safeTopInset: CGFloat,
        rendersRichText: Bool
    ) -> some View {
        ZoneEditorCanvas(
            content: content,
            selectedPath: selectedPath,
            previewDirection: $previewDirection,
            highlightContext: highlightContext,
            fontScale: editorTextScale,
            verticalAlignmentFallback: verticalAlignmentFallback,
            topContentInset: editorTopContentInset(safeTopInset: safeTopInset),
            bottomAccessoryHeight: floatingToolbarAccessoryHeight,
            bottomAccessoryTopY: keyboardMonitor.isVisible ? floatingFormatBarRenderedTopY : nil,
            scrollResetToken: activeSide,
            scrollRestorationRequest: activeSide == side ? scrollRestorationRequest : nil,
            rendersRichText: rendersRichText,
            showsDebugOverlays: showsEditorDebugOverlays && activeSide == side,
            onScrollOffsetChange: { offsetY in
                guard activeSide == side else { return }
                handleEditorScrollOffsetChange(offsetY)
            },
            onEmptySpaceTap: { context in
                guard activeSide == side else { return }
                handleCanvasEmptySpaceTap(context)
            },
            onScrollRestorationApplied: {
                guard activeSide == side else { return }
                handleScrollRestorationApplied()
            }
        )
    }

    private func handleEditorScrollOffsetChange(_ offsetY: CGFloat) {
        scrollTransition.currentNormalizedOffsetY = offsetY
    }

    private func handleScrollRestorationApplied() {
        scrollTransition.restoringAfterModeSwitch = false
        scrollRestorationRequest = nil
    }

    private func handleCanvasEmptySpaceTap(_ context: ZoneEditorCanvasTapContext) {
        focusManager.prepareForZoneInsertion()

        if !currentContent.rootZone.hasContent,
           let emptyPath = firstEditableLeafPath(in: currentContent.rootZone),
           let emptyZone = currentContent.zone(at: emptyPath) {
            selectedPath = emptyPath
            focusManager.requestFocus(for: emptyZone.id)
            return
        }

        if !currentContent.rootZone.hasContent, currentContent.rootZone.isLeaf {
            selectedPath = .root
            currentContent.updateZone(at: .root) { zone in
                zone.contentType = .text
                zone.sizeMode = .auto
                zone.blockAlignment = .auto
                zone.textAlignment = .leading
            }
            focusManager.requestFocus(for: currentContent.rootZone.id)
            return
        }

        let insertion = insertionPoint(for: context)

        if let emptyPath = blockingEmptyTextZonePath(
            relativeTo: insertion.path,
            direction: insertion.direction
        ),
           let emptyZone = currentContent.zone(at: emptyPath) {
            selectedPath = emptyPath
            focusManager.requestFocus(for: emptyZone.id)
            return
        }

        insertTextZoneWithFocus(relativeTo: insertion.path, direction: insertion.direction)
    }

    private func dismissFloatingFormatMenu() {
        focusManager.forceReleaseKeyboard()
        zoneController.forceReleaseKeyboard()
        zoneController.updateFocusedZone(nil)
        selectedPath = nil
        previewDirection = nil
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

        return zone.text.isEmpty
    }

    private func firstEditableLeafPath(
        in zone: ZoneModel,
        currentPath: ZonePath = .root
    ) -> ZonePath? {
        if zone.isLeaf {
            switch zone.contentType {
            case .empty, .text, .code:
                return currentPath
            case .image, .sketch:
                return nil
            }
        }

        guard let children = zone.children else { return nil }
        for (index, child) in children.enumerated() {
            if let path = firstEditableLeafPath(in: child, currentPath: currentPath.appending(index)) {
                return path
            }
        }

        return nil
    }

    private func deleteSelectedZone(at path: ZonePath) {
        currentContent.deleteZone(at: path)
        focusManager.forceReleaseKeyboard()
        selectedPath = nil
        previewDirection = nil
    }

    private func insertForcedLineBreak(at path: ZonePath) {
        guard let zone = currentContent.zone(at: path),
              zone.contentType == .text || zone.contentType == .empty || zone.contentType == .code else {
            return
        }

        selectedPath = path
        focusManager.prepareForZoneInsertion()
        focusManager.requestFocus(for: zone.id)
        NotificationCenter.default.post(
            name: .zoneEditorInsertForcedLineBreak,
            object: zone.id
        )
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

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            newZoneID = currentContent.addTextZone(relativeTo: path, direction: direction)
            if let newID = newZoneID, let newPath = findPath(for: newID, in: currentContent.rootZone) {
                selectedPath = newPath
            }
        }

        if let id = newZoneID {
            focusManager.requestFocus(for: id)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
        HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
            closeTopButton

            Spacer(minLength: 0)

            HStack(spacing: UIConstants.Spacing.small) {
                sideSwitch
                previewTopButton
                renderTopButton
            }

            Spacer(minLength: 0)

            Button(action: saveCard) {
                ChromeSoftCircleSymbol(
                    systemName: "checkmark",
                    size: UIConstants.Size.actionButton,
                    symbolSize: UIConstants.Size.navigationChromeIcon,
                    tint: canSave ? Color.black.opacity(0.78) : .secondary,
                    backgroundTint: canSave ? successAccent : topChromeDisabledFill
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.55)
            .accessibilityLabel(localized("Save"))
        }
        .topNavigationChrome(horizontalInset: topChromeHorizontalInset)
    }

    private var closeTopButton: some View {
        ChromeSoftCircleSymbolButton(
            systemName: "xmark",
            accessibilityLabel: localized("Close"),
            action: closeEditor,
            size: UIConstants.Size.actionButton,
            symbolSize: UIConstants.Size.navigationChromeIcon,
            tint: topChromeUtilityForeground,
            backgroundTint: topChromeUtilityFill
        )
    }

    private var previewTopButton: some View {
        Button(action: openPreview) {
            ChromeSoftCircleSymbol(
                systemName: "eye",
                size: UIConstants.Size.actionButton,
                symbolSize: UIConstants.Size.navigationChromeIcon,
                tint: hasSavableContent ? topChromeUtilityForeground : .secondary,
                backgroundTint: topChromeUtilityFill
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasSavableContent)
        .opacity(hasSavableContent ? 1 : 0.55)
        .accessibilityLabel(localized("Preview"))
    }

    private var renderTopButton: some View {
        Button(action: toggleRenderedContent) {
            ChromeSoftCircleSymbol(
                systemName: "rectangle.dashed",
                size: UIConstants.Size.actionButton,
                symbolSize: UIConstants.Size.navigationChromeIcon,
                tint: hasSavableContent ? topChromeUtilityForeground : .secondary,
                backgroundTint: showsRenderedContent ? accent.opacity(0.28) : topChromeUtilityFill
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasSavableContent)
        .opacity(hasSavableContent ? 1 : 0.55)
        .accessibilityLabel(localized("Render"))
    }

    private var sideSwitch: some View {
        Button {
            toggleActiveSide()
        } label: {
            ZStack(alignment: .bottomLeading) {
                HStack(spacing: UIConstants.Spacing.medium) {
                    sideSwitchSegment(title: "Q", isSelected: activeSide == 0)
                    sideSwitchSegment(title: "A", isSelected: activeSide == 1)
                }
                .padding(.horizontal, UIConstants.Spacing.standard)

                Capsule(style: .continuous)
                    .fill(accent)
                    .frame(width: sideSwitchIndicatorWidth, height: 3)
                    .offset(x: sideSwitchIndicatorX, y: -8)
                    .animation(.tabItemSpring, value: activeSide)
            }
            .frame(width: sideSwitchWidth, height: UIConstants.Size.actionButton)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Capsule(style: .continuous)
                .fill(topChromeUtilityFill)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(topChromeUtilityBorder, lineWidth: 0.75)
        )
        .accessibilityLabel(activeSideTitle)
        .accessibilityAddTraits(.isButton)
    }

    private func sideSwitchSegment(title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .black, design: .rounded))
            .foregroundStyle(Color.primary)
            .scaleEffect(isSelected ? 1.2 : 0.9)
            .animation(.tabItemSpring, value: isSelected)
            .frame(width: sideSwitchSegmentWidth, height: UIConstants.Size.actionButton)
    }

    private var activeSideTitle: String {
        activeSide == 0 ? localized("Question") : localized("Answer")
    }

    private func toggleActiveSide() {
        let newSide = activeSide == 0 ? 1 : 0
        blurEditingBeforeSideSwitch()
        activeSide = newSide
        selectedPath = nil
        zoneController.setActiveSide(newSide)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func openPreview() {
        guard hasSavableContent else { return }
        focusManager.forceReleaseKeyboard()
        zoneController.forceReleaseKeyboard()
        zoneController.updateFocusedZone(nil)
        selectedPath = nil
        previewDirection = nil
        showPreview = true
    }

    private func toggleRenderedContent() {
        guard hasSavableContent else { return }
        let targetMode = !showsRenderedContent

        scrollTransition.currentMode = showsRenderedContent
        scrollTransition.targetMode = targetMode
        scrollTransition.restoringAfterModeSwitch = true
        scrollRestorationRequest = ZoneEditorScrollRestorationRequest(
            normalizedOffsetY: scrollTransition.currentNormalizedOffsetY,
            targetRenderedMode: targetMode
        )

        if targetMode {
            focusManager.forceReleaseKeyboard()
            zoneController.forceReleaseKeyboard()
            zoneController.updateFocusedZone(nil)
        }

        withTransaction(Transaction(animation: editorModeAnimation)) {
            showsRenderedContent = targetMode
        }
    }

    private func closeEditor() {
        guard !hasUnsavedChanges else {
            focusManager.forceReleaseKeyboard()
            zoneController.forceReleaseKeyboard()
            showUnsavedChangesDialog = true
            return
        }
        closeEditorDiscardingChanges()
    }

    private func closeEditorDiscardingChanges() {
        focusManager.forceReleaseKeyboard()
        zoneController.forceReleaseKeyboard()
        lineTracker.clearAll()
        zoneController.clearHeightCache()
        dismiss()
    }

    private func blurEditingBeforeSideSwitch() {
        scheduledFocusTask?.cancel()
        scheduledFocusTask = nil
        previewDirection = nil
        selectedPath = nil
        focusManager.forceReleaseKeyboard()
        zoneController.forceReleaseKeyboard()
        zoneController.updateFocusedZone(nil)
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
        .black
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

struct ZoneEditorScrollRestorationRequest: Equatable {
    let normalizedOffsetY: CGFloat
    let targetRenderedMode: Bool
}

private final class FlashcardEditorScrollTransitionState {
    var currentNormalizedOffsetY: CGFloat = 0
    var currentMode: Bool = false
    var targetMode: Bool = false
    var restoringAfterModeSwitch = false
}

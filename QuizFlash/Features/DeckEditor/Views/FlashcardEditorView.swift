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
    var onContentChange: ((ZoneModel, ZoneModel) -> Void)?
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
    @State private var scheduledRenderToggleTask: Task<Void, Never>?
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
    @State private var suppressCanvasEmptyTapUntil: CFAbsoluteTime = 0
    @State private var editorSessionID = UUID()


    // Visual-only ghost preview. The model changes only after the user commits.
    @State private var previewDirection: AddDirection? = nil

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var successAccent: Color { ThemeManager.shared.successPrimary }
    private var topChromeUtilityFill: Color { Color(uiColor: .secondarySystemBackground) }
    private var topChromeUtilityBorder: Color { Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.10) }
    private var topChromeUtilityForeground: Color { accent }
    private var topChromeDisabledFill: Color { Color(uiColor: .tertiarySystemBackground) }
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
        onContentChange: ((ZoneModel, ZoneModel) -> Void)? = nil,
        onSave: @escaping (ZoneModel, ZoneModel) -> Void
    ) {
        self.onSaveZones = onSave
        self.onContentChange = onContentChange
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
        onContentChange: ((ZoneModel, ZoneModel) -> Void)? = nil,
        onSave: @escaping (ZoneModel, ZoneModel) -> Void
    ) {

        self.onSaveZones = onSave
        self.onContentChange = onContentChange
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
            let _ = recordEditorLifecycle("editor-body", details: "safe=\(Int(proxy.safeAreaInsets.top)),\(Int(proxy.safeAreaInsets.bottom))")
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
        .onChange(of: selectedPhoto) { _, item in
            recordEditorLifecycle(
                "photo-selection-change",
                details: "hasItem=\(item == nil ? 0 : 1) selected=\(selectedPath?.id ?? "nil")"
            )
            addPhoto(item)
        }
        .onChange(of: keyboardMonitor.isVisible) { _, isVisible in
            keyboardDebugRevision += 1
            toolbarVisibilityDebugRevision += 1
            recordToolbarLifecycle(
                "keyboard-visible-change",
                details: "visible=\(debugFlag(isVisible)) \(toolbarLifecycleDetails())"
            )
            updateFloatingFormatBarPresentation(isKeyboardVisible: isVisible)
            updateToolbarDebugLine()
        }
        .onChange(of: keyboardMonitor.visibleHeight) { _, _ in
            recordToolbarLifecycle(
                "keyboard-height-change",
                details: "height=\(debugValue(keyboardMonitor.visibleHeight)) \(toolbarLifecycleDetails())"
            )
            updateFloatingFormatBarKeyboardHeight()
            updateToolbarDebugLine()
        }
        .onChange(of: frontSelectedPath) { _, _ in
            handleSelectedPathChange(source: "front")
        }
        .onChange(of: backSelectedPath) { _, _ in
            handleSelectedPathChange(source: "back")
        }
        .fullScreenCover(isPresented: $showSketchModal) { CanvasModalView { data in addSketch(data) } }
        .fullScreenSheet(
            isPresented: $showPreview,
            configuration: .sheet(
                heightMode: .fullScreen,
                showsBackdropBlur: false,
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
            configureZoneEditorDebugRecording()
            recordEditorLifecycle("editor-appear", details: "destination=flashcard")
            if selectedPath == nil {
                selectedPath = Self.initialSelectedPath(in: currentContent.rootZone)
            }
            focusManager.forceReleaseKeyboard()
        }
        .onDisappear {
            recordEditorLifecycle("editor-disappear", details: "destination=flashcard")
            ZoneEditorDebugStore.shared.setLayoutRecordingEnabled(false)
            cancelScheduledEditorTasks()
        }
        .onChange(of: showsEditorDebugOverlays) { _, _ in
            configureZoneEditorDebugRecording()
        }
        .onChange(of: developmentPreferences.zoneEditorDebugHUDEnabled) { _, _ in
            configureZoneEditorDebugRecording()
        }
        .onChange(of: frontZoneContent.rootZone) { _, _ in
            notifyContentChange()
        }
        .onChange(of: backZoneContent.rootZone) { _, _ in
            notifyContentChange()
        }
    }

    private func notifyContentChange() {
        onContentChange?(frontZoneContent.rootZone, backZoneContent.rootZone)
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
                        .background {
                            GeometryReader { proxy in
                                Color.clear
                                    .onGeometryChange(for: CGFloat.self) { _ in
                                        proxy.frame(in: .global).minY
                                    } action: { topY in
                                        guard abs((floatingFormatBarTopY ?? topY) - topY) > 0.5 else { return }
                                        floatingFormatBarTopY = topY
                                        floatingFormatBarTopUpdateCount += 1
                                    }
                            }
                        }
                        .offset(y: floatingFormatBarYOffset)
                        .modifier(
                            EditorKeyboardAccessoryVisibilityModifier(
                                isVisible: isFloatingFormatBarVisible
                            )
                        )
                        .accessibilityHidden(!isFloatingFormatBarVisible)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .zIndex(30)
    }

    private var isFloatingFormatBarVisible: Bool {
        guard isFloatingFormatBarPresented,
              let selectedPath,
              let selectedZone = currentContent.zone(at: selectedPath) else {
            return false
        }

        return selectedZone.isEditorMediaLeaf || keyboardMonitor.isVisible
    }

    private var floatingFormatBarScale: CGFloat {
        isFloatingFormatBarVisible ? 1 : 0.98
    }

    private var floatingFormatBarOpacity: Double {
        isFloatingFormatBarVisible ? 1 : 0
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
            ? 0
            : UIConstants.Spacing.standard
    }

    private var floatingFormatBarYOffset: CGFloat {
        -floatingFormatBarKeyboardHeight
    }

    private var floatingFormatBarRenderedTopY: CGFloat? {
        floatingFormatBarTopY.map { $0 + floatingFormatBarYOffset }
    }

    private var floatingToolbarAccessoryHeight: CGFloat {
        if isFloatingFormatBarVisible {
            return 96
        }

        guard keyboardMonitor.isVisible,
              selectedPath != nil,
              !selectedZoneIsMedia else { return 0 }
        return 96
    }

    private var selectedZoneIsMedia: Bool {
        guard let selectedPath,
              let selectedZone = currentContent.zone(at: selectedPath) else {
            return false
        }

        return selectedZone.isEditorMediaLeaf
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

    private func configureZoneEditorDebugRecording() {
        ZoneEditorDebugStore.shared.setLayoutRecordingEnabled(showsEditorPerformanceDebug)
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

    private func updateFloatingFormatBarPresentation(isKeyboardVisible: Bool) {
        recordToolbarLifecycle(
            "presentation-request",
            details: "keyboardVisible=\(debugFlag(isKeyboardVisible)) \(toolbarLifecycleDetails())"
        )
        floatingFormatBarPresentationTask?.cancel()
        if floatingFormatBarPresentationTask != nil {
            recordToolbarLifecycle("presentation-task-cancel", details: toolbarLifecycleDetails())
        }
        floatingFormatBarPresentationTask = nil

        if isKeyboardVisible || selectedZoneIsMedia {
            if isKeyboardVisible {
                updateFloatingFormatBarKeyboardHeight()
            } else {
                floatingFormatBarKeyboardHeight = 0
            }

            guard !isFloatingFormatBarPresented else {
                recordToolbarLifecycle("presentation-skip-already-presented", details: toolbarLifecycleDetails())
                updateToolbarDebugLine()
                return
            }

            if isKeyboardVisible, !selectedZoneIsMedia {
                let delay = EditorKeyboardAccessoryMotion.keyboardAppearMenuDelay(
                    keyboardDuration: keyboardMonitor.animationDuration
                )
                recordToolbarLifecycle(
                    "appear-schedule",
                    details: "delay=\(debugDuration(delay)) keyboardDuration=\(String(format: "%.3f", keyboardMonitor.animationDuration)) \(toolbarLifecycleDetails())"
                )
                floatingFormatBarPresentationTask = Task { @MainActor in
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled,
                          keyboardMonitor.isVisible,
                          !selectedZoneIsMedia else {
                        recordToolbarLifecycle("appear-schedule-rejected", details: toolbarLifecycleDetails())
                        return
                    }
                    updateFloatingFormatBarKeyboardHeight()
                    recordToolbarLifecycle("appear-animation-start", details: toolbarLifecycleDetails())
                    withAnimation(EditorKeyboardAccessoryMotion.appearAnimation) {
                        isFloatingFormatBarPresented = true
                    }
                    toolbarVisibilityDebugRevision += 1
                    recordToolbarLifecycle("appear-presented", details: toolbarLifecycleDetails())
                    updateToolbarDebugLine()
                }
            } else {
                recordToolbarLifecycle("appear-immediate-start", details: toolbarLifecycleDetails())
                withAnimation(EditorKeyboardAccessoryMotion.appearAnimation) {
                    isFloatingFormatBarPresented = true
                }
                toolbarVisibilityDebugRevision += 1
                recordToolbarLifecycle("appear-immediate-presented", details: toolbarLifecycleDetails())
                updateToolbarDebugLine()
            }
        } else {
            recordToolbarLifecycle("hide-animation-start", details: toolbarLifecycleDetails())
            withAnimation(EditorKeyboardAccessoryMotion.dismissAnimation) {
                isFloatingFormatBarPresented = false
            }
            toolbarVisibilityDebugRevision += 1
            floatingFormatBarPresentationTask = Task { @MainActor in
                try? await Task.sleep(for: EditorKeyboardAccessoryMotion.cleanupDelay)
                guard !Task.isCancelled else { return }
                withTransaction(Transaction(animation: nil)) {
                    floatingFormatBarKeyboardHeight = 0
                    floatingFormatBarTopY = nil
                }
                recordToolbarLifecycle("hide-cleanup", details: toolbarLifecycleDetails())
                updateToolbarDebugLine()
            }
            updateToolbarDebugLine()
        }
    }

    private func handleSelectedPathChange(source: String) {
        toolbarVisibilityDebugRevision += 1

        if selectedZoneIsMedia {
            prepareForMediaZoneSelection()
            recordToolbarLifecycle("media-selection-present", details: "source=\(source) \(toolbarLifecycleDetails())")
            withAnimation(EditorKeyboardAccessoryMotion.appearAnimation) {
                isFloatingFormatBarPresented = true
                floatingFormatBarKeyboardHeight = 0
            }
            toolbarVisibilityDebugRevision += 1
        } else if !keyboardMonitor.isVisible {
            recordToolbarLifecycle("selection-hide-no-keyboard", details: "source=\(source) \(toolbarLifecycleDetails())")
            withAnimation(EditorKeyboardAccessoryMotion.dismissAnimation) {
                isFloatingFormatBarPresented = false
                floatingFormatBarKeyboardHeight = 0
            }
            toolbarVisibilityDebugRevision += 1
        }

        ZoneEditorDebugStore.shared.recordLayoutEvent(
            "selection-change",
            zoneID: selectedPath.flatMap { currentContent.zone(at: $0)?.id },
            pathID: selectedPath?.id,
            details: "source=\(source) activeSide=\(activeSide) media=\(selectedZoneIsMedia ? 1 : 0) kb=\(keyboardMonitor.isVisible ? 1 : 0) root=\(zoneDebugSummary(currentContent.rootZone))"
        )
        updateToolbarDebugLine()
    }

    private func updateFloatingFormatBarKeyboardHeight() {
        guard keyboardMonitor.isVisible else {
            recordToolbarLifecycle("height-skip-keyboard-hidden", details: toolbarLifecycleDetails())
            return
        }
        let height = keyboardMonitor.visibleHeight
        guard abs(floatingFormatBarKeyboardHeight - height) > 0.5 else {
            recordToolbarLifecycle("height-skip-same", details: "candidate=\(debugValue(height)) \(toolbarLifecycleDetails())")
            return
        }

        let oldHeight = floatingFormatBarKeyboardHeight
        withTransaction(Transaction(animation: nil)) {
            floatingFormatBarKeyboardHeight = height
        }
        recordToolbarLifecycle(
            "height-applied",
            details: "from=\(debugValue(oldHeight)) to=\(debugValue(height)) \(toolbarLifecycleDetails())"
        )
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

    private func recordToolbarLifecycle(_ stage: String, details: String) {
        ZoneEditorDebugStore.shared.recordToolbarLifecycle(
            editor: "flashcard",
            stage: stage,
            zoneID: selectedPath.flatMap { currentContent.zone(at: $0)?.id },
            pathID: selectedPath?.id,
            details: details
        )
    }

    private func toolbarLifecycleDetails() -> String {
        "kb=\(debugFlag(keyboardMonitor.isVisible)):\(debugValue(keyboardMonitor.visibleHeight)) dur=\(String(format: "%.3f", keyboardMonitor.animationDuration)) presented=\(debugFlag(isFloatingFormatBarPresented)) visible=\(debugFlag(isFloatingFormatBarVisible)) media=\(debugFlag(selectedZoneIsMedia)) barH=\(debugValue(floatingFormatBarKeyboardHeight)) top=\(debugOptionalValue(floatingFormatBarTopY)) opacity=\(String(format: "%.2f", floatingFormatBarOpacity)) task=\(floatingFormatBarPresentationTask == nil ? "nil" : "active") rev=\(toolbarVisibilityDebugRevision)"
    }

    private func debugFlag(_ value: Bool) -> String {
        value ? "1" : "0"
    }

    private func debugValue(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    private func debugOptionalValue(_ value: CGFloat?) -> String {
        value.map(debugValue) ?? "nil"
    }

    private func debugDuration(_ duration: Duration) -> String {
        let components = duration.components
        let milliseconds = components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
        return "\(milliseconds)ms"
    }

    private func recordEditorLifecycle(_ stage: String, details: String) -> Void {
        ZoneEditorDebugStore.shared.recordLayoutEvent(
            stage,
            zoneID: currentContent.rootZone.id,
            pathID: selectedPath?.id,
            details: "session=\(shortDebugID(editorSessionID)) activeSide=\(activeSide) frontObj=\(contentObjectDebugID(frontZoneContent)) backObj=\(contentObjectDebugID(backZoneContent)) selected=\(selectedPath?.id ?? "nil") front=\(zoneDebugSummary(frontZoneContent.rootZone)) back=\(zoneDebugSummary(backZoneContent.rootZone)) \(details)"
        )
    }

    private func contentObjectDebugID(_ content: ZoneCardContent) -> String {
        String(ObjectIdentifier(content).hashValue, radix: 16)
    }

    private func shortDebugID(_ id: UUID) -> String {
        String(id.uuidString.prefix(6))
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
            onDeleteZone: {
                deleteSelectedZone(at: path)
            },
            canPreview: hasSavableContent,
            showsPrimaryActions: false,
            showsZoneActions: true,
            usesMediaZoneToolbar: true,
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
        } else {
            editorCanvas(
                content: currentContent,
                selectedPath: selectedPathBinding,
                side: activeSide,
                safeTopInset: safeTopInset,
                rendersRichText: false
            )
        }
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
            bottomAccessoryTopY: isFloatingFormatBarVisible ? floatingFormatBarRenderedTopY : nil,
            scrollResetToken: activeSide,
            scrollRestorationRequest: activeSide == side ? scrollRestorationRequest : nil,
            rendersRichText: rendersRichText,
            showsZoneHeightGuides: true,
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
        guard !shouldSuppressCanvasEmptyTap() else { return }

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
            }
            focusManager.requestFocus(for: currentContent.rootZone.id)
            return
        }

        let insertion = insertionPoint(for: context)
        guard insertion.allowsInsertion else { return }

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
        recordToolbarLifecycle("dismiss-request", details: toolbarLifecycleDetails())
        suppressCanvasEmptyTapUntil = CFAbsoluteTimeGetCurrent() + 0.9
        scheduledFocusTask?.cancel()
        scheduledFocusTask = nil
        floatingFormatBarPresentationTask?.cancel()
        if floatingFormatBarPresentationTask != nil {
            recordToolbarLifecycle("dismiss-cancel-presentation-task", details: toolbarLifecycleDetails())
        }
        floatingFormatBarPresentationTask = nil
        focusManager.suppressFocusRequests(for: 0.9, releasesKeyboard: false)
        recordToolbarLifecycle("dismiss-fade-start", details: toolbarLifecycleDetails())
        withAnimation(EditorKeyboardAccessoryMotion.dismissAnimation) {
            isFloatingFormatBarPresented = false
        }
        toolbarVisibilityDebugRevision += 1
        updateToolbarDebugLine()

        floatingFormatBarPresentationTask = Task { @MainActor in
            recordToolbarLifecycle(
                "dismiss-keyboard-release-scheduled",
                details: "delay=\(debugDuration(EditorKeyboardAccessoryMotion.keyboardDismissDelay)) \(toolbarLifecycleDetails())"
            )
            try? await Task.sleep(for: EditorKeyboardAccessoryMotion.keyboardDismissDelay)
            guard !Task.isCancelled else { return }
            recordToolbarLifecycle("dismiss-keyboard-release-start", details: toolbarLifecycleDetails())
            focusManager.forceReleaseKeyboard()
            zoneController.forceReleaseKeyboard()
            zoneController.updateFocusedZone(nil)
            selectedPath = nil
            previewDirection = nil
            withTransaction(Transaction(animation: nil)) {
                floatingFormatBarKeyboardHeight = 0
                floatingFormatBarTopY = nil
            }
            toolbarVisibilityDebugRevision += 1
            recordToolbarLifecycle("dismiss-complete", details: toolbarLifecycleDetails())
            updateToolbarDebugLine()
        }
    }

    private func shouldSuppressCanvasEmptyTap() -> Bool {
        CFAbsoluteTimeGetCurrent() < suppressCanvasEmptyTapUntil
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
        let nextSelectedZoneID = focusTargetAfterDeletingZone(at: path)
        var selectedNeighborPath: ZonePath?
        let shouldKeepKeyboardActive = keyboardMonitor.isVisible && nextSelectedZoneID != nil
        let deletedZoneID = currentContent.zone(at: path)?.id

        if shouldKeepKeyboardActive, let nextSelectedZoneID {
            _ = focusManager.retainKeyboardForTextFocusTransfer(to: nextSelectedZoneID)
        }

        withAnimation(zoneListMutationAnimation) {
            currentContent.deleteZone(at: path)
            previewDirection = nil
            selectedNeighborPath = nextSelectedZoneID.flatMap {
                findPath(for: $0, in: currentContent.rootZone)
            }
            selectedPath = selectedNeighborPath
        }
        ZoneEditorDebugStore.shared.recordLayoutEvent(
            "zone-delete",
            zoneID: deletedZoneID,
            pathID: path.id,
            details: "activeSide=\(activeSide) next=\(selectedNeighborPath?.id ?? "nil") root=\(zoneDebugSummary(currentContent.rootZone))"
        )

        if let nextSelectedZoneID, selectedNeighborPath != nil {
            if shouldKeepKeyboardActive {
                focusManager.requestFocus(for: nextSelectedZoneID)
                zoneController.updateFocusedZone(nextSelectedZoneID)
            } else {
                zoneController.updateFocusedZone(nil)
            }
        } else {
            suppressCanvasEmptyTapUntil = CFAbsoluteTimeGetCurrent() + 0.9
            focusManager.suppressFocusRequests(for: 0.9)
            zoneController.forceReleaseKeyboard()
            zoneController.updateFocusedZone(nil)
        }
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

    private func insertionPoint(for context: ZoneEditorCanvasTapContext) -> (path: ZonePath, direction: AddDirection, allowsInsertion: Bool) {
        let sortedFrames = context.zoneFrames
            .filter { currentContent.zone(at: $0.path) != nil }
            .sorted {
                if abs($0.frame.midY - $1.frame.midY) > 1 {
                    return $0.frame.midY < $1.frame.midY
                }
                return $0.frame.midX < $1.frame.midX
            }

        guard let first = sortedFrames.first else {
            return (.root, .down, true)
        }

        let last = sortedFrames.last ?? first
        let bottomTapSlop: CGFloat = 24
        guard context.location.y >= last.frame.maxY - bottomTapSlop else {
            return (last.path, .down, false)
        }

        return (last.path, .down, true)
    }

    private func insertTextZoneWithFocus(relativeTo path: ZonePath?, direction: AddDirection) {
        var newZoneID: UUID?

        withAnimation(zoneListMutationAnimation) {
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

    private var zoneListMutationAnimation: Animation {
        .smooth(duration: 0.26, extraBounce: 0)
    }

    private func focusTargetAfterDeletingZone(at path: ZonePath) -> UUID? {
        guard let parentPath = path.parent,
              let childIndex = path.lastIndex,
              let siblings = currentContent.zone(at: parentPath)?.children,
              siblings.indices.contains(childIndex) else {
            return nil
        }

        let lowerIndex = childIndex + 1
        if siblings.indices.contains(lowerIndex) {
            return siblings[lowerIndex].id
        }

        let upperIndex = childIndex - 1
        if siblings.indices.contains(upperIndex) {
            return siblings[upperIndex].id
        }

        return nil
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

            previewTopButton

            Spacer(minLength: 0)

            sideSwitch

            Spacer(minLength: 0)

            renderTopButton

            Spacer(minLength: 0)

            saveTopButton
        }
        .topNavigationChrome(horizontalInset: topChromeHorizontalInset)
    }

    private var closeTopButton: some View {
        ChromeSoftCircleSymbolButton(
            systemName: "xmark",
            accessibilityLabel: localized("Close"),
            action: closeEditor,
            size: UIConstants.Size.actionButton,
            tint: topChromeUtilityForeground,
            backgroundTint: topChromeUtilityFill
        )
    }

    private var previewTopButton: some View {
        Button(action: openPreview) {
            ChromeSoftCircleSymbol(
                systemName: "eye",
                size: UIConstants.Size.actionButton,
                tint: hasSavableContent ? topChromeUtilityForeground : .secondary,
                backgroundTint: topChromeUtilityFill
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasSavableContent)
        .accessibilityLabel(localized("Preview"))
    }

    private var renderTopButton: some View {
        Button(action: toggleRenderedContent) {
            ChromeSoftCircleSymbol(
                systemName: "wand.and.stars",
                size: UIConstants.Size.actionButton,
                tint: hasSavableContent ? (showsRenderedContent ? .black : topChromeUtilityForeground) : .secondary,
                backgroundTint: showsRenderedContent ? accent : topChromeUtilityFill
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasSavableContent)
        .accessibilityLabel(localized("Render"))
    }

    private var saveTopButton: some View {
        Button(action: saveCard) {
            ChromeSoftCircleSymbol(
                systemName: "checkmark",
                size: UIConstants.Size.actionButton,
                tint: canSave ? successAccent : .secondary,
                backgroundTint: canSave ? topChromeUtilityFill : topChromeDisabledFill
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .accessibilityLabel(localized("Save"))
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
        scheduledRenderToggleTask?.cancel()

        if targetMode, keyboardMonitor.isVisible {
            prepareForRenderModeKeyboardDismiss()
            scheduledRenderToggleTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled else { return }
                applyRenderedContentMode(targetMode)
                scheduledRenderToggleTask = nil
            }
            return
        }

        applyRenderedContentMode(targetMode)
    }

    private func applyRenderedContentMode(_ targetMode: Bool) {
        guard showsRenderedContent != targetMode else { return }

        scrollTransition.currentMode = showsRenderedContent
        scrollTransition.targetMode = targetMode
        scrollTransition.restoringAfterModeSwitch = true
        scrollRestorationRequest = ZoneEditorScrollRestorationRequest(
            normalizedOffsetY: scrollTransition.currentNormalizedOffsetY,
            targetRenderedMode: targetMode
        )

        if targetMode {
            prepareForRenderModeKeyboardDismiss()
        }

        withTransaction(Transaction(animation: .smooth(duration: UIConstants.Animation.medium, extraBounce: 0))) {
            showsRenderedContent = targetMode
        }
    }

    private func prepareForRenderModeKeyboardDismiss() {
        suppressCanvasEmptyTapUntil = CFAbsoluteTimeGetCurrent() + 0.9
        cancelScheduledEditorTasks()
        focusManager.suppressFocusRequests(for: 0.9)
        zoneController.forceReleaseKeyboard()
        zoneController.updateFocusedZone(nil)
        selectedPath = nil
        previewDirection = nil
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
        suppressCanvasEmptyTapUntil = CFAbsoluteTimeGetCurrent() + 0.9
        focusManager.suppressFocusRequests(for: 0.9)
        zoneController.forceReleaseKeyboard()
        zoneController.updateFocusedZone(nil)
    }

    // MARK: - Zone Operations

    // MARK: - Photo/Sketch

    private func prepareForMediaZoneSelection() {
        scheduledFocusTask?.cancel()
        scheduledFocusTask = nil
        previewDirection = nil
        suppressCanvasEmptyTapUntil = CFAbsoluteTimeGetCurrent() + 0.9
        focusManager.suppressFocusRequests(for: 0.9)
        focusManager.forceReleaseKeyboard()
        zoneController.forceReleaseKeyboard()
        zoneController.updateFocusedZone(nil)
    }

    private func insertOrReplaceMediaZone(
        targetPath: ZonePath?,
        newZone: ZoneModel,
        source: String
    ) -> ZonePath? {
        let targetZone = targetPath.flatMap { currentContent.zone(at: $0) }
        var mediaPath: ZonePath?

        if let targetPath,
           canReplaceWithMedia(targetZone) {
            currentContent.updateZone(at: targetPath) { zone in
                zone = newZone
            }
            mediaPath = targetPath
            recordMediaImportDebug(source: source, action: "replace", path: targetPath, zoneID: newZone.id)
        } else {
            let referencePath = targetPath.flatMap { currentContent.zone(at: $0) == nil ? nil : $0 } ?? .root
            let newZoneID = currentContent.addZone(
                relativeTo: referencePath,
                direction: .down,
                newZone: newZone
            )
            mediaPath = findPath(for: newZoneID, in: currentContent.rootZone)
            recordMediaImportDebug(source: source, action: "insert", path: mediaPath, zoneID: newZoneID)
        }

        prepareForMediaZoneSelection()
        selectedPath = mediaPath
        return mediaPath
    }

    private func canReplaceWithMedia(_ zone: ZoneModel?) -> Bool {
        guard let zone, zone.isLeaf else { return false }
        if zone.isEditorMediaLeaf { return true }

        switch zone.contentType {
        case .empty:
            return true
        case .text, .code:
            return zone.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image, .sketch:
            return true
        }
    }

    private func recordMediaImportDebug(
        source: String,
        action: String,
        path: ZonePath?,
        zoneID: UUID
    ) {
        ZoneEditorDebugStore.shared.recordLayoutEvent(
            "media-import",
            zoneID: zoneID,
            pathID: path?.id,
            details: "source=\(source) action=\(action) activeSide=\(activeSide) root=\(zoneDebugSummary(currentContent.rootZone))"
        )
    }

    private func zoneDebugSummary(_ zone: ZoneModel) -> String {
        if zone.isLeaf {
            return "\(zone.contentType.rawValue)#\(zone.id.uuidString.prefix(6))"
        }

        let childSummary = (zone.children ?? [])
            .map { "\($0.contentType.rawValue)#\($0.id.uuidString.prefix(6))" }
            .joined(separator: ",")
        return "\(zone.direction.rawValue)[\(childSummary)]"
    }

    private func addPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        let targetPath = selectedPath
        let importID = UUID()
        let importStart = CFAbsoluteTimeGetCurrent()
        recordMediaImportPhase(
            "photo-import-start",
            importID: importID,
            targetPath: targetPath,
            details: "targetType=\(targetPath.flatMap { currentContent.zone(at: $0)?.contentType.rawValue } ?? "nil")"
        )

        Task {
            let loadStart = CFAbsoluteTimeGetCurrent()
            await MainActor.run {
                recordMediaImportPhase(
                    "photo-load-start",
                    importID: importID,
                    targetPath: targetPath,
                    details: "elapsed=\(formatMilliseconds(since: importStart))"
                )
            }
            if let data = try? await item.loadTransferable(type: Data.self) {
                let loadMS = elapsedMilliseconds(since: loadStart)
                await MainActor.run {
                    recordMediaImportPhase(
                        "photo-load-end",
                        importID: importID,
                        targetPath: targetPath,
                        details: "bytes=\(data.count) loadMs=\(loadMS) elapsed=\(formatMilliseconds(since: importStart))"
                    )
                }
                let compressStart = CFAbsoluteTimeGetCurrent()
                let compressedData = await Task.detached(priority: .userInitiated) {
                    data.compressedImageData(maxDimension: 1200, compressionQuality: 0.7) ?? data
                }.value
                let compressMS = elapsedMilliseconds(since: compressStart)

                await MainActor.run {
                    recordMediaImportPhase(
                        "photo-compress-end",
                        importID: importID,
                        targetPath: targetPath,
                        details: "input=\(data.count) output=\(compressedData.count) compressMs=\(compressMS) elapsed=\(formatMilliseconds(since: importStart))"
                    )
                    recordMediaImportPhase(
                        "photo-apply-start",
                        importID: importID,
                        targetPath: targetPath,
                        details: "rootBefore=\(zoneDebugSummary(currentContent.rootZone))"
                    )
                    _ = insertOrReplaceMediaZone(
                        targetPath: targetPath,
                        newZone: .image(data: compressedData),
                        source: "photo"
                    )
                    recordMediaImportPhase(
                        "photo-apply-end",
                        importID: importID,
                        targetPath: selectedPath,
                        details: "rootAfter=\(zoneDebugSummary(currentContent.rootZone)) totalMs=\(elapsedMilliseconds(since: importStart))"
                    )
                }
            } else {
                await MainActor.run {
                    ZoneEditorDebugStore.shared.recordLayoutEvent(
                        "media-import-failed",
                        zoneID: targetPath.flatMap { currentContent.zone(at: $0)?.id },
                        pathID: targetPath?.id,
                        details: "source=photo activeSide=\(activeSide) root=\(zoneDebugSummary(currentContent.rootZone))"
                    )
                    recordMediaImportPhase(
                        "photo-load-failed",
                        importID: importID,
                        targetPath: targetPath,
                        details: "elapsed=\(formatMilliseconds(since: importStart))"
                    )
                }
            }
            await MainActor.run {
                recordMediaImportPhase(
                    "photo-selection-clear",
                    importID: importID,
                    targetPath: selectedPath,
                    details: "elapsed=\(formatMilliseconds(since: importStart))"
                )
                selectedPhoto = nil
            }
        }
    }

    private func recordMediaImportPhase(
        _ stage: String,
        importID: UUID,
        targetPath: ZonePath?,
        details: String
    ) {
        ZoneEditorDebugStore.shared.recordLayoutEvent(
            stage,
            zoneID: targetPath.flatMap { currentContent.zone(at: $0)?.id },
            pathID: targetPath?.id,
            details: "import=\(shortDebugID(importID)) session=\(shortDebugID(editorSessionID)) activeSide=\(activeSide) \(details)"
        )
    }

    private func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
    }

    private func formatMilliseconds(since start: CFAbsoluteTime) -> String {
        "\(elapsedMilliseconds(since: start))ms"
    }

    private func addSketch(_ data: Data) {
        let targetPath = selectedPath

        Task {
            await MainActor.run {
                _ = insertOrReplaceMediaZone(
                    targetPath: targetPath,
                    newZone: .sketch(data: data),
                    source: "sketch"
                )
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

private enum EditorKeyboardAccessoryMotion {
    static let appearAnimation: Animation = .selectionToolbarSpring
    static let dismissAnimation: Animation = .selectionToolbarSpring
    static let cleanupDelay: Duration = .milliseconds(140)
    static let keyboardDismissDelay: Duration = .milliseconds(105)

    static func keyboardAppearMenuDelay(keyboardDuration: TimeInterval) -> Duration {
        .milliseconds(35)
    }
}

private struct EditorKeyboardAccessoryVisibilityModifier: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0.001)
            .blur(radius: isVisible ? 0 : 3)
            .scaleEffect(isVisible ? 1 : 0.7, anchor: .bottom)
            .allowsHitTesting(isVisible)
            .animation(
                isVisible
                    ? EditorKeyboardAccessoryMotion.appearAnimation
                    : EditorKeyboardAccessoryMotion.dismissAnimation,
                value: isVisible
            )
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

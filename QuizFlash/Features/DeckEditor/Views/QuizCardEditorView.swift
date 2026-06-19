//
//  QuizCardEditorView.swift
//  QuizFlash
//
//  Manual quiz-card authoring built on the shared zone editor stack.
//

import SwiftUI
import PhotosUI
import UIKit
import Combine

/// A type-aware editor for manual quiz authoring inside the deck editor flow.
struct QuizCardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(KeyboardMonitor.self) private var keyboardMonitor

    @State private var highlightContext: HighlightContext?
    @StateObject private var session: QuizEditorSession
    @State private var activeEditor: QuizEditorTarget = .question
    @State private var previewDirection: AddDirection? = nil
    @State private var showSketchModal = false
    @State private var showPreview = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var markedCorrectIndicatorChoiceID: UUID?
    @State private var markedCorrectIndicatorTask: Task<Void, Never>?
    @State private var pendingDeleteChoiceID: UUID?
    @State private var pendingDeleteTask: Task<Void, Never>?
    @State private var floatingFormatBarKeyboardHeight: CGFloat = 0
    @State private var isFloatingFormatBarPresented = false
    @State private var floatingFormatBarPresentationTask: Task<Void, Never>?
    @State private var keyboardDebugRevision = 0
    @State private var toolbarVisibilityDebugRevision = 0
    @State private var quizScrollDriver = ZoneEditorScrollDriver()
    @State private var scheduledCaretScrollTask: Task<Void, Never>?
    @State private var keyboardDismissPadding: CGFloat = 0
    @State private var isQuizDebugEnabled = false
    @State private var activeQuizCaretPathID: String?
    @State private var activeQuizCaretWindowRect: CGRect?
    @State private var activeQuizCaretSource: ZoneEditorCaretScrollSource?
    @State private var activeQuizCaretTraceID: String?
    @State private var activeQuizCaretAnchorY: CGFloat?
    @State private var activeQuizCaretEditorHeight: CGFloat?
    @State private var quizViewportScreenFrame: CGRect = .zero
    @State private var quizCaretScrollGate = QuizCaretScrollGate()
    @State private var quizCaretScrollScheduleSequence = 0

    private let textSize: FlashcardTextSize
    private let onSave: (QuizCardContent) -> Void

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var successAccent: Color { ThemeManager.shared.successPrimary }
    private var topChromeUtilityFill: Color { Color(uiColor: .secondarySystemBackground) }
    private var topChromeUtilityBorder: Color { Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.10) }
    private var topChromeUtilityForeground: Color { accent }
    private var topChromeDisabledFill: Color { Color(uiColor: .tertiarySystemBackground) }
    private var focusManager = ZoneFocusManager.shared
    private var zoneController = ZoneController.shared
    private var locale: Locale { appPreferences.resolvedLocale }
    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var editorTextScale: CGFloat { CGFloat(textSize.playModeScale) }
    private var topChromeHorizontalInset: CGFloat {
        isCompact ? UIConstants.Layout.compactScreenEdgeInset : UIConstants.Layout.screenEdgeInset
    }
    private var isFormatBarVisible: Bool { isFloatingFormatBarVisible }
    private var isQuizDebugAvailable: Bool { AppFeatures.current.showsVisualDebugOverlays }
    private var isQuizDebugRecordingActive: Bool { isQuizDebugAvailable && isQuizDebugEnabled }
    private var bottomContentPadding: CGFloat {
        let chromePadding: CGFloat = isFloatingFormatBarVisible ? 148 : 96
        return chromePadding + keyboardDismissPadding
    }

    private var keyboardContentPadding: CGFloat {
        guard keyboardMonitor.isVisible else { return 0 }
        let keyboardSettlePadding: CGFloat = 64
        return max(keyboardMonitor.visibleHeight + keyboardSettlePadding, 0)
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private func localizedFormat(_ value: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = AppLocalization.string(value, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    init(
        initialContent: QuizCardContent,
        searchQuery: String? = nil,
        textSize: FlashcardTextSize,
        onSave: @escaping (QuizCardContent) -> Void
    ) {
        self.textSize = textSize
        _session = StateObject(wrappedValue: QuizEditorSession(initialContent: initialContent))

        if let query = searchQuery, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _highlightContext = State(initialValue: HighlightContext(query: query))
        } else {
            _highlightContext = State(initialValue: nil)
        }

        self.onSave = onSave
    }

    private var questionContent: ZoneCardContent { session.questionContent }

    private var questionSelectedPath: ZonePath? {
        get { session.questionSelectedPath }
        nonmutating set { session.questionSelectedPath = newValue }
    }

    private var choices: [QuizChoiceEditorItem] {
        get { session.choices }
        nonmutating set { session.choices = newValue }
    }

    private var explanationContent: ZoneCardContent? {
        get { session.explanationContent }
        nonmutating set { session.explanationContent = newValue }
    }

    private var explanationSelectedPath: ZonePath? {
        get { session.explanationSelectedPath }
        nonmutating set { session.explanationSelectedPath = newValue }
    }

    private var isExplanationExpanded: Bool {
        get { session.isExplanationExpanded }
        nonmutating set { session.isExplanationExpanded = newValue }
    }

    private var currentContent: ZoneCardContent? {
        switch activeEditor {
        case .question:
            return questionContent
        case .choice(let choiceID):
            return choice(for: choiceID)?.content
        case .explanation:
            return explanationContent
        }
    }

    private var currentSelectedPath: ZonePath? {
        get {
            switch activeEditor {
            case .question:
                return questionSelectedPath
            case .choice(let choiceID):
                return choice(for: choiceID)?.selectedPath
            case .explanation:
                return explanationSelectedPath
            }
        }
        nonmutating set {
            switch activeEditor {
            case .question:
                questionSelectedPath = newValue
            case .choice(let choiceID):
                choice(for: choiceID)?.selectedPath = newValue
            case .explanation:
                explanationSelectedPath = newValue
            }
        }
    }

    private var validationMessage: String? {
        if !questionContent.hasContent {
            return localized("Add a question before saving.")
        }

        if choices.count < 2 {
            return localized("Add at least two answers.")
        }

        if choices.contains(where: { !$0.content.hasContent }) {
            return localized("Fill in every answer before saving.")
        }

        if !choices.contains(where: \.isCorrect) {
            return localized("Mark at least one correct answer.")
        }

        return nil
    }

    private var canSave: Bool {
        validationMessage == nil
    }
    private var canUseInteractiveDismiss: Bool {
        !showSketchModal && !isPhotoPickerPresented
    }
    private var currentQuizContent: QuizCardContent {
        let cleanedExplanationZone: ZoneModel?
        if let explanationContent, explanationContent.hasContent {
            cleanedExplanationZone = explanationContent.rootZone
        } else {
            cleanedExplanationZone = nil
        }

        return QuizCardContent(
            questionZone: questionContent.rootZone,
            choices: choices.map {
                QuizChoiceDraft(
                    id: $0.id,
                    contentZone: $0.content.rootZone,
                    isCorrect: $0.isCorrect
                )
            },
            explanationZone: cleanedExplanationZone,
            allowsMultipleCorrect: choices.filter(\.isCorrect).count > 1
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let safeTopInset = proxy.safeAreaInsets.top
            let contentWidth = max(proxy.size.width - 16, 1)

            ZStack(alignment: .top) {
                editorBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
                        questionSection(availableWidth: contentWidth)
                        quizZoneSeparator
                        answersSection(availableWidth: contentWidth)
                        quizZoneSeparator
                        addAnswerButton
                        quizZoneSeparator
                        explanationSection(availableWidth: contentWidth)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, UIConstants.Layout.deckNavigationTopPadding + UIConstants.Size.actionButton + UIConstants.Spacing.large)
                    .padding(.bottom, bottomContentPadding)
                }
                .background {
                    ZoneEditorScrollViewLocator { scrollView in
                        quizScrollDriver.attach(scrollView)
                        quizScrollDriver.setTopInset(0)
                        quizScrollDriver.resetBottomInset()
                    }
                    GeometryReader { geometry in
                        Color.clear
                            .onGeometryChange(for: CGRect.self) { proxy in
                                proxy.frame(in: .global)
                            } action: { frame in
                                quizViewportScreenFrame = frame
                            }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .screenEdgeShadow(
                    topHeight: editorTopBlurHeight(safeTopInset: safeTopInset),
                    debugScreenID: "quiz.editor",
                    style: .progressiveBlur()
                )
                .onScrollViewEmptySpaceTap(isActive: isFormatBarVisible) {
                    dismissFormatBar()
                }
                .onReceive(NotificationCenter.default.publisher(for: .zoneEditorCaretMoved)) { notification in
                    handleCaretMovedNotification(notification)
                }
                .overlay(alignment: .topLeading) {
                    quizScrollDebugOverlay
                }

                topChrome
                    .zIndex(20)

                floatingFormatBar
                quizDebugControls(safeTopInset: safeTopInset)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, item in
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
            if isVisible {
                withTransaction(Transaction(animation: nil)) {
                    keyboardDismissPadding = keyboardContentPadding
                }
                scheduleStoredQuizCaretScroll(delays: [.milliseconds(24), .milliseconds(104)])
            } else {
                scheduledCaretScrollTask?.cancel()
                scheduledCaretScrollTask = nil
                activeQuizCaretSource = nil
                activeQuizCaretAnchorY = nil
                activeQuizCaretEditorHeight = nil
                quizScrollDriver.resetBottomInset()
                withAnimation(EditorKeyboardAccessoryMotion.keyboardPaddingDismissAnimation) {
                    keyboardDismissPadding = 0
                }
            }
        }
        .onChange(of: keyboardMonitor.visibleHeight) { _, _ in
            recordToolbarLifecycle(
                "keyboard-height-change",
                details: "height=\(debugValue(keyboardMonitor.visibleHeight)) \(toolbarLifecycleDetails())"
            )
            if keyboardMonitor.isVisible {
                withTransaction(Transaction(animation: nil)) {
                    keyboardDismissPadding = keyboardContentPadding
                }
            }
            updateFloatingFormatBarKeyboardHeight()
            scheduleStoredQuizCaretScroll(delays: [.milliseconds(24), .milliseconds(104)])
        }
        .onChange(of: isQuizDebugEnabled) { _, isEnabled in
            if isEnabled {
                ZoneEditorDebugStore.shared.setLayoutRecordingEnabled(true)
                recordQuizScroll(
                    "quiz.debug-toggle-on",
                    pathID: currentSelectedPath?.id,
                    details: quizScrollDetails(proposedDelta: nil)
                )
            } else {
                recordQuizScroll(
                    "quiz.debug-toggle-off",
                    pathID: currentSelectedPath?.id,
                    details: quizScrollDetails(proposedDelta: nil)
                )
                ZoneEditorDebugStore.shared.setLayoutRecordingEnabled(false)
                quizScrollDriver.setDebugTraceContext(nil)
            }
        }
        .fullScreenCover(isPresented: $showSketchModal) {
            CanvasModalView { data in
                addSketch(data)
            }
        }
        .fullScreenSheet(
            isPresented: $showPreview,
            configuration: .sheet(
                heightMode: .fullScreen,
                showsDefaultTopProgressiveBlur: false
            )
        ) { safeArea in
            CardPreviewModeView(
                content: .quiz(currentQuizContent),
                safeAreaInsets: safeArea,
                textSize: textSize
            )
        } background: {
            Color.clear
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: currentSelectedPath)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: previewDirection)
        .swipeBack(enabled: canUseInteractiveDismiss) {
            dismiss()
        }
        .onAppear {
            ZoneEditorDebugStore.shared.setLayoutRecordingEnabled(isQuizDebugRecordingActive)
            recordQuizScroll(
                "quiz.editor-appear",
                pathID: currentSelectedPath?.id,
                details: quizScrollDetails(proposedDelta: nil)
            )
        }
        .onDisappear {
            quizScrollDriver.setDebugTraceContext(nil)
            recordQuizScroll(
                "quiz.editor-disappear",
                pathID: currentSelectedPath?.id,
                details: quizScrollDetails(proposedDelta: nil)
            )
            ZoneEditorDebugStore.shared.setLayoutRecordingEnabled(false)
            markedCorrectIndicatorTask?.cancel()
            markedCorrectIndicatorTask = nil
            pendingDeleteTask?.cancel()
            pendingDeleteTask = nil
            floatingFormatBarPresentationTask?.cancel()
            floatingFormatBarPresentationTask = nil
            scheduledCaretScrollTask?.cancel()
            scheduledCaretScrollTask = nil
            keyboardDismissPadding = 0
            activeQuizCaretPathID = nil
            activeQuizCaretWindowRect = nil
            activeQuizCaretSource = nil
            activeQuizCaretAnchorY = nil
            activeQuizCaretEditorHeight = nil
            quizScrollDriver.detach()
        }
    }

    @ViewBuilder
    private var floatingFormatBar: some View {
        ZStack {
            if let content = currentContent, let path = formatBarPath {
                VStack {
                    Spacer(minLength: 0)

                    formatBar(content: content, path: path)
                        .padding(.vertical, 4)
                        .padding(.horizontal, isCompact ? 16 : topChromeHorizontalInset)
                        .padding(.bottom, floatingToolbarBaseBottomInset)
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
              let content = currentContent,
              let path = currentSelectedPath,
              let selectedZone = content.zone(at: path) else {
            return false
        }

        return selectedZone.isEditorMediaLeaf || keyboardMonitor.isVisible
    }

    private var floatingFormatBarOpacity: Double {
        isFloatingFormatBarVisible ? 1 : 0
    }

    private var formatBarPath: ZonePath? {
        guard let content = currentContent else { return nil }
        if let selectedPath = currentSelectedPath, content.zone(at: selectedPath) != nil {
            return selectedPath
        }

        return firstLeafPath(in: content.rootZone, currentPath: .root) ?? .root
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

    private var floatingToolbarAccessoryHeight: CGFloat {
        if isFloatingFormatBarVisible {
            return 96
        }

        guard keyboardMonitor.isVisible,
              currentSelectedPath != nil,
              !selectedZoneIsMedia else {
            return 0
        }

        return 96
    }

    private var selectedZoneIsMedia: Bool {
        guard let content = currentContent,
              let path = currentSelectedPath,
              let selectedZone = content.zone(at: path) else {
            return false
        }

        return selectedZone.isEditorMediaLeaf
    }

    @ViewBuilder
    private func formatBar(content: ZoneCardContent, path: ZonePath) -> some View {
        EditorFormatMenuBar(
            content: content,
            path: path,
            onChoosePhoto: {
                isPhotoPickerPresented = true
            },
            onSketch: {
                showSketchModal = true
            },
            canPreview: questionContent.hasContent || choices.contains { $0.content.hasContent },
            showsPrimaryActions: false,
            showsZoneActions: false,
            onPreview: {
                openPreview()
            },
            onClose: {
                dismissFormatBar()
            }
        )
        .onAppear {
            recordToolbarLifecycle("formatbar-appear", details: "path=\(path.id) \(toolbarLifecycleDetails())")
        }
        .onDisappear {
            recordToolbarLifecycle("formatbar-disappear", details: "path=\(path.id) \(toolbarLifecycleDetails())")
        }
    }

    private func dismissFormatBar() {
        recordToolbarLifecycle("dismiss-request", details: toolbarLifecycleDetails())
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
            currentSelectedPath = nil
            previewDirection = nil
            withTransaction(Transaction(animation: nil)) {
                floatingFormatBarKeyboardHeight = 0
            }
            toolbarVisibilityDebugRevision += 1
            recordToolbarLifecycle("dismiss-complete", details: toolbarLifecycleDetails())
        }
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
                }
            } else {
                recordToolbarLifecycle("appear-immediate-start", details: toolbarLifecycleDetails())
                withAnimation(EditorKeyboardAccessoryMotion.appearAnimation) {
                    isFloatingFormatBarPresented = true
                }
                toolbarVisibilityDebugRevision += 1
                recordToolbarLifecycle("appear-immediate-presented", details: toolbarLifecycleDetails())
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
                }
                recordToolbarLifecycle("hide-cleanup", details: toolbarLifecycleDetails())
            }
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

        recordToolbarLifecycle(
            "selection-change",
            details: "source=\(source) \(toolbarLifecycleDetails())"
        )
        updateFloatingFormatBarPresentation(isKeyboardVisible: keyboardMonitor.isVisible)
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

    private func recordToolbarLifecycle(_ stage: String, details: @autoclosure () -> String) {
        guard isQuizDebugRecordingActive else { return }
        ZoneEditorDebugStore.shared.recordToolbarLifecycle(
            editor: "quiz",
            stage: stage,
            zoneID: currentSelectedZoneID,
            pathID: currentSelectedPath?.id,
            details: details()
        )
    }

    private var currentSelectedZoneID: UUID? {
        guard let content = currentContent,
              let path = currentSelectedPath else {
            return nil
        }
        return content.zone(at: path)?.id
    }

    private func toolbarLifecycleDetails() -> String {
        "target=\(debugTargetID(activeEditor)) kb=\(debugFlag(keyboardMonitor.isVisible)):\(debugValue(keyboardMonitor.visibleHeight)) dur=\(String(format: "%.3f", keyboardMonitor.animationDuration)) presented=\(debugFlag(isFloatingFormatBarPresented)) visible=\(debugFlag(isFloatingFormatBarVisible)) media=\(debugFlag(selectedZoneIsMedia)) barH=\(debugValue(floatingFormatBarKeyboardHeight)) opacity=\(String(format: "%.2f", floatingFormatBarOpacity)) task=\(floatingFormatBarPresentationTask == nil ? "nil" : "active") rev=\(toolbarVisibilityDebugRevision) selected=\(currentSelectedPath?.id ?? "nil")"
    }

    private func debugTargetID(_ target: QuizEditorTarget) -> String {
        switch target {
        case .question:
            return "question"
        case .choice(let id):
            return "choice:\(String(id.uuidString.prefix(6)))"
        case .explanation:
            return "explanation"
        }
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

    private func debugRect(_ rect: CGRect) -> String {
        "\(debugValue(rect.minX)),\(debugValue(rect.minY)),\(debugValue(rect.width))x\(debugValue(rect.height))"
    }

    private func debugDuration(_ duration: Duration) -> String {
        let components = duration.components
        let milliseconds = components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
        return "\(milliseconds)ms"
    }

    private var topChrome: some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
            closeTopButton

            Spacer(minLength: 0)

            previewTopButton

            Spacer(minLength: 0)

            Button(action: saveCard) {
                ChromeSoftCircleSymbol(
                    systemName: "checkmark",
                    size: UIConstants.Size.actionButton,
                    symbolSize: UIConstants.Size.navigationChromeIcon,
                    tint: canSave ? .black : .secondary,
                    backgroundTint: canSave ? successAccent : topChromeDisabledFill
                )
            }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .accessibilityLabel(localized("Save"))
        }
            .topNavigationChrome(horizontalInset: topChromeHorizontalInset)
    }

    @ViewBuilder
    private func quizDebugControls(safeTopInset: CGFloat) -> some View {
        if isQuizDebugAvailable {
            VStack {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            isQuizDebugEnabled.toggle()
                        }
                    } label: {
                        Text(isQuizDebugEnabled ? "DBG ON" : "DBG")
                            .font(.caption2.monospaced().weight(.bold))
                            .foregroundStyle(isQuizDebugEnabled ? .black : .orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                isQuizDebugEnabled ? Color.orange : Color.black.opacity(0.62),
                                in: Capsule(style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isQuizDebugEnabled ? "Disable quiz editor debug" : "Enable quiz editor debug")

                    if isQuizDebugEnabled {
                        Button {
                            UIPasteboard.general.string = quizDebugReport
                        } label: {
                            Text("COPY DEBUG")
                                .font(.caption2.monospaced().weight(.bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color.orange, in: Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Copy quiz editor debug")
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.top, safeTopInset + UIConstants.Layout.deckNavigationTopPadding + UIConstants.Size.actionButton + 8)
            .padding(.trailing, topChromeHorizontalInset)
            .zIndex(60)
        }
    }

    private var quizDebugReport: String {
        """
        QuizFlash Quiz Editor Debug
        timestamp: \(ISO8601DateFormatter().string(from: Date()))
        target: \(debugTargetID(activeEditor))
        selectedPath: \(currentSelectedPath?.id ?? "nil")
        selectedZone: \(shortDebugID(currentSelectedZoneID))
        focusedZone: \(shortDebugID(focusManager.focusedZoneID))
        keyboard: visible=\(debugFlag(keyboardMonitor.isVisible)) height=\(debugValue(keyboardMonitor.visibleHeight)) duration=\(debugValue(keyboardMonitor.animationDuration))
        toolbar: accessory=\(debugValue(floatingToolbarAccessoryHeight))
        viewport: \(debugRect(quizViewportScreenFrame))
        scroll: offset=\(debugValue(quizScrollDriver.currentNormalizedOffsetY)) insetBottom=\(debugValue(quizScrollDriver.currentContentInsetBottom)) adjustedBottom=\(debugValue(quizScrollDriver.currentAdjustedContentInsetBottom))
        caret: path=\(activeQuizCaretPathID ?? "nil") source=\(activeQuizCaretSource?.rawValue ?? "nil") rect=\(activeQuizCaretWindowRect.map(debugRect) ?? "nil") anchor=\(debugOptionalValue(activeQuizCaretAnchorY)) editorHeight=\(debugOptionalValue(activeQuizCaretEditorHeight))

        LAYOUT / RENDER TIMELINE
        \(ZoneEditorDebugStore.shared.layoutTraceReport)
        """
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
                tint: accent,
                backgroundTint: topChromeUtilityFill
            )
        }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("Preview"))
    }

    private func questionSection(availableWidth: CGFloat) -> some View {
        QuizZoneSectionCard(
            content: questionContent,
            selectedPath: binding(for: .question),
            highlightContext: highlightContext,
            fontScale: editorTextScale,
            availableWidth: availableWidth,
            previewDirection: $previewDirection,
            onSelectionChange: {
                activateEditor(.question)
            }
        ) {
            activateEditor(.question)
        }
    }

    private var quizZoneSeparator: some View {
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private func answersSection(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                VStack(spacing: UIConstants.Spacing.standard) {
                    choiceHeader(
                        index: index,
                        choiceID: choice.id,
                        isCorrect: choice.isCorrect,
                        isDeletePending: pendingDeleteChoiceID == choice.id,
                        onToggleCorrect: {
                            toggleCorrect(for: choice.id)
                        },
                        onDelete: {
                            handleDeleteTap(for: choice.id)
                        }
                    )

                    QuizChoiceCard(
                        choice: choice,
                        highlightContext: highlightContext,
                        fontScale: editorTextScale,
                        availableWidth: availableWidth,
                        previewDirection: $previewDirection,
                        onActivate: {
                            activateEditor(.choice(choice.id))
                        },
                        onSelectionChange: {
                            if choice.selectedPath != nil {
                                activateEditor(.choice(choice.id))
                            } else {
                                handleSelectedPathChange(source: "choice:\(String(choice.id.uuidString.prefix(6)))")
                            }
                        }
                    )
                }

                if index < choices.count - 1 {
                    quizZoneSeparator
                        .padding(.vertical, UIConstants.Spacing.standard)
                }
            }
        }
    }

    private var addAnswerButton: some View {
        addSectionButton(localized("Add Answer"), systemImage: "plus") {
            addChoice()
        }
    }

    private func addSectionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, UIConstants.Spacing.large)
                .padding(.vertical, UIConstants.Spacing.small)
                .background(accent.opacity(0.10), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(accent.opacity(0.18), lineWidth: 1)
                }
        }
        .buttonStyle(QuizEditorAddButtonStyle())
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func choiceHeader(
        index: Int,
        choiceID: UUID,
        isCorrect: Bool,
        isDeletePending: Bool,
        onToggleCorrect: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
                Text(String(index + 1))
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 18, alignment: .trailing)

                correctToggleButton(isCorrect: isCorrect, action: onToggleCorrect)

                if markedCorrectIndicatorChoiceID == choiceID {
                    Text(localized("Marked as correct"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(successAccent)
                        .transition(.scale(scale: 0.86, anchor: .leading).combined(with: .opacity))
                }
            }

            Spacer(minLength: UIConstants.Spacing.standard)

            deleteConfirmationButton(isPending: isDeletePending, action: onDelete)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deleteConfirmationButton(isPending: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isPending ? "arrow.up.trash.fill" : "trash.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.red)
            .frame(width: 26, height: 26)
            .contentShape(Circle())
            .scaleEffect(isPending ? 1.7 : 1)
        }
        .buttonStyle(QuizEditorControlButtonStyle(isActive: isPending))
        .animation(.easeOut(duration: 0.16), value: isPending)
        .accessibilityLabel(isPending ? localized("Delete?") : localized("Delete"))
    }

    private func correctToggleButton(isCorrect: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(successAccent.opacity(isCorrect ? 1 : 0.10))

                Circle()
                    .stroke(successAccent.opacity(isCorrect ? 0 : 0.85), lineWidth: 2.4)

                if isCorrect {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Color.black.opacity(0.75))
                }
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(QuizEditorControlButtonStyle(isActive: isCorrect))
        .accessibilityLabel(isCorrect ? localized("Correct") : localized("Mark Correct"))
    }

    @ViewBuilder
    private func explanationSection(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            if let explanationContent {
                if isExplanationExpanded {
                    HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
                        Text(localized("Explanation"))
                            .font(.caption.weight(.heavy))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: UIConstants.Spacing.standard)

                        Button(role: .destructive) {
                            removeExplanation()
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.red)
                                .frame(width: 26, height: 26)
                                .contentShape(Circle())
                        }
                        .buttonStyle(QuizEditorControlButtonStyle())
                        .accessibilityLabel(localized("Delete"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    QuizZoneSectionCard(
                        content: explanationContent,
                        selectedPath: binding(for: .explanation),
                        highlightContext: highlightContext,
                        fontScale: editorTextScale,
                        availableWidth: availableWidth,
                        previewDirection: $previewDirection,
                        onSelectionChange: {
                            activateEditor(.explanation)
                        }
                    ) {
                        activateEditor(.explanation)
                    }
                } else {
                    Button {
                        isExplanationExpanded = true
                        activateEditor(.explanation)
                    } label: {
                        HStack(spacing: UIConstants.Spacing.small) {
                            Image(systemName: "text.quote")
                                .foregroundStyle(accent)

                            Text(explanationContent.rootZone.previewText(maxLength: 90))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)

                            Spacer()

                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                            .padding(UIConstants.Spacing.standard)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
                    }
                        .buttonStyle(.plain)
                }
            } else {
                addSectionButton(localized("Add Explanation"), systemImage: "plus.bubble") {
                    addExplanation()
                }
            }
        }
    }

    private func binding(for target: QuizEditorTarget) -> Binding<ZonePath?> {
        Binding(
            get: { selectedPath(for: target) },
            set: { newValue in
                setSelectedPath(newValue, for: target)
            }
        )
    }

    private func selectedPath(for target: QuizEditorTarget) -> ZonePath? {
        switch target {
        case .question:
            return questionSelectedPath
        case .choice(let choiceID):
            return choice(for: choiceID)?.selectedPath
        case .explanation:
            return explanationSelectedPath
        }
    }

    private func setSelectedPath(
        _ path: ZonePath?,
        for target: QuizEditorTarget,
        recordsSelection: Bool = true
    ) {
        switch target {
        case .question:
            questionSelectedPath = path
            if recordsSelection {
                handleSelectedPathChange(source: "question")
            }
        case .choice(let choiceID):
            choice(for: choiceID)?.selectedPath = path
            if recordsSelection {
                handleSelectedPathChange(source: "choice:\(String(choiceID.uuidString.prefix(6)))")
            }
        case .explanation:
            explanationSelectedPath = path
            if recordsSelection {
                handleSelectedPathChange(source: "explanation")
            }
        }
    }

    private func activateEditor(_ target: QuizEditorTarget) {
        if activeEditor != target {
            setSelectedPath(nil, for: activeEditor, recordsSelection: false)
            previewDirection = nil
        }

        activeEditor = target

        if selectedPath(for: target) == nil {
            setSelectedPath(.root, for: target)
        } else {
            handleSelectedPathChange(source: "activate:\(debugTargetID(target))")
        }
    }

    private func handleCaretMovedNotification(_ notification: Notification) {
        let notificationPathID = notification.userInfo?[ZoneEditorCaretScrollNotification.pathIDKey] as? String
        let caretRect = caretWindowRect(from: notification)
        let source = caretScrollSource(from: notification)
        let traceID = caretTraceID(from: notification)
        let caretAnchorY = caretAnchorY(from: notification)
        let caretEditorHeight = caretEditorHeight(from: notification)
        recordQuizScroll(
            "quiz.scroll-caret-received",
            pathID: notificationPathID,
            details: "trace=\(traceID) source=\(source.rawValue) rect=\(caretRect.map(debugRect) ?? "nil") anchor=\(debugOptionalValue(caretAnchorY)) editorHeight=\(debugOptionalValue(caretEditorHeight)) \(quizScrollDetails(proposedDelta: nil))"
        )
        recordQuizScrollState(
            "quiz.scroll-state-caret-received",
            pathID: notificationPathID,
            extra: "trace=\(traceID) source=\(source.rawValue) rect=\(caretRect.map(debugRect) ?? "nil") anchor=\(debugOptionalValue(caretAnchorY)) editorHeight=\(debugOptionalValue(caretEditorHeight))"
        )

        guard let notificationPathID,
              currentSelectedPath?.id == notificationPathID,
              focusManager.focusedZoneID == currentSelectedZoneID else {
            recordQuizScroll(
                "quiz.scroll-skip-not-active-path",
                pathID: notificationPathID,
                details: "activeSelected=\(currentSelectedPath?.id ?? "nil") focused=\(shortDebugID(focusManager.focusedZoneID)) currentZone=\(shortDebugID(currentSelectedZoneID)) \(quizScrollDetails(proposedDelta: nil))"
            )
            return
        }

        quizScrollDriver.setDebugTraceContext(
            isQuizDebugRecordingActive
                ? "caret source=\(source.rawValue) trace=\(traceID) path=\(notificationPathID) rect=\(caretRect.map(debugRect) ?? "nil")"
                : nil
        )

        if source == .newline {
            quizScrollDriver.releaseOffsetLock()
            recordQuizScroll(
                "quiz.scroll-release-newline-lock",
                pathID: notificationPathID,
                details: "trace=\(traceID) \(quizScrollDetails(proposedDelta: nil))"
            )
        }

        guard shouldScrollQuizCaret(for: source) else {
            if source == .textInput,
               activeQuizCaretSource == .newline,
               keyboardMonitor.isVisible,
               let caretRect,
               caretRect.maxY > quizVisibleBottomWindowY(bottomBuffer: quizNewlineCaretBottomChromeBuffer) + 1 {
                activeQuizCaretPathID = notificationPathID
                activeQuizCaretWindowRect = caretRect
                activeQuizCaretAnchorY = caretAnchorY
                activeQuizCaretEditorHeight = caretEditorHeight
                recordQuizScroll(
                    "quiz.scroll-continue-newline-after-text-input",
                    pathID: notificationPathID,
                    details: "source=textInput rect=\(debugRect(caretRect)) \(quizScrollDetails(proposedDelta: nil))"
                )
                return
            }

            scheduledCaretScrollTask?.cancel()
            scheduledCaretScrollTask = nil
            recordQuizScroll(
                "quiz.scroll-task-cancel-nonscroll-source",
                pathID: notificationPathID,
                details: "source=\(source.rawValue) schedule=\(quizCaretScrollScheduleSequence) \(quizScrollDetails(proposedDelta: nil))"
            )
            activeQuizCaretPathID = notificationPathID
            activeQuizCaretWindowRect = caretRect
            activeQuizCaretSource = source
            activeQuizCaretTraceID = traceID
            activeQuizCaretAnchorY = caretAnchorY
            activeQuizCaretEditorHeight = caretEditorHeight
            recordQuizScroll(
                "quiz.scroll-skip-text-input",
                pathID: notificationPathID,
                details: "source=\(source.rawValue) rect=\(caretRect.map(debugRect) ?? "nil") \(quizScrollDetails(proposedDelta: nil))"
            )
            return
        }

        if let caretRect,
           quizCaretScrollGate.shouldIgnoreCaretUpdate(pathID: notificationPathID, rect: caretRect) {
            recordQuizScroll(
                "quiz.scroll-skip-duplicate-caret",
                pathID: notificationPathID,
                details: "source=\(source.rawValue) rect=\(debugRect(caretRect)) \(quizScrollDetails(proposedDelta: nil))"
            )
            return
        }

        activeQuizCaretPathID = notificationPathID
        activeQuizCaretWindowRect = caretRect
        activeQuizCaretSource = source
        activeQuizCaretTraceID = traceID
        activeQuizCaretAnchorY = caretAnchorY
        activeQuizCaretEditorHeight = caretEditorHeight

        guard keyboardMonitor.isVisible else {
            recordQuizScroll(
                "quiz.scroll-skip-visible",
                pathID: notificationPathID,
                details: "source=\(source.rawValue) reason=keyboard-hidden \(quizScrollDetails(proposedDelta: nil))"
            )
            return
        }

        guard caretRect != nil else {
            recordQuizScroll(
                "quiz.scroll-skip-visible",
                pathID: notificationPathID,
                details: "source=\(source.rawValue) reason=no-caret-rect \(quizScrollDetails(proposedDelta: nil))"
            )
            return
        }

        scheduleStoredQuizCaretScroll(delays: quizCaretScrollDelays(for: source))
    }

    private func scheduleStoredQuizCaretScroll(delays: [Duration]) {
        guard !delays.isEmpty else { return }
        guard keyboardMonitor.isVisible else {
            recordQuizScroll(
                "quiz.scroll-schedule-skip",
                pathID: activeQuizCaretPathID,
                details: "reason=keyboard-hidden \(quizScrollDetails(proposedDelta: nil))"
            )
            return
        }
        guard activeQuizCaretPathID != nil else {
            recordQuizScroll(
                "quiz.scroll-schedule-skip",
                pathID: nil,
                details: "reason=no-active-caret \(quizScrollDetails(proposedDelta: nil))"
            )
            return
        }
        guard activeQuizCaretSource.map(shouldScrollQuizCaret) == true else {
            recordQuizScroll(
                "quiz.scroll-schedule-skip",
                pathID: activeQuizCaretPathID,
                details: "reason=source source=\(activeQuizCaretSource?.rawValue ?? "nil") \(quizScrollDetails(proposedDelta: nil))"
            )
            return
        }
        quizCaretScrollScheduleSequence += 1
        let scheduleID = quizCaretScrollScheduleSequence
        if scheduledCaretScrollTask != nil {
            recordQuizScroll(
                "quiz.scroll-task-cancel",
                pathID: activeQuizCaretPathID,
                details: "reason=reschedule newSchedule=\(scheduleID) delays=\(debugDurations(delays)) \(quizScrollDetails(proposedDelta: nil))"
            )
        }
        recordQuizScroll(
            "quiz.scroll-schedule",
            pathID: activeQuizCaretPathID,
            details: "schedule=\(scheduleID) source=\(activeQuizCaretSource?.rawValue ?? "nil") delays=\(debugDurations(delays)) \(quizScrollDetails(proposedDelta: nil))"
        )

        scheduledCaretScrollTask?.cancel()
        scheduledCaretScrollTask = Task { @MainActor in
            for (index, delay) in delays.enumerated() {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else {
                    recordQuizScroll(
                        "quiz.scroll-run-cancelled",
                        pathID: activeQuizCaretPathID,
                        details: "schedule=\(scheduleID) currentSchedule=\(quizCaretScrollScheduleSequence) pass=\(index + 1) delay=\(debugDuration(delay)) \(quizScrollDetails(proposedDelta: nil))"
                    )
                    return
                }

                guard keyboardMonitor.isVisible,
                      focusManager.focusedZoneID == currentSelectedZoneID else {
                    recordQuizScroll(
                        "quiz.scroll-run-abort",
                        pathID: activeQuizCaretPathID,
                        details: "schedule=\(scheduleID) currentSchedule=\(quizCaretScrollScheduleSequence) pass=\(index + 1) delay=\(debugDuration(delay)) focused=\(shortDebugID(focusManager.focusedZoneID)) currentZone=\(shortDebugID(currentSelectedZoneID)) \(quizScrollDetails(proposedDelta: nil))"
                    )
                    return
                }

                recordQuizScroll(
                    "quiz.scroll-run",
                    pathID: activeQuizCaretPathID,
                    details: "schedule=\(scheduleID) currentSchedule=\(quizCaretScrollScheduleSequence) pass=\(index + 1) delay=\(debugDuration(delay)) rect=\(activeQuizCaretWindowRect.map(debugRect) ?? "nil") \(quizScrollDetails(proposedDelta: nil))"
                )
                recordQuizScrollState(
                    "quiz.scroll-state-run",
                    pathID: activeQuizCaretPathID,
                    extra: "pass=\(index + 1) delay=\(debugDuration(delay))"
                )
                quizScrollDriver.setDebugTraceContext(
                    isQuizDebugRecordingActive
                        ? "run schedule=\(scheduleID) pass=\(index + 1) source=\(activeQuizCaretSource?.rawValue ?? "nil") trace=\(activeQuizCaretTraceID ?? "nil") path=\(activeQuizCaretPathID ?? "nil")"
                        : nil
                )

                guard let pathID = activeQuizCaretPathID,
                      currentSelectedPath?.id == pathID else {
                    recordQuizScroll(
                        "quiz.scroll-skip-not-active-path",
                        pathID: activeQuizCaretPathID,
                        details: "activeSelected=\(currentSelectedPath?.id ?? "nil") focused=\(shortDebugID(focusManager.focusedZoneID)) currentZone=\(shortDebugID(currentSelectedZoneID)) \(quizScrollDetails(proposedDelta: nil))"
                    )
                    return
                }

                guard let caretRect = activeQuizCaretWindowRect else {
                    recordQuizScroll(
                        "quiz.scroll-skip-visible",
                        pathID: pathID,
                        details: "reason=no-caret-rect \(quizScrollDetails(proposedDelta: nil))"
                    )
                    continue
                }

                if scrollQuizCaretDownIfNeeded(caretRect, pathID: pathID) {
                    activeQuizCaretWindowRect = nil
                    activeQuizCaretSource = nil
                    activeQuizCaretAnchorY = nil
                    activeQuizCaretEditorHeight = nil
                    return
                }
            }
        }
    }

    @discardableResult
    private func scrollQuizCaretDownIfNeeded(_ caretRect: CGRect, pathID: String) -> Bool {
        let bottomBuffer = quizCaretBottomChromeBuffer(forSource: activeQuizCaretSource)
        let visibleBottomY = quizVisibleBottomWindowY(bottomBuffer: bottomBuffer)
        let proposedDelta = caretRect.maxY - visibleBottomY
        let probeID = isQuizDebugRecordingActive ? "\(pathID)-\(Int(Date().timeIntervalSince1970 * 1_000))" : nil

        recordQuizScrollState(
            "quiz.scroll-probe-start",
            pathID: pathID,
            extra: "probe=\(probeID ?? "off") source=\(activeQuizCaretSource?.rawValue ?? "nil") rect=\(debugRect(caretRect)) visibleBottom=\(debugValue(visibleBottomY)) bottomBuffer=\(debugValue(bottomBuffer)) proposedDelta=\(debugOptionalValue(proposedDelta))"
        )

        recordQuizScrollState(
            "quiz.scroll-probe-after-inset",
            pathID: pathID,
            extra: "probe=\(probeID ?? "off") resolvedInset=content-padding bottomBuffer=\(debugValue(bottomBuffer))"
        )

        guard proposedDelta > 1 else {
            recordQuizScroll(
                "quiz.scroll-skip-visible",
                pathID: pathID,
                details: "reason=already-visible source=\(activeQuizCaretSource?.rawValue ?? "nil") rect=\(debugRect(caretRect)) visibleBottom=\(debugValue(visibleBottomY)) bottomBuffer=\(debugValue(bottomBuffer)) proposedDelta=\(debugOptionalValue(proposedDelta)) \(quizScrollDetails(proposedDelta: proposedDelta))"
            )
            return false
        }

        if quizCaretScrollGate.shouldSuppressScrollRequest(
            pathID: pathID,
            rect: caretRect,
            visibleBottomY: visibleBottomY,
            proposedDelta: proposedDelta,
            normalizedOffsetY: quizScrollDriver.currentNormalizedOffsetY,
            animationDuration: quizCaretScrollAnimationDuration
        ) {
            recordQuizScroll(
                "quiz.scroll-skip-duplicate-request",
                pathID: pathID,
                details: "source=\(activeQuizCaretSource?.rawValue ?? "nil") rect=\(debugRect(caretRect)) visibleBottom=\(debugValue(visibleBottomY)) bottomBuffer=\(debugValue(bottomBuffer)) proposedDelta=\(debugOptionalValue(proposedDelta)) \(quizScrollDetails(proposedDelta: proposedDelta))"
            )
            return false
        }

        let didScroll = quizScrollDriver.scrollWindowRectAboveBottomChromeIfNeeded(
            windowRect: caretRect,
            bottomChromeTopY: nil,
            keyboardHeight: keyboardMonitor.visibleHeight,
            bottomAccessoryHeight: floatingToolbarAccessoryHeight,
            bottomBuffer: bottomBuffer,
            animationDuration: quizCaretScrollAnimationDuration,
            animationOptions: keyboardMonitor.animationOptions,
            zoneID: currentSelectedZoneID,
            keepsOffsetLocked: activeQuizCaretSource != .newline
        )
        quizCaretScrollGate.recordScrollResult(
            didScroll: didScroll,
            pathID: pathID,
            rect: caretRect,
            visibleBottomY: visibleBottomY,
            proposedDelta: proposedDelta,
            normalizedOffsetY: quizScrollDriver.currentNormalizedOffsetY
        )
        recordQuizScrollState(
            "quiz.scroll-probe-after-request",
            pathID: pathID,
            extra: "probe=\(probeID ?? "off") didScroll=\(debugFlag(didScroll))"
        )
        if let probeID {
            scheduleQuizScrollStateProbe(probeID: probeID, pathID: pathID)
        }

        let skippedStage = proposedDelta < -140 ? "quiz.scroll-skip-upward" : "quiz.scroll-skip-visible"
        let sourceStage: String
        switch activeQuizCaretSource {
        case .focus:
            sourceStage = "quiz.scroll-apply-focus"
        case .selectionTap:
            sourceStage = "quiz.scroll-apply-selection-tap"
        case .newline:
            sourceStage = "quiz.scroll-apply-newline"
        default:
            sourceStage = "quiz.scroll-apply-down"
        }
        recordQuizScroll(
            didScroll ? sourceStage : skippedStage,
            pathID: pathID,
            details: "source=\(activeQuizCaretSource?.rawValue ?? "nil") rect=\(debugRect(caretRect)) visibleBottom=\(debugValue(visibleBottomY)) bottomBuffer=\(debugValue(bottomBuffer)) resolvedInset=content-padding didScroll=\(debugFlag(didScroll)) \(quizScrollDetails(proposedDelta: proposedDelta))"
        )
        return didScroll
    }

    private func scheduleQuizScrollStateProbe(probeID: String, pathID: String) {
        guard isQuizDebugRecordingActive else { return }
        quizScrollDriver.scheduleDebugSnapshots(
            prefix: "quiz.scroll-probe-\(probeID)",
            delays: [0, 0.008, 0.016, 0.033, 0.05, 0.08, 0.12, 0.18, 0.30, 0.50],
            zoneID: currentSelectedZoneID,
            extra: "path=\(pathID) target=\(debugTargetID(activeEditor))"
        )
    }

    private func recordQuizScrollState(_ stage: String, pathID: String?, extra: @autoclosure () -> String) {
        guard isQuizDebugRecordingActive else { return }
        quizScrollDriver.recordDebugSnapshot(
            stage,
            zoneID: currentSelectedZoneID,
            extra: "path=\(pathID ?? "nil") \(extra()) \(quizScrollDetails(proposedDelta: nil))"
        )
    }

    private func caretWindowRect(from notification: Notification) -> CGRect? {
        guard let value = notification.userInfo?[ZoneEditorCaretScrollNotification.caretRectInWindowKey] else {
            return nil
        }

        if let rectValue = value as? NSValue {
            return rectValue.cgRectValue
        }

        return value as? CGRect
    }

    private func caretScrollSource(from notification: Notification) -> ZoneEditorCaretScrollSource {
        guard let rawValue = notification.userInfo?[ZoneEditorCaretScrollNotification.sourceKey] as? String,
              let source = ZoneEditorCaretScrollSource(rawValue: rawValue) else {
            return .selectionTap
        }

        return source
    }

    private func caretTraceID(from notification: Notification) -> String {
        notification.userInfo?[ZoneEditorCaretScrollNotification.traceIDKey] as? String ?? "missing"
    }

    private func caretAnchorY(from notification: Notification) -> CGFloat? {
        notification.userInfo?[ZoneEditorCaretScrollNotification.anchorYKey] as? CGFloat
    }

    private func caretEditorHeight(from notification: Notification) -> CGFloat? {
        notification.userInfo?[ZoneEditorCaretScrollNotification.editorHeightKey] as? CGFloat
    }

    private func shouldScrollQuizCaret(for source: ZoneEditorCaretScrollSource) -> Bool {
        source == .focus || source == .selectionTap || source == .newline
    }

    private func quizCaretScrollDelays(for source: ZoneEditorCaretScrollSource) -> [Duration] {
        source == .newline
            ? [.zero]
            : [.milliseconds(16), .milliseconds(96)]
    }

    private func quizCaretBottomChromeBuffer(forSource source: ZoneEditorCaretScrollSource?) -> CGFloat {
        source == .newline ? quizNewlineCaretBottomChromeBuffer : quizCaretBottomChromeBuffer
    }

    private func quizVisibleBottomWindowY(
        bottomBuffer: CGFloat? = nil
    ) -> CGFloat {
        let resolvedBottomBuffer = bottomBuffer ?? quizCaretBottomChromeBuffer(forSource: activeQuizCaretSource)
        let viewportBottomY = UIScreen.main.bounds.maxY - resolvedBottomBuffer
        let chromeTopY = UIScreen.main.bounds.maxY
            - max(keyboardMonitor.visibleHeight, 0)
            - max(floatingToolbarAccessoryHeight, 0)
        return min(viewportBottomY, chromeTopY - resolvedBottomBuffer)
    }

    @ViewBuilder
    private var quizScrollDebugOverlay: some View {
        if isQuizDebugRecordingActive {
            ZStack(alignment: .topLeading) {
                quizDebugHorizontalLine(
                    screenY: quizViewportScreenFrame.maxY,
                    color: .blue,
                    title: "viewport bottom"
                )
                quizDebugHorizontalLine(
                    screenY: quizKeyboardTopScreenY,
                    color: .orange,
                    title: "keyboard top"
                )
                quizDebugHorizontalLine(
                    screenY: quizToolbarTopScreenY,
                    color: .purple,
                    title: "toolbar top"
                )
                quizDebugHorizontalLine(
                    screenY: quizVisibleBottomWindowY(),
                    color: .green,
                    title: "visible bottom"
                )
                if let activeQuizCaretWindowRect {
                    quizDebugHorizontalLine(
                        screenY: activeQuizCaretWindowRect.maxY,
                        color: .red,
                        title: "caret bottom"
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("quiz scroll")
                    Text("offset \(debugValue(quizScrollDriver.currentNormalizedOffsetY))")
                    Text("kb \(debugValue(keyboardMonitor.visibleHeight)) toolbar \(debugValue(floatingToolbarAccessoryHeight))")
                    Text("visible \(debugValue(quizVisibleBottomWindowY())) buffer \(debugValue(quizCaretBottomChromeBuffer(forSource: activeQuizCaretSource)))")
                    Text("padding \(debugValue(bottomContentPadding))")
                    Text("inset \(debugValue(quizScrollDriver.currentContentInsetBottom))/\(debugValue(quizScrollDriver.currentAdjustedContentInsetBottom))")
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(6)
                .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 6))
                .padding(.leading, 8)
                .padding(.top, max(quizViewportScreenFrame.height - 132, 0))
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func quizDebugHorizontalLine(screenY: CGFloat, color: Color, title: String) -> some View {
        let localY = screenY - quizViewportScreenFrame.minY
        if quizViewportScreenFrame.height > 0,
           localY >= 0,
           localY <= quizViewportScreenFrame.height {
            HStack(spacing: 4) {
                Rectangle()
                    .stroke(
                        color.opacity(0.95),
                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                    )
                    .frame(maxWidth: .infinity, minHeight: 1.5, maxHeight: 1.5)

                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 4))
            }
            .offset(y: localY)
        }
    }

    private var quizKeyboardTopScreenY: CGFloat {
        UIScreen.main.bounds.maxY - max(keyboardMonitor.visibleHeight, 0)
    }

    private var quizToolbarTopScreenY: CGFloat {
        quizKeyboardTopScreenY - max(floatingToolbarAccessoryHeight, 0)
    }

    private var quizCaretBottomChromeBuffer: CGFloat {
        100
    }

    private var quizNewlineCaretBottomChromeBuffer: CGFloat {
        32
    }

    private var quizCaretScrollAnimationDuration: TimeInterval {
        if activeQuizCaretSource == .newline {
            return 0.10
        }
        guard keyboardMonitor.isVisible else { return 0.16 }
        return min(max(keyboardMonitor.animationDuration, 0.12), 0.28)
    }

    private func recordQuizScroll(_ stage: String, pathID: String?, details: @autoclosure () -> String) {
        guard isQuizDebugRecordingActive else { return }
        ZoneEditorDebugStore.shared.recordLayoutEvent(
            stage,
            zoneID: currentSelectedZoneID,
            pathID: pathID,
            details: details()
        )
    }

    private func quizScrollDetails(proposedDelta: CGFloat?) -> String {
        "trace=\(activeQuizCaretTraceID ?? "nil") target=\(debugTargetID(activeEditor)) kb=\(debugFlag(keyboardMonitor.isVisible)):\(debugValue(keyboardMonitor.visibleHeight)) toolbar=\(debugValue(floatingToolbarAccessoryHeight)) offset=\(debugValue(quizScrollDriver.currentNormalizedOffsetY)) visibleBottom=\(debugValue(quizVisibleBottomWindowY())) viewport=\(debugRect(quizViewportScreenFrame)) bottomPadding=\(debugValue(bottomContentPadding)) scrollInset=\(debugValue(quizScrollDriver.currentContentInsetBottom))/\(debugValue(quizScrollDriver.currentAdjustedContentInsetBottom)) delta=\(debugOptionalValue(proposedDelta)) selected=\(currentSelectedPath?.id ?? "nil")"
    }

    private func debugDurations(_ durations: [Duration]) -> String {
        durations.map(debugDuration).joined(separator: ",")
    }

    private func shortDebugID(_ id: UUID?) -> String {
        guard let id else { return "nil" }
        return String(id.uuidString.prefix(6))
    }

    private func addChoice() {
        let newChoice = QuizChoiceEditorItem()

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            choices.append(newChoice)
            activateEditor(.choice(newChoice.id))
        }

        requestFocus(for: newChoice.content.rootZone.id, delaySeconds: 0.12)
    }

    private func deleteChoice(_ choiceID: UUID) {
        guard let index = indexOfChoice(choiceID) else { return }
        let fallbackEditor: QuizEditorTarget

        clearPendingDelete(animated: false)

        if markedCorrectIndicatorChoiceID == choiceID {
            markedCorrectIndicatorTask?.cancel()
            markedCorrectIndicatorTask = nil
            markedCorrectIndicatorChoiceID = nil
        }

        if choices.indices.contains(index + 1) {
            fallbackEditor = .choice(choices[index + 1].id)
        } else if index > 0 {
            fallbackEditor = .choice(choices[index - 1].id)
        } else {
            fallbackEditor = .question
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
            choices.remove(at: index)
            if activeEditor == .choice(choiceID) {
                activeEditor = fallbackEditor
                if selectedPath(for: fallbackEditor) == nil {
                    setSelectedPath(.root, for: fallbackEditor)
                }
            }
        }
    }

    private func handleDeleteTap(for choiceID: UUID) {
        if pendingDeleteChoiceID == choiceID {
            pendingDeleteTask?.cancel()
            pendingDeleteTask = nil
            deleteChoice(choiceID)
            return
        }

        pendingDeleteTask?.cancel()
        withAnimation(.easeOut(duration: 0.16)) {
            pendingDeleteChoiceID = choiceID
        }

        pendingDeleteTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            clearPendingDelete(animated: true, choiceID: choiceID)
        }
    }

    private func clearPendingDelete(animated: Bool, choiceID: UUID? = nil) {
        pendingDeleteTask?.cancel()
        pendingDeleteTask = nil

        guard pendingDeleteChoiceID != nil,
              choiceID == nil || pendingDeleteChoiceID == choiceID else { return }

        let clear = {
            pendingDeleteChoiceID = nil
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.14)) {
                clear()
            }
        } else {
            clear()
        }
    }

    private func toggleCorrect(for choiceID: UUID) {
        guard let targetChoice = choice(for: choiceID) else { return }
        let willMarkCorrect = !targetChoice.isCorrect
        targetChoice.isCorrect.toggle()

        markedCorrectIndicatorTask?.cancel()
        markedCorrectIndicatorTask = nil

        if willMarkCorrect {
            withAnimation(.easeOut(duration: 0.16)) {
                markedCorrectIndicatorChoiceID = choiceID
            }

            markedCorrectIndicatorTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    if markedCorrectIndicatorChoiceID == choiceID {
                        markedCorrectIndicatorChoiceID = nil
                    }
                }
                markedCorrectIndicatorTask = nil
            }
        } else if markedCorrectIndicatorChoiceID == choiceID {
            withAnimation(.easeInOut(duration: 0.14)) {
                markedCorrectIndicatorChoiceID = nil
            }
        }
    }

    private func addExplanation() {
        let newExplanationContent = ZoneCardContent(rootZone: .text())

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            explanationContent = newExplanationContent
            explanationSelectedPath = .root
            isExplanationExpanded = true
            activateEditor(.explanation)
        }

        requestFocus(for: newExplanationContent.rootZone.id, delaySeconds: 0.12)
    }

    private func removeExplanation() {
        let wasActiveExplanation = activeEditor == .explanation

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            explanationContent = nil
            explanationSelectedPath = nil
            isExplanationExpanded = false
            if wasActiveExplanation {
                activeEditor = .question
                questionSelectedPath = nil
                previewDirection = nil
            }
        }

        if wasActiveExplanation {
            focusManager.forceReleaseKeyboard()
            zoneController.forceReleaseKeyboard()
            zoneController.updateFocusedZone(nil)
            updateFloatingFormatBarPresentation(isKeyboardVisible: false)
        }
    }

    private func addPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }

        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let compressedData = data.compressedImageData(maxDimension: 1200, compressionQuality: 0.7) ?? data
                await MainActor.run {
                    applyMedia(data: compressedData, as: .image)
                }
            }

            await MainActor.run {
                selectedPhoto = nil
            }
        }
    }

    private func addSketch(_ data: Data) {
        applyMedia(data: data, as: .sketch)
    }

    private func prepareForMediaZoneSelection() {
        scheduledCaretScrollTask?.cancel()
        scheduledCaretScrollTask = nil
        previewDirection = nil
        focusManager.suppressFocusRequests(for: 0.9)
        focusManager.forceReleaseKeyboard()
        zoneController.forceReleaseKeyboard()
        zoneController.updateFocusedZone(nil)
        activeQuizCaretPathID = nil
        activeQuizCaretWindowRect = nil
        activeQuizCaretSource = nil
        activeQuizCaretAnchorY = nil
        activeQuizCaretEditorHeight = nil
    }

    private func applyMedia(data: Data, as contentType: ZoneContentType) {
        guard let content = currentContent else { return }

        activateEditor(activeEditor)

        guard let path = currentSelectedPath else { return }
        content.updateZone(at: path) { zone in
            zone.contentType = contentType
            zone.imageData = data
        }
        prepareForMediaZoneSelection()
        updateFloatingFormatBarPresentation(isKeyboardVisible: false)
    }

    private func openPreview() {
        guard questionContent.hasContent || choices.contains(where: { $0.content.hasContent }) else { return }
        focusManager.forceReleaseKeyboard()
        zoneController.forceReleaseKeyboard()
        zoneController.updateFocusedZone(nil)
        currentSelectedPath = nil
        previewDirection = nil
        showPreview = true
    }

    private func closeEditor() {
        focusManager.forceReleaseKeyboard()
        zoneController.forceReleaseKeyboard()
        dismiss()
    }

    private func saveCard() {
        questionContent.cleanup()
        choices.forEach { $0.content.cleanup() }
        explanationContent?.cleanup()
        onSave(currentQuizContent)
        focusManager.forceReleaseKeyboard()
        zoneController.clearHeightCache()
        dismiss()
    }

    private func choice(for choiceID: UUID) -> QuizChoiceEditorItem? {
        choices.first(where: { $0.id == choiceID })
    }

    private func indexOfChoice(_ choiceID: UUID) -> Int? {
        choices.firstIndex(where: { $0.id == choiceID })
    }

    private func requestFocus(for zoneID: UUID, delaySeconds: Double = 0.05) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delaySeconds))
            focusManager.requestFocus(for: zoneID)
        }
    }

    private var editorBackground: Color {
            .black
    }

    private func editorTopBlurHeight(safeTopInset: CGFloat) -> CGFloat {
        safeTopInset + UIConstants.Layout.deckNavigationTopPadding + UIConstants.Size.actionButton + UIConstants.Spacing.large
    }
}

/// Identifies which quiz section currently owns the bottom formatting bar.
private enum QuizEditorTarget: Equatable {
    case question
    case choice(UUID)
    case explanation
}

private enum QuizEditorStyle {
    static let buttonCornerRadius: CGFloat = 22
}

private struct QuizEditorControlButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isActive || configuration.isPressed ? 1 : 0.8)
            .animation(.easeInOut(duration: 0.18), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.18), value: isActive)
    }
}

private struct QuizEditorAddButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 1 : 0.9)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.16), value: configuration.isPressed)
    }
}

private enum EditorKeyboardAccessoryMotion {
    static let appearAnimation: Animation = .selectionToolbarSpring
    static let dismissAnimation: Animation = .selectionToolbarSpring
    static let keyboardPaddingDismissAnimation: Animation = .easeOut(duration: 0.24)
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
            .scaleEffect(isVisible ? 1 : 0.94, anchor: .bottom)
            .allowsHitTesting(isVisible)
            .animation(
                isVisible
                    ? EditorKeyboardAccessoryMotion.appearAnimation
                    : EditorKeyboardAccessoryMotion.dismissAnimation,
                value: isVisible
            )
    }
}

/// Mutable quiz editor session retained across parent redraws.
@MainActor
private final class QuizEditorSession: ObservableObject {
    @Published var questionContent: ZoneCardContent
    @Published var questionSelectedPath: ZonePath?
    @Published var choices: [QuizChoiceEditorItem]
    @Published var explanationContent: ZoneCardContent?
    @Published var explanationSelectedPath: ZonePath?
    @Published var isExplanationExpanded: Bool

    init(initialContent: QuizCardContent) {
        questionContent = ZoneCardContent(rootZone: initialContent.questionZone)
        questionSelectedPath = nil

        var seededChoices = initialContent.choices.map {
            QuizChoiceEditorItem(
                id: $0.id,
                content: ZoneCardContent(rootZone: $0.contentZone),
                isCorrect: $0.isCorrect,
                selectedPath: nil
            )
        }
        if seededChoices.count < 2 {
            let missingCount = 2 - seededChoices.count
            seededChoices.append(contentsOf: (0..<missingCount).map { _ in QuizChoiceEditorItem() })
        }
        choices = seededChoices

        if let explanationZone = initialContent.explanationZone {
            explanationContent = ZoneCardContent(rootZone: explanationZone)
            isExplanationExpanded = explanationZone.hasContent
        } else {
            explanationContent = nil
            isExplanationExpanded = false
        }
        explanationSelectedPath = nil
    }
}

/// One mutable answer editor state inside the quiz authoring surface.
@Observable
private final class QuizChoiceEditorItem: Identifiable {
    let id: UUID
    var content: ZoneCardContent
    var isCorrect: Bool
    var selectedPath: ZonePath?

    init(
        id: UUID = UUID(),
        content: ZoneCardContent = ZoneCardContent(rootZone: .text()),
        isCorrect: Bool = false,
        selectedPath: ZonePath? = nil
    ) {
        self.id = id
        self.content = content
        self.isCorrect = isCorrect
        self.selectedPath = selectedPath
    }
}

/// Shared zone-editor card chrome used by the question and explanation surfaces.
private struct QuizZoneSectionCard<TrailingContent: View>: View {
    let content: ZoneCardContent
    @Binding var selectedPath: ZonePath?
    var highlightContext: HighlightContext?
    let fontScale: CGFloat
    let availableWidth: CGFloat
    @Binding var previewDirection: AddDirection?
    @ViewBuilder var trailingContent: () -> TrailingContent
    let onSelectionChange: () -> Void
    let onActivate: () -> Void

    init(
        content: ZoneCardContent,
        selectedPath: Binding<ZonePath?>,
        highlightContext: HighlightContext?,
        fontScale: CGFloat,
        availableWidth: CGFloat,
        previewDirection: Binding<AddDirection?>,
        onSelectionChange: @escaping () -> Void = {},
        @ViewBuilder trailingContent: @escaping () -> TrailingContent = { EmptyView() },
        onActivate: @escaping () -> Void
    ) {
        self.content = content
        self._selectedPath = selectedPath
        self.highlightContext = highlightContext
        self.fontScale = fontScale
        self.availableWidth = availableWidth
        self._previewDirection = previewDirection
        self.trailingContent = trailingContent
        self.onSelectionChange = onSelectionChange
        self.onActivate = onActivate
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZoneEditorView(
                content: content,
                path: .root,
                selectedPath: $selectedPath,
                highlightContext: highlightContext,
                fontScale: fontScale,
                availableWidth: availableWidth,
                measurementWidth: availableWidth,
                previewDirection: $previewDirection
            )
                .frame(width: availableWidth, alignment: .topLeading)
                .frame(minHeight: 88, alignment: .top)

            trailingContent()
        }
            .onTapGesture {
                onActivate()
            }
            .onChange(of: selectedPath) { _, newPath in
                guard newPath != nil else { return }
                onSelectionChange()
            }
    }

}

/// One answer row with correctness controls and a mini zone editor.
private struct QuizChoiceCard: View {
    @Bindable var choice: QuizChoiceEditorItem
    var highlightContext: HighlightContext?
    let fontScale: CGFloat
    let availableWidth: CGFloat
    @Binding var previewDirection: AddDirection?
    let onActivate: () -> Void
    let onSelectionChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            ZoneEditorView(
                content: choice.content,
                path: .root,
                selectedPath: $choice.selectedPath,
                highlightContext: highlightContext,
                fontScale: fontScale,
                availableWidth: availableWidth,
                measurementWidth: availableWidth,
                previewDirection: $previewDirection
            )
                .frame(width: availableWidth, alignment: .topLeading)
        }
            .onTapGesture {
            onActivate()
        }
            .onChange(of: choice.selectedPath) { _, _ in
            onSelectionChange()
        }
    }

}

@MainActor
private final class QuizCaretScrollGate {
    private struct ScrollRequest {
        let pathID: String
        let rect: CGRect
        let visibleBottomY: CGFloat
        let proposedDelta: CGFloat
        let normalizedOffsetY: CGFloat
        let timestamp: CFTimeInterval
    }

    private var lastCaretPathID: String?
    private var lastCaretRect: CGRect?
    private var lastAppliedRequest: ScrollRequest?

    func shouldIgnoreCaretUpdate(pathID: String, rect: CGRect) -> Bool {
        defer {
            lastCaretPathID = pathID
            lastCaretRect = rect
        }

        guard lastCaretPathID == pathID,
              let lastCaretRect else {
            return false
        }

        return abs(lastCaretRect.minY - rect.minY) < 0.75
            && abs(lastCaretRect.maxY - rect.maxY) < 0.75
            && abs(lastCaretRect.minX - rect.minX) < 0.75
            && abs(lastCaretRect.width - rect.width) < 0.75
    }

    func shouldSuppressScrollRequest(
        pathID: String,
        rect: CGRect,
        visibleBottomY: CGFloat,
        proposedDelta: CGFloat,
        normalizedOffsetY: CGFloat,
        animationDuration: TimeInterval
    ) -> Bool {
        guard let lastAppliedRequest,
              lastAppliedRequest.pathID == pathID else {
            return false
        }

        let elapsed = CACurrentMediaTime() - lastAppliedRequest.timestamp
        let holdWindow = max(animationDuration + 0.08, 0.22)
        guard elapsed <= holdWindow else { return false }

        let sameCaretBand = abs(lastAppliedRequest.rect.maxY - rect.maxY) < 18
            && abs(lastAppliedRequest.rect.minY - rect.minY) < 18
        let sameTargetBand = abs(lastAppliedRequest.visibleBottomY - visibleBottomY) < 12
            && abs(lastAppliedRequest.proposedDelta - proposedDelta) < 36
        let scrollStillSettling = abs(lastAppliedRequest.normalizedOffsetY - normalizedOffsetY) > 1

        return sameCaretBand && (sameTargetBand || scrollStillSettling)
    }

    func recordScrollResult(
        didScroll: Bool,
        pathID: String,
        rect: CGRect,
        visibleBottomY: CGFloat,
        proposedDelta: CGFloat,
        normalizedOffsetY: CGFloat
    ) {
        guard didScroll else { return }
        lastAppliedRequest = ScrollRequest(
            pathID: pathID,
            rect: rect,
            visibleBottomY: visibleBottomY,
            proposedDelta: proposedDelta,
            normalizedOffsetY: normalizedOffsetY,
            timestamp: CACurrentMediaTime()
        )
    }
}

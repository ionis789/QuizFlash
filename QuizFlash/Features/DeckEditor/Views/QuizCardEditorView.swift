//
//  QuizCardEditorView.swift
//  QuizFlash
//
//  Manual quiz-card authoring built on the shared zone editor stack.
//

import SwiftUI
import PhotosUI

/// A type-aware editor for manual quiz authoring inside the deck editor flow.
struct QuizCardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(KeyboardMonitor.self) private var keyboardMonitor

    @State private var highlightContext: HighlightContext?
    @State private var questionContent: ZoneCardContent
    @State private var questionSelectedPath: ZonePath? = .root
    @State private var choices: [QuizChoiceEditorItem]
    @State private var explanationContent: ZoneCardContent?
    @State private var explanationSelectedPath: ZonePath? = .root
    @State private var isExplanationExpanded: Bool
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

    private let onSave: (QuizCardContent) -> Void

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var successAccent: Color { ThemeManager.shared.successPrimary }
    private var topChromeUtilityFill: Color { Color(uiColor: .secondarySystemFill) }
    private var topChromeUtilityBorder: Color { Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.10) }
    private var topChromeUtilityForeground: Color { accent }
    private var topChromeDisabledFill: Color { Color(uiColor: .tertiarySystemFill) }
    private var focusManager = ZoneFocusManager.shared
    private var zoneController = ZoneController.shared
    private var locale: Locale { appPreferences.resolvedLocale }
    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var topChromeHorizontalInset: CGFloat {
        isCompact ? UIConstants.Layout.compactScreenEdgeInset : UIConstants.Layout.screenEdgeInset
    }
    private var isFormatBarVisible: Bool {
        keyboardMonitor.isVisible && currentContent != nil && currentSelectedPath != nil
    }
    private var bottomContentPadding: CGFloat {
        isFormatBarVisible ? 148 : 96
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
        onSave: @escaping (QuizCardContent) -> Void
    ) {
        _questionContent = State(initialValue: ZoneCardContent(rootZone: initialContent.questionZone))

        var seededChoices = initialContent.choices.map {
            QuizChoiceEditorItem(
                id: $0.id,
                content: ZoneCardContent(rootZone: $0.contentZone),
                isCorrect: $0.isCorrect,
                selectedPath: .root
            )
        }
        if seededChoices.count < 2 {
            let missingCount = 2 - seededChoices.count
            seededChoices.append(contentsOf: (0..<missingCount).map { _ in QuizChoiceEditorItem() })
        }
        _choices = State(initialValue: seededChoices)

        if let explanationZone = initialContent.explanationZone {
            _explanationContent = State(initialValue: ZoneCardContent(rootZone: explanationZone))
            _isExplanationExpanded = State(initialValue: explanationZone.hasContent)
        } else {
            _explanationContent = State(initialValue: nil)
            _isExplanationExpanded = State(initialValue: false)
        }

        if let query = searchQuery, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _highlightContext = State(initialValue: HighlightContext(query: query))
        } else {
            _highlightContext = State(initialValue: nil)
        }

        self.onSave = onSave
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

            ZStack(alignment: .top) {
                editorBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
                        questionSection
                        answersSection
                        explanationSection

                        if let validationMessage {
                            Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                    }
                        .padding(.horizontal, UIConstants.Spacing.large)
                        .padding(.top, UIConstants.Layout.deckNavigationTopPadding + UIConstants.Size.actionButton + UIConstants.Spacing.large)
                        .padding(.bottom, bottomContentPadding)
                }
                    .scrollDismissesKeyboard(.interactively)
                    .screenEdgeShadow(
                    topHeight: editorTopBlurHeight(safeTopInset: safeTopInset),
                    debugScreenID: "quiz.editor",
                    style: .progressiveBlur()
                )

                topChrome
                    .zIndex(20)
            }
        }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
            if isFormatBarVisible, let content = currentContent, let path = currentSelectedPath {
                formatBar(content: content, path: path)
                    .padding(.horizontal, UIConstants.Spacing.standard)
                    .padding(.bottom, UIConstants.Spacing.small)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
            .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { _, item in
            addPhoto(item)
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
                safeAreaInsets: safeArea
            )
        } background: {
            Color.clear
        }
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: currentSelectedPath)
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: keyboardMonitor.isVisible)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: previewDirection)
            .swipeBack(enabled: canUseInteractiveDismiss) {
            dismiss()
        }
            .task {
            if questionSelectedPath == nil {
                questionSelectedPath = .root
            }

            if highlightContext == nil || highlightContext?.isDismissed == true {
                requestFocus(for: questionContent.rootZone.id, delaySeconds: 0.35)
            }
        }
            .onDisappear {
            markedCorrectIndicatorTask?.cancel()
            markedCorrectIndicatorTask = nil
            pendingDeleteTask?.cancel()
            pendingDeleteTask = nil
        }
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
            showsPreviewAction: false,
            showsMoreActions: false,
            onPreview: {
                openPreview()
            },
            onClose: {
                focusManager.forceReleaseKeyboard()
                previewDirection = nil
            }
        )
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
                tint: accent,
                backgroundTint: topChromeUtilityFill
            )
        }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("Preview"))
    }

    private var questionSection: some View {
        QuizZoneSectionCard(
            title: localized("QUESTION"),
            subtitle: localized("Prompt"),
            content: questionContent,
            selectedPath: binding(for: .question),
            highlightContext: highlightContext,
            previewDirection: $previewDirection
        ) {
            activateEditor(.question)
        }
    }

    private var answersSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {

            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in

                VStack(spacing: UIConstants.Spacing.small) {
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
                        index: index,
                        canMoveDown: index < choices.count - 1,
                        choice: choice,
                        highlightContext: highlightContext,
                        previewDirection: $previewDirection,
                        onActivate: {
                            activateEditor(.choice(choice.id))
                        },
                        onMoveUp: {
                            moveChoice(choice.id, direction: -1)
                        },
                        onMoveDown: {
                            moveChoice(choice.id, direction: 1)
                        }
                    )
                }
            }

            Button {
                addChoice()
            } label: {
                Label(localized("Add Answer"), systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, UIConstants.Spacing.standard)
                    .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: QuizEditorStyle.buttonCornerRadius, style: .continuous)
                )
                    .overlay {
                    RoundedRectangle(cornerRadius: QuizEditorStyle.buttonCornerRadius, style: .continuous)
                        .stroke(accent.opacity(0.18), lineWidth: 1)
                }
            }
                .buttonStyle(.plain)
        }
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
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.caption.weight(.bold))

                if isPending {
                    Text(localized("Delete?"))
                        .font(.caption.weight(.bold))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .foregroundStyle(.red)
            .frame(minWidth: 28, minHeight: 28)
            .padding(.horizontal, isPending ? 10 : 0)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.24, dampingFraction: 0.84), value: isPending)
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
        .buttonStyle(.plain)
        .accessibilityLabel(isCorrect ? localized("Correct") : localized("Mark Correct"))
    }

    @ViewBuilder
    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            HStack {
                HStack(spacing: 2) {
                    Text(localized("EXPLANATION"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Text("(" + localized("optional") + ")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if explanationContent != nil {
                    Button(isExplanationExpanded ? localized("Collapse") : localized("Expand")) {
                        isExplanationExpanded.toggle()
                    }
                        .font(.caption.weight(.semibold))
                        .tint(accent)
                }
            }

            if let explanationContent {
                if isExplanationExpanded {
                    QuizZoneSectionCard(
                        title: localized("EXPLANATION"),
                        subtitle: localized("Optional rationale"),
                        content: explanationContent,
                        selectedPath: binding(for: .explanation),
                        highlightContext: highlightContext,
                        previewDirection: $previewDirection,
                        trailingContent: {
                            Button(role: .destructive) {
                                removeExplanation()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.red)
                                    .frame(width: 28, height: 28)
                                    .background(Color.red.opacity(0.08), in: Circle())
                            }
                                .buttonStyle(.plain)
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
                Button {
                    addExplanation()
                } label: {
                    Label(localized("Add Explanation"), systemImage: "plus.bubble")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, UIConstants.Spacing.standard)
                        .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: QuizEditorStyle.buttonCornerRadius, style: .continuous)
                    )
                        .overlay {
                        RoundedRectangle(cornerRadius: QuizEditorStyle.buttonCornerRadius, style: .continuous)
                            .stroke(accent.opacity(0.18), lineWidth: 1)
                    }
                }
                    .buttonStyle(.plain)
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

    private func setSelectedPath(_ path: ZonePath?, for target: QuizEditorTarget) {
        switch target {
        case .question:
            questionSelectedPath = path
        case .choice(let choiceID):
            choice(for: choiceID)?.selectedPath = path
        case .explanation:
            explanationSelectedPath = path
        }
    }

    private func activateEditor(_ target: QuizEditorTarget) {
        if activeEditor != target {
            setSelectedPath(nil, for: activeEditor)
            previewDirection = nil
        }

        activeEditor = target

        if selectedPath(for: target) == nil {
            setSelectedPath(.root, for: target)
        }
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
        withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
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
            withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                clear()
            }
        } else {
            clear()
        }
    }

    private func moveChoice(_ choiceID: UUID, direction: Int) {
        guard let index = indexOfChoice(choiceID) else { return }
        let newIndex = index + direction
        guard choices.indices.contains(newIndex) else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
            choices.swapAt(index, newIndex)
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

        withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
            explanationContent = newExplanationContent
            explanationSelectedPath = .root
            isExplanationExpanded = true
            activateEditor(.explanation)
        }

        requestFocus(for: newExplanationContent.rootZone.id)
    }

    private func removeExplanation() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
            explanationContent = nil
            explanationSelectedPath = .root
            isExplanationExpanded = false
            if activeEditor == .explanation {
                activateEditor(.question)
            }
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

    private func applyMedia(data: Data, as contentType: ZoneContentType) {
        guard let content = currentContent else { return }

        activateEditor(activeEditor)

        guard let path = currentSelectedPath else { return }
        content.updateZone(at: path) { zone in
            zone.contentType = contentType
            zone.imageData = data
        }
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
    static let sectionCornerRadius: CGFloat = 30
    static let buttonCornerRadius: CGFloat = 22
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
        selectedPath: ZonePath? = .root
    ) {
        self.id = id
        self.content = content
        self.isCorrect = isCorrect
        self.selectedPath = selectedPath
    }
}

/// Shared zone-editor card chrome used by the question and explanation surfaces.
private struct QuizZoneSectionCard<TrailingContent: View>: View {
    let title: String
    let subtitle: String
    let content: ZoneCardContent
    @Binding var selectedPath: ZonePath?
    var highlightContext: HighlightContext?
    @Binding var previewDirection: AddDirection?
    @ViewBuilder var trailingContent: () -> TrailingContent
    let onActivate: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        subtitle: String,
        content: ZoneCardContent,
        selectedPath: Binding<ZonePath?>,
        highlightContext: HighlightContext?,
        previewDirection: Binding<AddDirection?>,
        @ViewBuilder trailingContent: @escaping () -> TrailingContent = { EmptyView() },
        onActivate: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
        self._selectedPath = selectedPath
        self.highlightContext = highlightContext
        self._previewDirection = previewDirection
        self.trailingContent = trailingContent
        self.onActivate = onActivate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Text(subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()
                trailingContent()
            }

            ZoneEditorView(
                content: content,
                path: .root,
                selectedPath: $selectedPath,
                highlightContext: highlightContext,
                previewDirection: $previewDirection
            )
                .frame(minHeight: 88, alignment: .top)
        }
            .padding(UIConstants.Spacing.standard)
            .background(
            cardBackground,
            in: RoundedRectangle(cornerRadius: QuizEditorStyle.sectionCornerRadius, style: .continuous)
        )
            .onTapGesture {
            onActivate()
        }
    }

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color.white.opacity(0.055))
        : AnyShapeStyle(Color.white.opacity(0.94))
    }

}

/// One answer row with correctness controls and a mini zone editor.
private struct QuizChoiceCard: View {
    let index: Int
    let canMoveDown: Bool
    @Bindable var choice: QuizChoiceEditorItem
    var highlightContext: HighlightContext?
    @Binding var previewDirection: AddDirection?
    let onActivate: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {

            HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
                Spacer()

                HStack(spacing: UIConstants.Spacing.small) {
                    QuizChoiceActionButton(symbol: "arrow.up", isEnabled: index > 0, action: onMoveUp)
                    QuizChoiceActionButton(symbol: "arrow.down", isEnabled: canMoveDown, action: onMoveDown)
                }
            }

            ZoneEditorView(
                content: choice.content,
                path: .root,
                selectedPath: $choice.selectedPath,
                highlightContext: highlightContext,
                previewDirection: $previewDirection
            )
                .frame(minHeight: 72, alignment: .top)
        }
            .padding(UIConstants.Spacing.standard)
            .background(
            cardBackground,
            in: RoundedRectangle(cornerRadius: QuizEditorStyle.sectionCornerRadius, style: .continuous)
        )
            .onTapGesture {
            onActivate()
        }
    }

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color.white.opacity(0.055))
        : AnyShapeStyle(Color.white.opacity(0.94))
    }

}

/// Small chrome button used for answer reordering and deletion.
private struct QuizChoiceActionButton: View {
    let symbol: String
    var isEnabled: Bool = true
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Color(uiColor: .tertiarySystemFill), in: Circle())
        }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.35)
    }
}

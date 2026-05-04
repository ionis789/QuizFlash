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
    @Environment(AppPreferences.self) private var appPreferences

    @State private var highlightContext: HighlightContext?
    @State private var questionContent: ZoneCardContent
    @State private var questionSelectedPath: ZonePath? = .root
    @State private var choices: [QuizChoiceEditorItem]
    @State private var explanationContent: ZoneCardContent?
    @State private var explanationSelectedPath: ZonePath? = .root
    @State private var isExplanationExpanded: Bool
    @State private var allowsMultipleCorrect: Bool
    @State private var activeEditor: QuizEditorTarget = .question
    @State private var previewDirection: AddDirection? = nil
    @State private var showSketchModal = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false

    private let onSave: (QuizCardContent) -> Void

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var focusManager = ZoneFocusManager.shared
    private var zoneController = ZoneController.shared
    private var locale: Locale { appPreferences.resolvedLocale }

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

        _allowsMultipleCorrect = State(initialValue: initialContent.allowsMultipleCorrect)

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

    var body: some View {
        NavigationStack {
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
                .padding(.top, UIConstants.Spacing.large)
                .padding(.bottom, currentSelectedPath == nil ? 96 : 148)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(backgroundGradient.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if let content = currentContent, let path = currentSelectedPath {
                    VStack(alignment: .leading, spacing: 6) {
                        if isFocusedSelection(content: content, path: path) {
                            zoneManagementButton(content: content, path: path)
                                .transition(.scale(scale: 0.88).combined(with: .opacity))
                        }

                        formatBar(content: content, path: path)
                    }
                        .padding(.horizontal, UIConstants.Spacing.standard)
                        .padding(.bottom, UIConstants.Spacing.small)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(localized("Quiz Card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar { toolbarContent }
            .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { _, item in
                addPhoto(item)
            }
            .fullScreenCover(isPresented: $showSketchModal) {
                CanvasModalView { data in
                    addSketch(data)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: currentSelectedPath)
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
            canPreview: false,
            onPreview: { },
            onClose: {
                focusManager.forceReleaseKeyboard()
                currentSelectedPath = nil
                previewDirection = nil
            }
        )
    }

    private func isFocusedSelection(content: ZoneCardContent, path: ZonePath) -> Bool {
        guard let zone = content.zone(at: path) else { return false }
        return focusManager.focusedZoneID == zone.id
    }

    private func zoneManagementButton(content: ZoneCardContent, path: ZonePath) -> some View {
        ZoneManagementFloatingButton(
            content: content,
            path: path,
            onSplit: { splitZone() },
            onDuplicate: { duplicateSelectedZone() },
            onMoveUp: { moveSelectedZoneUp() },
            onMoveDown: { moveSelectedZoneDown() },
            onClose: {
                focusManager.forceReleaseKeyboard()
                currentSelectedPath = nil
                previewDirection = nil
            }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(localized("Cancel")) {
                dismiss()
            }
            .tint(.secondary)
        }

        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: UIConstants.Spacing.medium) {
                Button {
                    isPhotoPickerPresented = true
                } label: {
                    Image(systemName: "photo.on.rectangle")
                        .font(.body.weight(.medium))
                }
                .tint(accent)

                Button {
                    showSketchModal = true
                } label: {
                    Image(systemName: "pencil.and.scribble")
                        .font(.body.weight(.medium))
                }
                .tint(accent)

                Divider()
                    .frame(height: 24)

                Button(localized("Save")) {
                    saveCard()
                }
                .fontWeight(.semibold)
                .disabled(!canSave)
            }
        }
    }

    private var questionSection: some View {
        QuizZoneSectionCard(
            title: localized("QUESTION"),
            subtitle: localized("Prompt"),
            isSelected: activeEditor == .question,
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
            HStack(alignment: .center, spacing: UIConstants.Spacing.standard) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("ANSWERS"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Text(
                        AppLocalization.numbered(
                            choices.count,
                            singular: "%d answer",
                            plural: "%d answers",
                            locale: locale
                        )
                    )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Toggle(localized("Multiple"), isOn: allowsMultipleCorrectBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Text(localized("Multiple Correct"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                QuizChoiceCard(
                    index: index,
                    canMoveDown: index < choices.count - 1,
                    choice: choice,
                    isSelected: activeEditor == .choice(choice.id),
                    highlightContext: highlightContext,
                    previewDirection: $previewDirection,
                    onActivate: {
                        activateEditor(.choice(choice.id))
                    },
                    onToggleCorrect: {
                        toggleCorrect(for: choice.id)
                    },
                    onMoveUp: {
                        moveChoice(choice.id, direction: -1)
                    },
                    onMoveDown: {
                        moveChoice(choice.id, direction: 1)
                    },
                    onDelete: {
                        deleteChoice(choice.id)
                    }
                )
            }

            Button {
                addChoice()
            } label: {
                Label(localized("Add Answer"), systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, UIConstants.Spacing.standard)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                            .stroke(accent.opacity(0.18), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("EXPLANATION"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Text(localized("Optional"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
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
                        isSelected: activeEditor == .explanation,
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
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                                .stroke(accent.opacity(0.18), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var allowsMultipleCorrectBinding: Binding<Bool> {
        Binding(
            get: { allowsMultipleCorrect },
            set: { newValue in
                allowsMultipleCorrect = newValue
                guard !newValue else { return }

                var firstCorrectChoiceID: UUID?
                for choice in choices where choice.isCorrect {
                    if firstCorrectChoiceID == nil {
                        firstCorrectChoiceID = choice.id
                    } else {
                        choice.isCorrect = false
                    }
                }
            }
        )
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

        withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
            choices.append(newChoice)
            activateEditor(.choice(newChoice.id))
        }

        requestFocus(for: newChoice.content.rootZone.id)
    }

    private func deleteChoice(_ choiceID: UUID) {
        guard let index = indexOfChoice(choiceID) else { return }
        let fallbackEditor: QuizEditorTarget

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

        if allowsMultipleCorrect {
            targetChoice.isCorrect.toggle()
            return
        }

        let willBecomeCorrect = !targetChoice.isCorrect
        for choice in choices {
            choice.isCorrect = false
        }
        targetChoice.isCorrect = willBecomeCorrect
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

    private func duplicateSelectedZone() {
        guard let content = currentContent, let path = currentSelectedPath else { return }

        var newZoneID: UUID?
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            newZoneID = content.duplicateZone(at: path)
            if let newZoneID, let newPath = findPath(for: newZoneID, in: content.rootZone) {
                currentSelectedPath = newPath
            }
        }

        if let newZoneID {
            requestFocus(for: newZoneID, delaySeconds: 0.12)
        }
    }

    private func moveSelectedZoneUp() {
        guard let content = currentContent, let path = currentSelectedPath else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if let newPath = content.moveZoneUp(at: path) {
                currentSelectedPath = newPath
            }
        }
    }

    private func moveSelectedZoneDown() {
        guard let content = currentContent, let path = currentSelectedPath else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if let newPath = content.moveZoneDown(at: path) {
                currentSelectedPath = newPath
            }
        }
    }

    private func splitZone() {
        guard let content = currentContent,
              let path = currentSelectedPath,
              let zone = content.zone(at: path),
              zone.contentType == .text else { return }

        let zoneID = zone.id
        let lines = zone.text.components(separatedBy: "\n")
        guard lines.count >= 2 else { return }

        let focusedLineIndex = zoneController.zoneHeightInfo(for: zoneID)?.focusedLineIndex ?? 0
        guard focusedLineIndex >= 0, focusedLineIndex < lines.count - 1 else { return }

        let splitResult = zone.text.splitAtLine(focusedLineIndex)
        focusManager.prepareForZoneInsertion()

        var createdZoneID: UUID?
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            content.updateZone(at: path) { currentZone in
                currentZone.text = splitResult.before
            }

            createdZoneID = content.addZone(relativeTo: path, direction: .down)

            if let createdZoneID, let createdPath = findPath(for: createdZoneID, in: content.rootZone) {
                content.updateZone(at: createdPath) { currentZone in
                    currentZone.text = splitResult.after
                    currentZone.contentType = .text
                    currentZone.textStyle = zone.textStyle
                    currentZone.textAlignment = zone.textAlignment
                    currentZone.sizeMode = zone.sizeMode
                    currentZone.blockAlignment = zone.blockAlignment
                    currentZone.fixedWidth = zone.fixedWidth
                    currentZone.fixedHeight = zone.fixedHeight
                    currentZone.textColor = zone.textColor
                    currentZone.isBold = zone.isBold
                    currentZone.isItalic = zone.isItalic
                    currentZone.hasBullet = zone.hasBullet
                    currentZone.fontFamily = zone.fontFamily
                    currentZone.highlightColor = zone.highlightColor
                }
                currentSelectedPath = createdPath
            }
        }

        if let createdZoneID {
            requestFocus(for: createdZoneID, delaySeconds: 0.1)
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

    private func saveCard() {
        questionContent.cleanup()
        choices.forEach { $0.content.cleanup() }
        explanationContent?.cleanup()

        let cleanedExplanationZone: ZoneModel?
        if let explanationContent, explanationContent.hasContent {
            cleanedExplanationZone = explanationContent.rootZone
        } else {
            cleanedExplanationZone = nil
        }

        let content = QuizCardContent(
            questionZone: questionContent.rootZone,
            choices: choices.map {
                QuizChoiceDraft(
                    id: $0.id,
                    contentZone: $0.content.rootZone,
                    isCorrect: $0.isCorrect
                )
            },
            explanationZone: cleanedExplanationZone,
            allowsMultipleCorrect: allowsMultipleCorrect
        )

        onSave(content)
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

    private func findPath(for id: UUID, in zone: ZoneModel, currentIndices: [Int] = []) -> ZonePath? {
        if zone.id == id {
            return ZonePath(indices: currentIndices)
        }

        guard let children = zone.children else { return nil }
        for (index, child) in children.enumerated() {
            if let foundPath = findPath(for: id, in: child, currentIndices: currentIndices + [index]) {
                return foundPath
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
}

/// Identifies which quiz section currently owns the bottom formatting bar.
private enum QuizEditorTarget: Equatable {
    case question
    case choice(UUID)
    case explanation
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
    let isSelected: Bool
    let content: ZoneCardContent
    @Binding var selectedPath: ZonePath?
    var highlightContext: HighlightContext?
    @Binding var previewDirection: AddDirection?
    @ViewBuilder var trailingContent: () -> TrailingContent
    let onActivate: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var accent: Color { ThemeManager.shared.accentColor.color }

    init(
        title: String,
        subtitle: String,
        isSelected: Bool,
        content: ZoneCardContent,
        selectedPath: Binding<ZonePath?>,
        highlightContext: HighlightContext?,
        previewDirection: Binding<AddDirection?>,
        @ViewBuilder trailingContent: @escaping () -> TrailingContent = { EmptyView() },
        onActivate: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
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
        .background(cardBackground, in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                .stroke(isSelected ? accent.opacity(0.35) : borderColor, lineWidth: 1)
        }
        .onTapGesture {
            onActivate()
        }
    }

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
            : AnyShapeStyle(Color.white)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }
}

/// One answer row with correctness controls and a mini zone editor.
private struct QuizChoiceCard: View {
    @Environment(AppPreferences.self) private var appPreferences

    let index: Int
    let canMoveDown: Bool
    @Bindable var choice: QuizChoiceEditorItem
    let isSelected: Bool
    var highlightContext: HighlightContext?
    @Binding var previewDirection: AddDirection?
    let onActivate: () -> Void
    let onToggleCorrect: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var locale: Locale { appPreferences.resolvedLocale }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private func localizedFormat(_ value: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = AppLocalization.string(value, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizedFormat("ANSWER %@", String(index + 1)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Button {
                        onToggleCorrect()
                    } label: {
                        Label(choice.isCorrect ? localized("Correct") : localized("Mark Correct"), systemImage: choice.isCorrect ? "checkmark.circle.fill" : "circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(choice.isCorrect ? accent : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((choice.isCorrect ? accent.opacity(0.12) : Color(uiColor: .tertiarySystemFill)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                HStack(spacing: UIConstants.Spacing.small) {
                    QuizChoiceActionButton(symbol: "arrow.up", isEnabled: index > 0, action: onMoveUp)
                    QuizChoiceActionButton(symbol: "arrow.down", isEnabled: canMoveDown, action: onMoveDown)
                    QuizChoiceActionButton(symbol: "trash", tint: .red, action: onDelete)
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
        .background(cardBackground, in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                .stroke(isSelected ? accent.opacity(0.35) : borderColor, lineWidth: 1)
        }
        .onTapGesture {
            onActivate()
        }
    }

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
            : AnyShapeStyle(Color.white)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
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

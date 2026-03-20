//
//  WriteCardEditorView.swift
//  QuizFlash
//
//  Manual write-card authoring with one text surface and one anchored blank.
//

import SwiftUI

/// A manual editor for write cards built around one text surface and one blank selection.
struct WriteCardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var sourceZone: ZoneModel
    @State private var selectedRange: NSRange
    @State private var blankSelection: WriteBlankSelection?
    @State private var isEditorFocused = false

    private let onSave: (WriteCardContent) -> Void

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var focusManager = ZoneFocusManager.shared

    init(
        initialContent: WriteCardContent,
        onSave: @escaping (WriteCardContent) -> Void
    ) {
        let normalizedZone = Self.normalizedSourceZone(from: initialContent.sourceZone)
        let restoredBlank = WriteBlankTextHelper.validatedBlankSelection(
            initialContent.blankSelection,
            in: normalizedZone.text,
            fallbackZoneID: normalizedZone.id
        )

        _sourceZone = State(initialValue: normalizedZone)
        _selectedRange = State(
            initialValue: restoredBlank.map { WriteBlankTextHelper.nsRange(for: $0) } ?? NSRange(location: 0, length: 0)
        )
        _blankSelection = State(initialValue: restoredBlank)
        self.onSave = onSave
    }

    private var validationMessage: String? {
        let trimmedText = sourceZone.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return "Add source text before saving."
        }

        guard activeBlankSelection != nil else {
            return "Select a non-empty substring to turn into the blank."
        }

        return nil
    }

    private var canSave: Bool {
        validationMessage == nil
    }

    private var currentSelectionText: String? {
        substring(in: selectedRange, within: sourceZone.text)
    }

    private var canMarkSelectionAsBlank: Bool {
        guard let currentSelectionText else { return false }
        return !currentSelectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activeBlankSelection: WriteBlankSelection? {
        guard let blankSelection else { return nil }
        return WriteBlankTextHelper.validatedBlankSelection(
            blankSelection,
            in: sourceZone.text,
            fallbackZoneID: sourceZone.id
        )
    }

    private var blankedPreviewText: String {
        guard let blankSelection = activeBlankSelection else { return sourceZone.text }
        return applyingBlank(blankSelection, to: sourceZone.text)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
                    sourceSection
                    selectionSection
                    previewSection

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, UIConstants.Spacing.large)
                .padding(.top, UIConstants.Spacing.large)
                .padding(.bottom, UIConstants.Spacing.huge)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(backgroundGradient.ignoresSafeArea())
            .navigationTitle("Write Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar { toolbarContent }
            .swipeBack {
                dismiss()
            }
            .task {
                try? await Task.sleep(for: .milliseconds(350))
                focusManager.requestFocus(for: sourceZone.id)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                dismiss()
            }
            .tint(.secondary)
        }

        ToolbarItem(placement: .primaryAction) {
            Button("Save") {
                saveCard()
            }
            .fontWeight(.semibold)
            .disabled(!canSave)
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            sectionHeader(
                title: "PROMPT",
                subtitle: "Edit the source text, then select the part you want learners to fill in."
            )

            ZStack(alignment: .topLeading) {
                Text(editorMeasurementText)
                    .font(editorFont)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(0)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ZoneTextViewRepresentable(
                    text: sourceTextBinding,
                    font: editorUIFont,
                    textColor: UIColor(sourceTextColor),
                    textAlignment: .left,
                    isBold: false,
                    isItalic: false,
                    zoneID: sourceZone.id,
                    isFirstResponder: isEditorFocused,
                    onTextChange: { newText in
                        updateSourceText(newText)
                    },
                    onCursorChange: { range, _ in
                        selectedRange = range
                    },
                    onFocusChange: { focused in
                        isEditorFocused = focused
                    }
                )
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 220, alignment: .topLeading)
            .padding(.horizontal, UIConstants.Spacing.standard)
            .padding(.vertical, UIConstants.Spacing.small)
            .background(editorCardBackground, in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                    .stroke(isEditorFocused ? accent.opacity(0.35) : borderColor, lineWidth: 1)
            }
        }
    }

    private var selectionSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            sectionHeader(
                title: "BLANK",
                subtitle: "Use the current text selection as the omitted answer."
            )

            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Selected Text")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    if let currentSelectionText, !currentSelectionText.isEmpty {
                        Text(currentSelectionText)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                    } else {
                        Text("Select text in the editor to define the blank.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: UIConstants.Spacing.small) {
                    Button {
                        markSelectionAsBlank()
                    } label: {
                        Label("Mark Blank", systemImage: "rectangle.and.pencil.and.ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(canMarkSelectionAsBlank ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, UIConstants.Spacing.standard)
                            .background((canMarkSelectionAsBlank ? accent : Color(uiColor: .tertiarySystemFill)), in: RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canMarkSelectionAsBlank)

                    Button {
                        clearBlankSelection()
                    } label: {
                        Label("Clear", systemImage: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(activeBlankSelection == nil ? Color.secondary : Color.red)
                            .padding(.horizontal, UIConstants.Spacing.standard)
                            .padding(.vertical, UIConstants.Spacing.standard)
                            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(activeBlankSelection == nil)
                }

                if let activeBlankSelection {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stored Answer")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        Text(activeBlankSelection.omittedText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(accent.opacity(0.12), in: Capsule())
                    }
                }
            }
            .padding(UIConstants.Spacing.standard)
            .background(editorCardBackground, in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            sectionHeader(
                title: "PREVIEW",
                subtitle: "This is the prompt learners will see."
            )

            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                if blankedPreviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Add text and mark a blank to preview the card.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    MixedMathTextView(
                        text: blankedPreviewText,
                        fontSize: 20,
                        textColor: .primary,
                        alignment: .leading,
                        isInteractive: false,
                        allowsReadOnlyOverflowScrolling: true
                    )
                }
            }
            .padding(UIConstants.Spacing.standard)
            .background(editorCardBackground, in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Text(subtitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private var sourceTextBinding: Binding<String> {
        Binding(
            get: { sourceZone.text },
            set: { newValue in
                updateSourceText(newValue)
            }
        )
    }

    private func updateSourceText(_ newValue: String) {
        guard sourceZone.text != newValue else { return }
        sourceZone.text = newValue
        sourceZone.contentType = .text

        if let currentBlankSelection = blankSelection {
            blankSelection = WriteBlankTextHelper.validatedBlankSelection(
                currentBlankSelection,
                in: newValue,
                fallbackZoneID: sourceZone.id
            )
        }
    }

    private func markSelectionAsBlank() {
        guard let omittedText = currentSelectionText,
              !omittedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        blankSelection = WriteBlankSelection(
            zoneID: sourceZone.id,
            utf16Range: selectedRange.location..<(selectedRange.location + selectedRange.length),
            omittedText: omittedText
        )
    }

    private func clearBlankSelection() {
        blankSelection = nil
    }

    private func saveCard() {
        guard let blankSelection = activeBlankSelection else { return }

        let content = WriteCardContent(
            sourceZone: sourceZone,
            blankSelection: blankSelection
        )

        onSave(content)
        focusManager.forceReleaseKeyboard()
        dismiss()
    }

    private func substring(in range: NSRange, within text: String) -> String? {
        guard range.length > 0,
              let stringRange = Range(range, in: text) else { return nil }
        return String(text[stringRange])
    }

    private func applyingBlank(_ blankSelection: WriteBlankSelection, to text: String) -> String {
        WriteBlankTextHelper.applyingBlank(blankSelection, to: text) ?? text
    }

    private var editorMeasurementText: String {
        let rawText = sourceZone.text
        return rawText.isEmpty ? " " : rawText + " "
    }

    private var editorFont: Font {
        .system(size: 22, weight: .regular, design: .rounded)
    }

    private var editorUIFont: UIFont {
        .systemFont(ofSize: 22, weight: .regular)
    }

    private var sourceTextColor: Color {
        .primary
    }

    private var editorCardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
            : AnyShapeStyle(Color.white)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
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

    private nonisolated static func normalizedSourceZone(from zone: ZoneModel) -> ZoneModel {
        if zone.isLeaf {
            var normalizedZone = zone
            normalizedZone.contentType = .text
            normalizedZone.children = nil
            normalizedZone.imageData = nil
            normalizedZone.codeLanguage = nil
            return normalizedZone
        }

        return ZoneModel.text(WriteBlankTextHelper.normalizedSourceText(from: zone))
    }
}

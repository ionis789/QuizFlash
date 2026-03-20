//
//  MatchCardEditorView.swift
//  QuizFlash
//
//  Manual match-card authoring with one short prompt and one short answer.
//

import SwiftUI

/// A focused editor for dedicated match cards.
struct MatchCardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var prompt: String
    @State private var answer: String
    @FocusState private var focusedField: Field?

    private let onSave: (MatchCardContent) -> Void

    private var accent: Color { ThemeManager.shared.accentColor.color }

    init(
        initialContent: MatchCardContent,
        onSave: @escaping (MatchCardContent) -> Void
    ) {
        _prompt = State(initialValue: initialContent.prompt)
        _answer = State(initialValue: initialContent.answer)
        self.onSave = onSave
    }

    private enum Field: Hashable {
        case prompt
        case answer
    }

    private var validationMessage: String? {
        if normalizedPrompt.isEmpty {
            return "Add a short prompt before saving."
        }

        if normalizedAnswer.isEmpty {
            return "Add the matching answer before saving."
        }

        return nil
    }

    private var canSave: Bool {
        validationMessage == nil
    }

    private var normalizedPrompt: String {
        normalizedSingleLine(prompt)
    }

    private var normalizedAnswer: String {
        normalizedSingleLine(answer)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
                    editorSection(
                        title: "PROMPT",
                        subtitle: "Keep it short enough to read instantly during a matching round.",
                        text: $prompt,
                        field: .prompt,
                        placeholder: "Example: Capital of France"
                    )

                    editorSection(
                        title: "ANSWER",
                        subtitle: "Use the exact short answer that should pair with the prompt.",
                        text: $answer,
                        field: .answer,
                        placeholder: "Example: Paris"
                    )

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
            .navigationTitle("Match Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar { toolbarContent }
            .task {
                focusedField = .prompt
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

    private func editorSection(
        title: String,
        subtitle: String,
        text: Binding<String>,
        field: Field,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            sectionHeader(title: title, subtitle: subtitle)

            TextEditor(text: text)
                .focused($focusedField, equals: field)
                .scrollContentBackground(.hidden)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(minHeight: 132, alignment: .topLeading)
                .padding(UIConstants.Spacing.standard)
                .background(editorCardBackground, in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(placeholder)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, UIConstants.Spacing.large)
                            .padding(.vertical, UIConstants.Spacing.large)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                        .stroke(
                            focusedField == field ? accent.opacity(0.35) : borderColor,
                            lineWidth: 1
                        )
                }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            sectionHeader(
                title: "PREVIEW",
                subtitle: "This is how the pair will read when Match uses the dedicated card."
            )

            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                previewRow(title: "Prompt", text: normalizedPrompt.isEmpty ? "No prompt added" : normalizedPrompt)
                previewRow(title: "Answer", text: normalizedAnswer.isEmpty ? "No answer added" : normalizedAnswer)
            }
            .padding(UIConstants.Spacing.standard)
            .background(editorCardBackground, in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
        }
    }

    private func previewRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.black, Color(white: 0.08)]
                : [Color(uiColor: .systemGroupedBackground), Color(uiColor: .secondarySystemGroupedBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var editorCardBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.035)
            : Color.white.opacity(0.82)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.09)
            : Color.black.opacity(0.06)
    }

    private func saveCard() {
        guard canSave else { return }
        onSave(
            MatchCardContent(
                prompt: normalizedPrompt,
                answer: normalizedAnswer
            )
        )
        dismiss()
    }

    private func normalizedSingleLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

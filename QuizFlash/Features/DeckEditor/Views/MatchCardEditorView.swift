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
    @Environment(AppPreferences.self) private var appPreferences

    @State private var prompt: String
    @State private var answer: String
    @FocusState private var focusedField: Field?

    private let onSave: (MatchCardContent) -> Void

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var locale: Locale { appPreferences.resolvedLocale }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

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


    private var canSave: Bool {
        if normalizedPrompt.isEmpty || normalizedAnswer.isEmpty {
            return false
        }
        return true
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
                        title: localized("PROMPT"),
                        text: $prompt,
                        field: .prompt,
                        placeholder: localized("Example: Capital of France")
                    )

                    editorSection(
                        title: localized("ANSWER"),
                        text: $answer,
                        field: .answer,
                        placeholder: localized("Example: Paris")
                    )
                }
                    .padding(.horizontal, UIConstants.Spacing.large)
                    .padding(.top, UIConstants.Spacing.large)
                    .padding(.bottom, UIConstants.Spacing.huge)
            }
                .scrollDismissesKeyboard(.interactively)
                .background(backgroundGradient.ignoresSafeArea())
                .navigationTitle(localized("Match Card"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbar { toolbarContent }
                .swipeBack {
                dismiss()
            }
                .task {
                focusedField = .prompt
            }
        }
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
            Button(localized("Save")) {
                saveCard()
            }
                .fontWeight(.semibold)
                .disabled(!canSave)
        }
    }

    private func editorSection(
        title: String,
        text: Binding<String>,
        field: Field,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            sectionHeader(title: title)

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

    private func sectionHeader(title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
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

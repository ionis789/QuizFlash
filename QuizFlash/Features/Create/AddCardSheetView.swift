//
//  AddCardSheetView.swift
//  QuizFlash
//
//  Created by Ion Socol on 04.01.2026.
//

import SwiftUI

struct AddCardSheetView: View {
    @Environment(\.dismiss) var dismiss

    var onSave: (String, String) -> Void

    @State private var frontText: String
    @State private var backText: String
    @State private var activeField: CardSide = .question
    @FocusState private var isEditorFocused: Bool

    enum CardSide {
        case question, answer
    }

    init(initialFront: String = "", initialBack: String = "", onSave: @escaping (String, String) -> Void) {
        _frontText = State(initialValue: initialFront)
        _backText = State(initialValue: initialBack)
        self.onSave = onSave
    }

    private var canSave: Bool {
        !frontText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !backText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var currentText: Binding<String> {
        activeField == .question ? $frontText : $backText
    }
    
    private var currentPlaceholder: String {
        activeField == .question ? "Enter question..." : "Enter answer..."
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                HStack(spacing: 12) {
                    tabButton(title: "Question", side: .question, hasContent: !frontText.isEmpty)
                    tabButton(title: "Answer", side: .answer, hasContent: !backText.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                Divider()
                
                // Editor
                ZStack(alignment: .topLeading) {
                    TextEditor(text: currentText)
                        .focused($isEditorFocused)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    
                    if currentText.wrappedValue.isEmpty {
                        Text(currentPlaceholder)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Divider()
                
                // Bottom toolbar (media buttons)
                HStack(spacing: 24) {
                    mediaButton(icon: "photo", label: "Photo")
                    mediaButton(icon: "mic", label: "Audio")
                    
                    Spacer()
                    
                    // Character count
                    Text("\(currentText.wrappedValue.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemBackground))
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }

                ToolbarItem(placement: .principal) {
                    Text("New Card")
                        .font(.headline)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            frontText.trimmingCharacters(in: .whitespacesAndNewlines),
                            backText.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isEditorFocused = false
                    }
                    .font(.subheadline.weight(.medium))
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isEditorFocused = true
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Tab Button
    @ViewBuilder
    private func tabButton(title: String, side: CardSide, hasContent: Bool) -> some View {
        let isActive = activeField == side
        
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                activeField = side
            }
            isEditorFocused = true
        } label: {
            HStack(spacing: 6) {
                if hasContent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                
                Text(title)
                    .font(.subheadline.weight(isActive ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? Color(uiColor: .secondarySystemBackground) : Color.clear)
            )
            .foregroundStyle(isActive ? .primary : .secondary)
        }
    }
    
    // MARK: - Media Button
    @ViewBuilder
    private func mediaButton(icon: String, label: String) -> some View {
        Button {
            // TODO: Implement media picker
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    AddCardSheetView { _, _ in }
}

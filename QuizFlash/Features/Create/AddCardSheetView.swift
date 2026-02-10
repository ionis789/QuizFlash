import SwiftUI

struct AddCardSheetView: View {
    @Environment(\.dismiss) var dismiss
    var onSave: (String, String) -> Void

    @State private var frontText: String
    @State private var backText: String
    @State private var activeField: CardSide = .question
    @FocusState private var isEditorFocused: Bool

    private var accent: Color { ThemeManager.shared.accentColor.color }


    enum CardSide { case question, answer }

    init(initialFront: String = "", initialBack: String = "", onSave: @escaping (String, String) -> Void) {
        _frontText = State(initialValue: initialFront)
        _backText = State(initialValue: initialBack)
        self.onSave = onSave
    }


    private var currentEditorText: Binding<String> {
        activeField == .question ? $frontText: $backText
    }

    private var canSave: Bool {
        !frontText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !backText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }


    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top Tab Bar
                    topTabBar

                    // Editor
                    editorSection
                }
            }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                toolbarView
            }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(frontText, backText)
                        dismiss()
                    }
                        .foregroundStyle(canSave ? accent : Color.gray)
                        .disabled(!canSave)
                }
                    
                    ToolbarItem(placement: .keyboard) {
                        toolbarView
                    }
            }
                .onAppear {
                isEditorFocused = true
            }
        }
    }

    // MARK: - Top Tab Bar
    private var topTabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton(
                    title: "QUESTION",
                    side: .question,
                    textCount: frontText.count
                )
                tabButton(
                    title: "ANSWER",
                    side: .answer,
                    textCount: backText.count
                )
            }
                .padding(.vertical, 12)

            Divider()
                .overlay(Color.white.opacity(0.15))
        }
    }

    // MARK: - Editor Section
    private var editorSection: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: currentEditorText)
                .focused($isEditorFocused)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(20)

            if currentEditorText.wrappedValue.isEmpty {
                Text(activeField == .question ? "Enter question..." : "Enter answer...")
                    .font(.body)
                    .foregroundStyle(Color.gray.opacity(0.5))
                    .padding(24)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Toolbar View
    private var toolbarView: some View {
        HStack(alignment: .center, spacing: 16) {
            // Media Buttons
            HStack(spacing: 24) {
                Button { } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(accent)
                }
                Spacer()
                Button { } label: {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(accent)
                }



            }

        }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
    }





    // MARK: - Tab Button
    private func tabButton(title: String, side: CardSide, textCount: Int) -> some View {
        let isActive = activeField == side

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeField = side
            }
            isEditorFocused = true
        } label: {

            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                    isActive ? accent : Color.white.opacity(0.55)
                )

                Text("(\(textCount))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.gray)

            }
                .padding()
                .frame(maxWidth: .infinity)
                .contentShape(Capsule())
                .background {
                if isActive {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }

            }
        }

            .buttonStyle(.plain)
    }
}

// MARK: - Preview
struct AddCardSheetView_Previews: PreviewProvider {
    static var previews: some View {
        AddCardSheetView { _, _ in }
    }
}

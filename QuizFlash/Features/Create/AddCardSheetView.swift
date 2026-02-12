import SwiftUI

struct AddCardSheetView: View {
    @Environment(\.dismiss) var dismiss
    var onSave: (String, String) -> Void

    @State private var frontText: String
    @State private var backText: String
    @State private var activeField: CardSide = .question
    
    // This controls the logic: True = Keyboard Toolbar, False = Floating Button
    @FocusState private var isEditorFocused: Bool

    // Mocking ThemeManager for the example to compile
    private var accent: Color = ThemeManager.shared.accentColor.color
    // If you have ThemeManager, use: ThemeManager.shared.accentColor.color

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
            // 1. PLACE THE FLOATING BUTTON IN AN OVERLAY
            .overlay(alignment: .bottomTrailing) {
                floatingPlusButton
            }
            // 2. KEYBOARD TOOLBAR (Only appears when keyboard is up)
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    keyboardToolbarView
                }
                
                // Navigation Bar Items
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
            }
            .onAppear {
                // Optional: Start focused, or remove to start with Floating Button visible
                isEditorFocused = true
            }
        }
    }

    // MARK: - Floating Plus Button (Apple Notes Style)
    private var floatingPlusButton: some View {
        Group {
            // Only show when keyboard is NOT focused
            if !isEditorFocused {
                Menu {
                    Button {
                        // Action for Camera
                    } label: {
                        Label("Scan Documents", systemImage: "doc.viewfinder")
                    }
                    
                    Button {
                        // Action for Photo
                    } label: {
                        Label("Choose Photo", systemImage: "photo")
                    }
                    
                    Button {
                        // Action for Format
                    } label: {
                        Label("Format Text", systemImage: "textformat")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundStyle(accent)
                        .background(Color.black) // Hides content behind the circle
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .padding(24) // Distance from edges
                .transition(.opacity.combined(with: .scale)) // Fade and scale effect
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isEditorFocused)
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
            // Expanded TextEditor to take available space
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
        // Tapping background dismisses keyboard to show floating button
        .contentShape(Rectangle())
        .onTapGesture {
            isEditorFocused = true
        }
    }

    // MARK: - Keyboard Toolbar View
    // This looks like the native keyboard accessory bar
    private var keyboardToolbarView: some View {
        HStack(alignment: .center, spacing: 16) {
            Button { } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(accent)
            }
            
            Spacer()
            
            // You can add the menu here too if you want it accessible from keyboard
            Menu {
                Button("Format", systemImage: "textformat") {}
                Button("Photo", systemImage: "photo") {}
            } label: {
                 Image(systemName: "plus")
                    .font(.system(size: 20))
                    .foregroundStyle(accent)
            }
        }
        .padding(.vertical, 8)
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

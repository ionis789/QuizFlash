import SwiftUI

struct AddCardSheetView: View {
    @Environment(\.dismiss) var dismiss
    var onSave: (String, String) -> Void
    
    @State private var frontText: String
    @State private var backText: String
    @State private var activeField: CardSide = .question
    @FocusState private var isEditorFocused: Bool
    
    // Keyboard tracking pentru sincronizare perfectă
    @State private var keyboardHeight: CGFloat = 0
    
    enum CardSide { case question, answer }
    
    init(initialFront: String = "", initialBack: String = "", onSave: @escaping (String, String) -> Void) {
        _frontText = State(initialValue: initialFront)
        _backText = State(initialValue: initialBack)
        self.onSave = onSave
    }
    
    private var currentText: Binding<String> {
        activeField == .question ? $frontText : $backText
    }
    
    private var canSave: Bool {
        !frontText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !backText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private let accentYellow = Color(red: 1.0, green: 0.8, blue: 0.0)
    
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
                    // ✅ Offset dinamic bazat pe keyboard height
                    .offset(y: keyboardHeight > 0 ? -keyboardHeight : 0)
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
                    .foregroundStyle(canSave ? accentYellow : Color.gray)
                    .disabled(!canSave)
                }
            }
            .onAppear {
                setupKeyboardObservers()
            }
        }
    }
    
    // MARK: - Top Tab Bar
    private var topTabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton(title: "QUESTION", side: .question)
                tabButton(title: "ANSWER", side: .answer)
            }
            .padding(.top, 10)
            
            Divider()
                .overlay(Color.white.opacity(0.15))
        }
    }
    
    // MARK: - Editor Section
    private var editorSection: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: currentText)
                .focused($isEditorFocused)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(20)
            
            if currentText.wrappedValue.isEmpty {
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
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(accentYellow)
                }
                
                Button { } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(accentYellow)
                }
            }
            
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 1, height: 24)
            
            Text("\(currentText.wrappedValue.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.gray)
            
            Spacer()
            
            Button {
                isEditorFocused = false
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 20)
                    .background(accentYellow)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .clipShape(
            .rect(
                topLeadingRadius: 30,
                bottomLeadingRadius: keyboardHeight > 0 ? 0 : 30,
                bottomTrailingRadius: keyboardHeight > 0 ? 0 : 30,
                topTrailingRadius: 30
            )
        )
        .shadow(color: keyboardHeight > 0 ? .clear : .black.opacity(0.3), radius: 10, y: 5)
        .padding(.horizontal, keyboardHeight > 0 ? 0 : 20)
        .padding(.bottom, keyboardHeight > 0 ? 0 : 12)
    }
    
    // MARK: - Keyboard Observers
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            handleKeyboardShow(notification)
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { notification in
            handleKeyboardHide(notification)
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { notification in
            handleKeyboardShow(notification)
        }
    }
    
    private func handleKeyboardShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int else {
            return
        }
        
        let curve = UIView.AnimationCurve(rawValue: curveValue) ?? .easeOut
        
        withAnimation(.timingCurve(curve.toSwiftUI(), duration: duration)) {
            keyboardHeight = keyboardFrame.height
        }
    }
    
    private func handleKeyboardHide(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int else {
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
            return
        }
        
        let curve = UIView.AnimationCurve(rawValue: curveValue) ?? .easeOut
        
        withAnimation(.timingCurve(curve.toSwiftUI(), duration: duration)) {
            keyboardHeight = 0
        }
    }
    
    // MARK: - Tab Button
    private func tabButton(title: String, side: CardSide) -> some View {
        let isActive = activeField == side
        
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeField = side
            }
            isEditorFocused = true
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? accentYellow : Color.white.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Animation Curve Extension
extension UIView.AnimationCurve {
    func toSwiftUI() -> UnitCurve {
        switch self {
        case .easeInOut:
            return .easeInOut
        case .easeIn:
            return .easeIn
        case .easeOut:
            return .easeOut
        case .linear:
            return .linear
        @unknown default:
            return .easeOut
        }
    }
}

// MARK: - Preview
struct AddCardSheetView_Previews: PreviewProvider {
    static var previews: some View {
        AddCardSheetView { _, _ in }
    }
}

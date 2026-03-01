//
//  CustomMenuButton.swift
//  QuizFlash
//

import SwiftUI

/// Buton reutilizabil pentru consistență vizuală în interiorul meniului
struct CustomMenuButton: View {
    private var accent: Color { ThemeManager.shared.accentColor.color }
    let title: String
    let icon: String
    var isSelected: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? accent : Color.primary)
                Spacer(minLength: 0)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isSelected ? accent : Color.primary)
                    .frame(width: 24, alignment: .center)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1.0)
        // Adăugăm un hover effect nativ foarte subtil (dacă dorești suport și pe iPadOS)
        .hoverEffect(.highlight)
    }
}

/// O clasă simplă de referință folosită pentru a urmări poziția meniului în timpul scroll-ului
/// fără a declanșa recalculări de 120Hz prin @State (care cauzează lag masiv și layout thrashing).
public final class MenuPositionTracker {
    public var rect: CGRect = .zero
    public init() {}
}

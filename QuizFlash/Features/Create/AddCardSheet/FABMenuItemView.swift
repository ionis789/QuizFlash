//
//  FABMenuItemView.swift
//  QuizFlash
//
//  UI-only: single FAB menu item (Photo / Sketch).
//

import SwiftUI

// MARK: - FAB Menu Item

struct FABMenuItem: View {
    let icon: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label).font(.subheadline.weight(.medium))
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: .tertiarySystemBackground))
                    .clipShape(Circle())
            }
            .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundStyle(.primary)
    }
}

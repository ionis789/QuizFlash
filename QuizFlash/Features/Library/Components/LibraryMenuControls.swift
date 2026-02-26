//
//  LibraryMenuControls.swift
//  QuizFlash
//
//  Created by Ion Socol on 24.02.2026.
//

import SwiftUI

struct LibraryMenuControls: View {
    @Bindable var viewModel: LibraryViewModel
    @Binding var isExpanded: Bool
    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            // Secțiunea de Acțiuni Principale
            CustomMenuButton(title: "Import Deck", icon: "square.and.arrow.down") {
                viewModel.showFileImporter = true
                closeMenu()
            }

            CustomMenuButton(title: "Select", icon: "checkmark.circle", disabled: viewModel.isSelecting || viewModel.isSearching) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.isSelecting = true
                }
                closeMenu()
            }

            Divider()
                .background(Color.primary.opacity(0.1))
                .padding(.vertical, 4)

            // Secțiunea de Sortare (Aplatizată pentru UX mai bun)
            Text("SORT BY")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 2)

            ForEach(SortOrder.allCases, id: \.self) { order in
                CustomMenuButton(
                    title: order.rawValue,
                    icon: viewModel.sortOrder == order ? "checkmark" : order.icon,
                    isSelected: viewModel.sortOrder == order ? true : false
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        viewModel.sortOrder = order
                    }
                    closeMenu()
                }
            }
        }
            .padding(12)
            .foregroundStyle(.primary)
    }

    private func closeMenu() {
        withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
            isExpanded = false
        }
    }
}

// Buton reutilizabil pentru consistență vizuală în interiorul meniului
struct CustomMenuButton: View {
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
                    .foregroundStyle(isSelected ? Color.accent : Color.primary)
                Spacer(minLength: 0)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isSelected ? Color.accent : Color.primary)
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


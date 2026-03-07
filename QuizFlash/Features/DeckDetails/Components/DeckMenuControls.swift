//
//  DeckMenuControls.swift
//  QuizFlash
//

import SwiftUI

struct DeckMenuControls: View {
    @Bindable var deck: DeckModel
    let isSelecting: Bool
    @Binding var sortOrder: SortOrder
    @Binding var isExpanded: Bool

    var onStartSelection: () -> Void
    var onExport: (() -> Void)?

    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            // Main Actions Section
            CustomMenuButton(
                title: "Select Cards",
                icon: "checkmark.circle",
                disabled: isSelecting
            ) {
                onStartSelection()
                closeMenu()
            }

            if let onExport = onExport {
                CustomMenuButton(
                    title: "Export Deck",
                    icon: "square.and.arrow.up"
                ) {
                    onExport()
                    closeMenu()
                }
            }

            Divider()
                .background(Color.primary.opacity(0.1))
                .padding(.vertical, 4)

            // Sorting Section
            Text("SORT BY")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 2)

            ForEach(SortOrder.allCases, id: \.self) { order in
                CustomMenuButton(
                    title: order.rawValue,
                    icon: sortOrder == order ? "checkmark" : order.icon,
                    isSelected: sortOrder == order
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        sortOrder = order
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

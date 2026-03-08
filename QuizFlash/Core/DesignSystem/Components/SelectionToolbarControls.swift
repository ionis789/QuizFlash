//
//  SelectionToolbarControls.swift
//  QuizFlash
//
//  Shared controls used by selection toolbars across Library and Deck screens.
//

import SwiftUI

// MARK: - SelectionToolbarIconButton

/// A shared circular glass action button used inside selection toolbars.
struct SelectionToolbarIconButton<Label: View>: View {
    let isEnabled: Bool
    let accessibilityLabel: String
    var badgeCount: Int? = nil
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(
                    width: UIConstants.Size.selectionToolbarControl,
                    height: UIConstants.Size.selectionToolbarControl
                )
                .glassButton(shape: .circle)
        }
        .overlay(alignment: .topTrailing) {
            if let badgeCount {
                SelectionCountBadge(count: badgeCount)
                    .offset(x: 5, y: -5)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - SelectionCountBadge

/// A compact numeric badge attached to icon-only selection actions.
struct SelectionCountBadge: View {
    let count: Int

    private var badgeColor: Color {
        count == 0 ? Color.secondary.opacity(0.8) : .red
    }

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 24)
            .background(badgeColor, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .allowsHitTesting(false)
    }
}

//
//  SelectionToolbarControls.swift
//  QuizFlash
//
//  Shared controls used by selection toolbars across Library and Deck screens.
//

import SwiftUI

// MARK: - SelectionToolbarCapsuleButton

/// A shared capsule action button used by selection toolbars.
struct SelectionToolbarCapsuleButton<Label: View>: View {
    let action: () -> Void
    let accessibilityLabel: String
    var isEnabled: Bool = true
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 10)
                .frame(height: UIConstants.Size.selectionToolbarControl)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - SelectionToolbarTextButton

/// A lightweight text action used by minimalist selection bars.
struct SelectionToolbarTextButton: View {
    let title: String
    let accessibilityLabel: String
    var isEnabled: Bool = true
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, 4)
                .frame(height: UIConstants.Size.selectionToolbarControl)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(accessibilityLabel)
    }
}

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
        }
        .overlay(alignment: .topTrailing) {
            if let badgeCount, badgeCount > 0 {
                SelectionCountBadge(count: badgeCount)
                    .offset(x: 4, y: -4)
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
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(badgeColor, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .allowsHitTesting(false)
    }
}

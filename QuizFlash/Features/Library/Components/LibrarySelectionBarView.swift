//
//  LibrarySelectionBarView.swift
//  QuizFlash
//
//  Bottom contextual bar shown during multi-select.
//  Floats above the tab bar with glass material.
//

import SwiftUI

/// A floating contextual bar displayed at the bottom of the screen during selection mode.
/// Provides actions for selected decks such as exporting or deleting.
struct LibrarySelectionBarView: View {

    @Bindable var viewModel: LibraryViewModel
    let decks: [DeckModel]
    let onDeleteTap: () -> Void

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var selectedCount: Int { viewModel.selectedDecks.count }

    var body: some View {
        HStack(spacing: 10) {

            // ── Done ──────────────────────────────────────────────────────────
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.exitSelectionMode()
                }
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(ScaleButtonStyle())

            Spacer()

            // ── Selected count badge ──────────────────────────────────────────
            if selectedCount > 0 {
                Text("\(selectedCount) selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .scale))
            }

            Spacer()

            // ── Export ────────────────────────────────────────────────────────
            Button {
                viewModel.exportSelectedDecks(from: decks)
            } label: {
                Group {
                    if viewModel.isExporting {
                        ProgressView().scaleEffect(0.75)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundStyle(selectedCount == 0 ? .primary : accent)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(selectedCount == 0
                                  ? Color.secondary.opacity(0.1)
                                  : accent.opacity(0.15))
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(selectedCount == 0 || viewModel.isExporting)

            // ── Delete ────────────────────────────────────────────────────────
            Button {
                onDeleteTap()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selectedCount == 0 ? .secondary : Color.red)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(selectedCount == 0
                                      ? Color.secondary.opacity(0.1)
                                      : Color.red.opacity(0.15))
                    )
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(selectedCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .contentShape(Rectangle())  // Absorb all taps including padding — prevent fall-through to layers below.
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedCount)
    }
}


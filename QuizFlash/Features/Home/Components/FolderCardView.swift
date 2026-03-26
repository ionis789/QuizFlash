// FolderCardView.swift
// QuizFlash
//
// Grid card components for the Folders section of HomeDashboardView.

import SwiftUI

// MARK: - Folder Card

/// A tactile folder card that visually mimics a native iOS folder with layered depth.
///
/// The card colour is derived from `FolderModel.colorHex` (user-chosen) rather than
/// the global theme accent, so each folder retains its individual identity.
///
/// - Parameters:
///   - folder: The folder model to display.
///   - action: Called when the user taps the card to open the folder.
struct FolderCardView: View {

    // MARK: - Input

    let folder: FolderModel
    let usesRegularMetrics: Bool
    let action: () -> Void

    // MARK: - Body

    var body: some View {
        let folderColor = Color(hex: folder.colorHex) ?? ThemeManager.shared.accentColor.color
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {

                // MARK: Header

                HStack {
                    Image(systemName: "folder.fill")
                        .font(usesRegularMetrics ? .system(size: 30, weight: .semibold) : .title)
                        .foregroundStyle(folderColor.gradient)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 16)

                // MARK: Title

                Text(folder.title)
                    .font(.headline.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.bottom, 4)

                // MARK: Deck Count

                // Safe: deckCount is a denormalized Int — no relationship fault at render time.
                Text("\(folder.deckCount) decks")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(usesRegularMetrics ? 18 : 16)
            .frame(minHeight: usesRegularMetrics ? 142 : 0, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetStyle()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty State Placeholder

/// A dashed-border placeholder card shown in the Folders grid when the user has no folders.
///
/// - Parameters:
///   - icon: An SF Symbols identifier shown above the message.
///   - message: A short guidance string (e.g. "No folders yet. Create one to organize your decks.").
struct EmptyStatePlaceholderFolderCard: View {

    // MARK: - Input

    let icon: String
    let message: String

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)

            Text(message)
                .font(.subheadline.weight(.medium))
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    Color(uiColor: .tertiaryLabel).opacity(0.3),
                    style: StrokeStyle(lineWidth: 1, dash: [6])
                )
        )
    }
}

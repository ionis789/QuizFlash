//
//  FolderCardView.swift
//  QuizFlash
//
//  Created by Ion Socol on 07.03.2026.
//

import SwiftUI

// MARK: - Folder Card (Tactile Style)
/// Designed to look more like a native iOS folder structure with depth.
struct FolderCardView: View {
    let folder: FolderModel
    let action: () -> Void

    var body: some View {
        let folderColor = Color(hex: folder.colorHex) ?? .blue

        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Header Area with Folder Icon
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.title)
                        .foregroundStyle(folderColor.gradient)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                    .padding(.bottom, 16)

                // Title Area
                Text(folder.title)
                    .font(.headline.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.bottom, 4)

                Text("\(folder.deckCount) decks")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(
                    Color.libraryDeckRow
                        .shadow(.inner(color: Color.white.opacity(0.15), radius: 1, x: 0, y: 0))
                )
            }
                .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 5, x: 0, y: 2)
        }
            .buttonStyle(.plain)
    }
}


// MARK: - Empty State View
struct EmptyStatePlaceholderFolderCard: View {
    let icon: String
    let message: String

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
                .strokeBorder(Color(uiColor: .tertiaryLabel).opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6]))
        )
    }
}

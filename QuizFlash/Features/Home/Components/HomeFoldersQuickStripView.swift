//
//  HomeFoldersQuickStripView.swift
//  QuizFlash
//
//  Compact quick-access strip for Home folders.
//

import SwiftUI

// MARK: - Home Folders Quick Strip

/// Compact quick-access folder strip promoted near the top of Home on both iPhone and iPad.
struct HomeFoldersQuickStripView: View {
    let folders: [FolderModel]
    let allDeckCount: Int
    let visibleLimit: Int
    let chipWidth: CGFloat
    let promptWidth: CGFloat
    let onOpenFolder: (FolderModel) -> Void
    let onCreateFolder: () -> Void

    private var visibleFolders: [FolderModel] {
        Array(folders.prefix(visibleLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Folders")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: onCreateFolder) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: UIConstants.Size.actionIcon, weight: .semibold))
                        .foregroundStyle(ThemeManager.shared.accentColor.color)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
                        .glassButton(shape: .circle)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if folders.isEmpty {
                        HomeFoldersQuickStripPrompt(
                            allDeckCount: allDeckCount,
                            width: promptWidth,
                            onCreateFolder: onCreateFolder
                        )
                    } else {
                        ForEach(visibleFolders) { folder in
                            HomeFoldersQuickChip(folder: folder, width: chipWidth) {
                                onOpenFolder(folder)
                            }
                        }

                        if folders.count > visibleFolders.count {
                            HomeFoldersOverflowBadge(count: folders.count)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Quick Strip Chip

private struct HomeFoldersQuickChip: View {
    let folder: FolderModel
    let width: CGFloat
    let action: () -> Void

    private var folderColor: Color {
        Color(hex: folder.colorHex) ?? ThemeManager.shared.accentColor.color
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(folderColor.opacity(0.14))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(folderColor)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("\(folder.deckCount) deck\(folder.deckCount == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(folderColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: width, alignment: .leading)
            .glassButton(
                shape: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Strip Prompt

private struct HomeFoldersQuickStripPrompt: View {
    let allDeckCount: Int
    let width: CGFloat
    let onCreateFolder: () -> Void

    var body: some View {
        Button(action: onCreateFolder) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.orange.opacity(0.14))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.orange)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Create your first folder")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(allDeckCount == 0 ? "Keep Home ready for your first deck" : "Group your decks before the library grows")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: width, alignment: .leading)
            .glassButton(
                shape: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Overflow Badge

private struct HomeFoldersOverflowBadge: View {
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("All folders")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)

            Text("\(count) total")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassButton(
            shape: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

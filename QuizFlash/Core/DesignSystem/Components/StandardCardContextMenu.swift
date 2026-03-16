//
//  StandardCardContextMenu.swift
//  QuizFlash
//

import SwiftUI

struct StandardCardContextMenu: View {
    let title: String
    let summary: String
    let indicatorTint: Color
    let isPinned: Bool
    let onEdit: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    private var menuShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack(spacing: 8) {
                Circle()
                    .fill(indicatorTint)
                    .frame(width: 7, height: 7)

                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: UIConstants.Spacing.small)
            }

            Text(summary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()
                .background(Color.primary.opacity(0.08))

            VStack(alignment: .leading, spacing: 2) {
                StandardCardContextMenuActionRow(
                    title: "Edit Card",
                    icon: "pencil",
                    tint: .primary,
                    action: onEdit
                )

                StandardCardContextMenuActionRow(
                    title: isPinned ? "Unpin Card" : "Pin Card",
                    icon: isPinned ? "pin.slash" : "pin",
                    tint: isPinned ? .orange : indicatorTint,
                    action: onTogglePin
                )

                StandardCardContextMenuActionRow(
                    title: "Delete Card",
                    icon: "trash",
                    tint: .red,
                    isDestructive: true,
                    action: onDelete
                )
            }
        }
        .padding(12)
        .frame(width: UIConstants.Size.floatingContextMenuWidth, alignment: .leading)
        .widgetStyle(cornerRadius: 24)
        .clipShape(menuShape)
        .overlay {
            menuShape
                .stroke(Color.white.opacity(0.08), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.28), radius: 16, y: 10)
    }
}

private struct StandardCardContextMenuActionRow: View {
    let title: String
    let icon: String
    let tint: Color
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18, alignment: .center)

                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(isDestructive ? .red : .primary)
                    .lineLimit(1)

                Spacer(minLength: UIConstants.Spacing.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

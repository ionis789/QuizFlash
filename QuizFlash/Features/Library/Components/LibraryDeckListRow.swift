//
//  LibraryDeckListRow.swift
//  QuizFlash
//
//  Deck row presentation and local interaction for Library lists.
//

import SwiftUI
import UIKit
import CoreText

struct LibraryDeckListRow: View, Equatable {
    let deck: LibraryDeckRowSnapshot
    let isFirstInSection: Bool
    let isSelecting: Bool
    let isSelected: Bool
    let showActionMenu: Bool
    let onNavigate: () -> Void
    let onToggleSelection: () -> Void
    let onToggleActionMenu: (Bool) -> Void
    let onEditColor: () -> Void
    let onDelete: () -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    @State private var titleAvailableWidth: CGFloat = 0

    static func == (lhs: LibraryDeckListRow, rhs: LibraryDeckListRow) -> Bool {
        lhs.deck == rhs.deck &&
        lhs.isFirstInSection == rhs.isFirstInSection &&
        lhs.isSelecting == rhs.isSelecting &&
        lhs.isSelected == rhs.isSelected &&
        lhs.showActionMenu == rhs.showActionMenu
    }

    private var deckTint: Color {
        Color(hex: deck.colorHex) ?? ThemeManager.shared.accentColor.color
    }

    private var selectionAccent: Color {
        ThemeManager.shared.accentColor.color
    }

    private var timeAgoString: String {
        Self.relativeFormatter.localizedString(for: deck.editedAt, relativeTo: Date())
    }

    private var topContentPadding: CGFloat {
        isFirstInSection
            ? LibrarySectionHeaderMetrics.firstDeckTopPadding
            : LibrarySectionHeaderMetrics.regularDeckTopPadding
    }

    var body: some View {
        rowContent
            .contentShape(Rectangle())
            .onTapGesture {
                handlePrimaryTap()
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                guard !isSelecting else { return }
                withAnimation(.circularSelectionSpring) {
                    onToggleActionMenu(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isButton)
            .overlay(alignment: .bottom) {
                if showActionMenu {
                    DeckActionMenu(
                        onEditColor: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                onToggleActionMenu(false)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                onEditColor()
                            }
                        },
                        onDelete: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                onToggleActionMenu(false)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                onDelete()
                            }
                        },
                        onDismiss: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                onToggleActionMenu(false)
                            }
                        }
                    )
                    .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                    .zIndex(100)
                }
            }
            .background {
                if showActionMenu {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.circularSelectionSpring) {
                                onToggleActionMenu(false)
                            }
                        }
                        .ignoresSafeArea()
                        .zIndex(99)
                }
            }
    }

    private var rowContent: some View {
        rowMainLine
            .padding(.leading, 4)
            .padding(.trailing, 4)
            .padding(.top, topContentPadding)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                if isSelecting {
                    LibraryRowAccessory(
                        isSelecting: isSelecting,
                        isSelected: isSelected,
                        accent: selectionAccent
                    )
                    .offset(x: 10)
                }
            }
            .overlay(alignment: .bottom) {
                LibraryRowSeparator(
                    tint: isSelected ? selectionAccent : deckTint,
                    isHighlighted: isSelected
                )
                .padding(.top, 10)
            }
    }

    private var rowMainLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            LibraryDeckTitleLabel(
                title: deck.title,
                availableWidth: titleAvailableWidth
            )
                .layoutPriority(1)

            HStack(spacing: 12) {
                LibraryDeckMetaLabel(
                    systemImage: "rectangle.stack.fill",
                    text: "\(deck.cardCount) card\(deck.cardCount == 1 ? "" : "s")"
                )

                LibraryDeckMetaLabel(
                    systemImage: "clock",
                    text: timeAgoString
                )

                if let folderTitle = deck.folderTitle {
                    LibraryDeckMetaLabel(
                        systemImage: "folder",
                        text: folderTitle
                    )
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newWidth in
                    if abs(titleAvailableWidth - newWidth) > 0.5 {
                        titleAvailableWidth = newWidth
                    }
                }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func handlePrimaryTap() {
        if isSelecting {
            withAnimation(.circularSelectionSpring) {
                onToggleSelection()
            }
        } else {
            onNavigate()
        }
    }
}

private struct LibraryRowAccessory: View {
    private static let size: CGFloat = 24

    let isSelecting: Bool
    let isSelected: Bool
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1.6)
                .opacity(isSelecting && !isSelected ? 1 : 0)

            Circle()
                .fill(accent)
                .scaleEffect(isSelected ? 1 : 0.86)
                .opacity(isSelected ? 1 : 0)

            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(isSelected ? 1 : 0.92)
                .opacity(isSelected ? 1 : 0)
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Rectangle())
        .opacity(isSelecting ? 1 : 0)
        .animation(.easeInOut(duration: 0.16), value: isSelecting)
        .animation(.easeInOut(duration: 0.16), value: isSelected)
    }
}

struct LibraryDeckMetaLabel: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
    }
}

private struct LibraryDeckTitleLabel: View {
    let title: String
    let availableWidth: CGFloat

    var body: some View {
        Text(verbatim: renderedTitle)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(Color("DeckTitle"))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var renderedTitle: String {
        guard availableWidth > 0 else { return title }
        let normalizedTitle = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalizedTitle.isEmpty else { return title }

        let words = normalizedTitle.split(separator: " ").map(String.init)
        guard words.count > 1 else { return normalizedTitle }

        let greedyLineWidth = availableWidth + 4
        var firstLineWords: [String] = []

        for word in words {
            let candidateWords = firstLineWords + [word]
            let candidateLine = candidateWords.joined(separator: " ")
            if Self.lineWidth(for: candidateLine) <= greedyLineWidth {
                firstLineWords = candidateWords
            } else {
                break
            }
        }

        guard !firstLineWords.isEmpty, firstLineWords.count < words.count else {
            return normalizedTitle
        }

        let firstLine = firstLineWords.joined(separator: " ")
        let secondLine = words.dropFirst(firstLineWords.count).joined(separator: " ")

        guard Self.lineWidth(for: secondLine) <= greedyLineWidth else {
            return normalizedTitle
        }

        return "\(firstLine)\n\(secondLine)"
    }

    private static let titleFont: UIFont = {
        let fallback = UIFont.systemFont(ofSize: 22, weight: .bold)
        guard let descriptor = fallback.fontDescriptor.withDesign(.rounded) else {
            return fallback
        }
        return UIFont(descriptor: descriptor, size: 22)
    }()

    private static func lineWidth(for text: String) -> CGFloat {
        let attributedText = NSAttributedString(
            string: text,
            attributes: [.font: titleFont]
        )
        let line = CTLineCreateWithAttributedString(attributedText)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}

struct LibraryRowSeparator: View {
    let tint: Color
    var isHighlighted: Bool = false

    var body: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: tint.opacity(0.20), location: 0.0),
                        .init(color: Color.white.opacity(0.145), location: 0.18),
                        .init(color: Color.white.opacity(0.12), location: 0.42),
                        .init(color: Color.white.opacity(0.085), location: 0.68),
                        .init(color: Color.white.opacity(0.045), location: 0.88),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: tint.opacity(0.11), location: 0.0),
                                .init(color: Color.white.opacity(0.075), location: 0.45),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(maxWidth: 168)
                    .blur(radius: 1.6)
            }
            .overlay {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: tint.opacity(0.96), location: 0.0),
                                .init(color: tint.opacity(0.82), location: 0.58),
                                .init(color: tint.opacity(0.16), location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .scaleEffect(x: isHighlighted ? 1 : 0.18, y: 1, anchor: .leading)
                    .opacity(isHighlighted ? 1 : 0)
                    .blur(radius: isHighlighted ? 0.2 : 0)
                    .animation(.circularSelectionSpring, value: isHighlighted)
            }
            .frame(height: 2)
            .clipShape(Capsule(style: .continuous))
            .opacity(0.88)
            .animation(.circularSelectionSpring, value: isHighlighted)
    }
}

private struct DeckActionMenu: View {
    let onEditColor: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onEditColor) {
                Label("Change Color", systemImage: "paintpalette")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
            }

            Divider()
                .padding(.horizontal, 12)

            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .frame(width: 220)
        .offset(y: 8)
        .allowsHitTesting(true)
    }
}

//
//  LibraryDeckListRow.swift
//  QuizFlash
//
//  Deck row presentation and local interaction for Library lists.
//

import SwiftUI
import SwiftData

struct LibraryDeckListRow: View, Equatable {
    let deck: LibraryDeckRowSnapshot
    let isFirstInSection: Bool
    let isSelecting: Bool
    let isSelected: Bool
    let showsContextMenu: Bool
    let onNavigate: @MainActor @Sendable () -> Void
    let onToggleSelection: @MainActor @Sendable () -> Void
    let onExport: @MainActor @Sendable () -> Void
    let onMoveToFolder: @MainActor @Sendable () -> Void
    let onDelete: @MainActor @Sendable () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppPreferences.self) private var appPreferences

    init(
        deck: LibraryDeckRowSnapshot,
        isFirstInSection: Bool,
        isSelecting: Bool,
        isSelected: Bool,
        showsContextMenu: Bool = true,
        onNavigate: @escaping @MainActor @Sendable () -> Void,
        onToggleSelection: @escaping @MainActor @Sendable () -> Void,
        onExport: @escaping @MainActor @Sendable () -> Void,
        onMoveToFolder: @escaping @MainActor @Sendable () -> Void,
        onDelete: @escaping @MainActor @Sendable () -> Void
    ) {
        self.deck = deck
        self.isFirstInSection = isFirstInSection
        self.isSelecting = isSelecting
        self.isSelected = isSelected
        self.showsContextMenu = showsContextMenu
        self.onNavigate = onNavigate
        self.onToggleSelection = onToggleSelection
        self.onExport = onExport
        self.onMoveToFolder = onMoveToFolder
        self.onDelete = onDelete
    }

    static func == (lhs: LibraryDeckListRow, rhs: LibraryDeckListRow) -> Bool {
        lhs.deck == rhs.deck &&
        lhs.isFirstInSection == rhs.isFirstInSection &&
        lhs.isSelecting == rhs.isSelecting &&
        lhs.isSelected == rhs.isSelected &&
        lhs.showsContextMenu == rhs.showsContextMenu
    }

    private var topContentPadding: CGFloat {
        isFirstInSection
            ? LibrarySectionHeaderMetrics.firstDeckTopPadding
            : LibrarySectionHeaderMetrics.regularDeckTopPadding
    }

    private var selectionFillTint: Color {
        themeManager.roleColor(.buttonPrimaryFill)
    }

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private var localizedCardCount: String {
        AppLocalization.numbered(
            deck.cardCount,
            singular: "%d card",
            plural: "%d cards",
            locale: locale
        )
    }

    var body: some View {
        Group {
            if showsContextMenu {
                interactiveRowContent
                    .customContextMenu(
                        id: deck.id,
                        isEnabled: !isSelecting,
                        actions: contextMenuActions
                    ) {
                        rowContent
                    }
            } else {
                interactiveRowContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isButton)
    }

    private var contextMenuActions: [CustomContextMenuAction] {
        [
            CustomContextMenuAction(
                title: localized("Export"),
                systemImage: "square.and.arrow.up",
                role: .normal,
                action: { onExport() }
            ),
            CustomContextMenuAction(
                title: localized("Move to Folder"),
                systemImage: "folder",
                role: .normal,
                action: { onMoveToFolder() }
            ),
            CustomContextMenuAction(
                title: localized("Delete"),
                systemImage: "trash",
                role: .destructive,
                action: { onDelete() }
            )
        ]
    }

    private var rowContent: some View {
        rowMainLine
            .padding(.leading, 4)
            .padding(.trailing, 4)
            .padding(.top, topContentPadding)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                LibraryRowSelectionFill(
                    tint: selectionFillTint,
                    isActive: isSelected
                )
            }
            .overlay(alignment: .bottom) {
                AppSectionSeparator()
            }
    }

    private var interactiveRowContent: some View {
        rowContent
            .contentShape(Rectangle())
            .onTapGesture {
                handlePrimaryTap()
            }
    }

    private var rowMainLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            LibraryDeckTitleLabel(title: deck.title)
                .layoutPriority(1)

            LibraryDeckCardMetaLine(
                cardCountText: localizedCardCount,
                showsFlashcards: deck.hasFlashcards,
                showsQuizCards: deck.hasQuizCards
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func handlePrimaryTap() {
        if isSelecting {
            onToggleSelection()
        } else {
            onNavigate()
        }
    }
}

private struct LibraryRowSelectionFill: View {
    let tint: Color
    let isActive: Bool

    private let activeBottomOpacity: CGFloat = 0.24
    private let activeMidOpacity: CGFloat = 0.16
    private let activeTopOpacity: CGFloat = 0.04

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: tint.opacity(activeBottomOpacity), location: 0),
                .init(color: tint.opacity(activeBottomOpacity), location: 0.08),
                .init(color: tint.opacity(activeMidOpacity), location: 0.34),
                .init(color: tint.opacity(activeTopOpacity), location: 0.72),
                .init(color: tint.opacity(0), location: 1)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .padding(.bottom, LibraryRowSelectionMetrics.fillBaselineInset)
        .scaleEffect(x: 1, y: isActive ? 1 : 0.001, anchor: .bottom)
        .opacity(isActive ? 1 : 0)
        .clipped()
        .allowsHitTesting(false)
        .animation(.circularSelectionSpring, value: isActive)
    }
}

private enum LibraryRowSelectionMetrics {
    static let fillBaselineInset: CGFloat = 1
}

private struct LibraryContextMenuTitlePreview: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(themeManager.textPrimary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 320, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.clear)
    }
}

struct LibraryDeckMetaLabel: View {
    @Environment(ThemeManager.self) private var themeManager

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
        .foregroundStyle(themeManager.textSecondary)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct LibraryDeckTitleLabel: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(themeManager.textPrimary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LibraryDeckCardMetaLine: View {
    @Environment(ThemeManager.self) private var themeManager

    let cardCountText: String
    let showsFlashcards: Bool
    let showsQuizCards: Bool

    var body: some View {
        HStack(spacing: 6) {
            if showsFlashcards {
                Image(systemName: "rectangle.stack.fill")
            }

            if showsQuizCards {
                Image(systemName: "questionmark.square.dashed")
            }

            Text(cardCountText)
                .lineLimit(1)
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(themeManager.textSecondary)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}

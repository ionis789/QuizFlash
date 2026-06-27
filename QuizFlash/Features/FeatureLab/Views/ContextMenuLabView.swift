//
//  ContextMenuLabView.swift
//  QuizFlash
//
//  Isolated surface for experimenting with the custom context menu.
//

import SwiftUI

struct ContextMenuLabView: View {
    private let runtime = FeatureLabFixtures.shared

    @State private var lastActionSummary = "Long press a surface"

    private var surfaces: [ContextMenuLabSurface] {
        ContextMenuLabSurface.makeFixtures(runtime: runtime)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                LargeScreenTitle(title: "Context Menu Lab")

                ContextMenuLabInfoCard(
                    text: "Use these real QuizFlash surfaces to validate haptics, logs, tab bar handoff, preview alignment, and edge handling while the shared CustomContextMenu is active."
                )

                ContextMenuLabStatusCard(summary: lastActionSummary)

                ForEach(Array(surfaces.enumerated()), id: \.element.id) { index, surface in
                    if index == 3 {
                        spacerBlock(height: 140)
                    } else if index == 6 {
                        spacerBlock(height: 220)
                    }

                    ContextMenuLabSection(surface: surface) { actionTitle in
                        lastActionSummary = "\(surface.title) • \(actionTitle)"
                    }
                }
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.large)
            .padding(.bottom, UIConstants.Size.bottomChromeBarHeight + 120)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Context Menu Lab")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func spacerBlock(height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
    }
}

private struct ContextMenuLabActionDescriptor {
    let title: String
    let systemImage: String
    let role: CustomContextMenuActionRole
}

private struct ContextMenuLabSurface: Identifiable {
    enum Payload {
        case libraryDeckRow(LibraryDeckRowSnapshot)
        case deckGrid([DeckCardGridView.CardSection])
        case recentDeck(DeckModel)
        case folder(FolderModel)
        case draftCard(DraftCard)
        case settingsHeader(
            icon: String,
            tint: Color,
            title: SettingsTextContent,
            subtitle: SettingsTextContent,
            badges: [SettingsTextContent]
        )
        case settingsRow(
            icon: String,
            tint: Color,
            title: SettingsTextContent,
            detail: SettingsTextContent?,
            value: String?
        )
    }

    let id: String
    let title: String
    let subtitle: String
    let payload: Payload
    let actions: [ContextMenuLabActionDescriptor]

    var usesEmbeddedContextMenu: Bool {
        switch payload {
        case .libraryDeckRow, .deckGrid:
            true
        default:
            false
        }
    }

    static func makeFixtures(runtime: FeatureLabFixtures.Runtime) -> [ContextMenuLabSurface] {
        return [
            .init(
                id: "library-row",
                title: "LibraryDeckListRow",
                subtitle: "Actual Library row using the shared custom context menu.",
                payload: .libraryDeckRow(runtime.libraryDeckRow),
                actions: []
            ),
            .init(
                id: "deck-grid",
                title: "DeckView cards",
                subtitle: "Actual grid cards from DeckView using the shared custom context menu.",
                payload: .deckGrid(runtime.deckGridSections),
                actions: []
            ),
            .init(
                id: "recent-deck",
                title: "Home recent deck card",
                subtitle: "Compact ticket surface from Home for top-area menu anchoring.",
                payload: .recentDeck(runtime.recentDeck),
                actions: [
                    .init(title: "Open Deck", systemImage: "chevron.compact.right", role: .normal),
                    .init(title: "Move to Folder", systemImage: "folder", role: .normal),
                    .init(title: "Delete", systemImage: "trash", role: .destructive),
                ]
            ),
            .init(
                id: "settings-header",
                title: "Settings header card",
                subtitle: "Large rounded chrome from Settings with multiple badge widths.",
                payload: .settingsHeader(
                    icon: "brain.head.profile",
                    tint: .cyan,
                    title: "Study Defaults",
                    subtitle: "Stress-test wide previews with a taller settings card.",
                    badges: ["Review", "Focus", "Daily Goal"]
                ),
                actions: [
                    .init(title: "Open Settings", systemImage: "gearshape", role: .normal),
                    .init(title: "Pin Section", systemImage: "pin", role: .normal),
                    .init(title: "Reset", systemImage: "arrow.counterclockwise", role: .destructive),
                ]
            ),
            .init(
                id: "folder-card",
                title: "Home folder card",
                subtitle: "Folder object with native card depth and a shorter tap target.",
                payload: .folder(runtime.folder),
                actions: [
                    .init(title: "Open Folder", systemImage: "folder", role: .normal),
                    .init(title: "Rename", systemImage: "pencil", role: .normal),
                    .init(title: "Delete Folder", systemImage: "trash", role: .destructive),
                ]
            ),
            .init(
                id: "editor-card",
                title: "Deck editor draft card",
                subtitle: "Rich authoring preview with stacked content, chips, and text density.",
                payload: .draftCard(runtime.draftCard),
                actions: [
                    .init(title: "Edit", systemImage: "pencil", role: .normal),
                    .init(title: "Duplicate", systemImage: "plus.square.on.square", role: .normal),
                    .init(title: "Delete", systemImage: "trash", role: .destructive),
                ]
            ),
            .init(
                id: "settings-row",
                title: "Settings navigation row",
                subtitle: "Bottom-edge validation with a slimmer row surface inside settings chrome.",
                payload: .settingsRow(
                    icon: "paintpalette.fill",
                    tint: .pink,
                    title: "Accent Color",
                    detail: "Preview how a slimmer row behaves close to the bottom reserved space.",
                    value: "Sunset"
                ),
                actions: [
                    .init(title: "Open", systemImage: "chevron.compact.right", role: .normal),
                    .init(title: "Apply Default", systemImage: "wand.and.stars", role: .normal),
                    .init(title: "Reset Preference", systemImage: "arrow.counterclockwise", role: .destructive),
                ]
            ),
        ]
    }
}

private struct ContextMenuLabSection: View {
    let surface: ContextMenuLabSurface
    let onAction: (String) -> Void

    private var menuActions: [CustomContextMenuAction] {
        surface.actions.map { descriptor in
            CustomContextMenuAction(
                title: descriptor.title,
                systemImage: descriptor.systemImage,
                role: descriptor.role
            ) {
                onAction(descriptor.title)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            VStack(alignment: .leading, spacing: 6) {
                Text(surface.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)

                Text(surface.subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if surface.usesEmbeddedContextMenu {
                previewBody
            } else {
                previewBody
                    .customContextMenu(id: surface.id, actions: menuActions) {
                        previewBody
                    }
            }
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        switch surface.payload {
        case .libraryDeckRow(let deck):
            LibraryDeckListRow(
                deck: deck,
                isFirstInSection: true,
                isSelecting: false,
                isSelected: false,
                onNavigate: { onAction("Open Deck") },
                onToggleSelection: { onAction("Toggle Selection") },
                onExport: { onAction("Export") },
                onMoveToFolder: { onAction("Move to Folder") },
                onDelete: { onAction("Delete") }
            )
            .padding(UIConstants.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        case .deckGrid(let sections):
            DeckCardGridView(
                cards: sections,
                isSelecting: false,
                selectedCards: [],
                isSuspended: false,
                onToggleSelection: { card in onAction("Toggle Selection #\(card.cardNumber)") },
                onTapCard: { card in onAction("Open Card #\(card.cardNumber)") },
                onEditCard: { card in onAction("Edit Card #\(card.cardNumber)") },
                onTogglePinned: { card in
                    onAction(card.isPinned ? "Unpin Card #\(card.cardNumber)" : "Pin Card #\(card.cardNumber)")
                },
                onDeleteCard: { card in onAction("Delete Card #\(card.cardNumber)") }
            )
        case .recentDeck(let deck):
            HomeRecentDeckCardView(deck: deck, usesRegularMetrics: false) {}
        case .folder(let folder):
            FolderCardView(folder: folder, usesRegularMetrics: false) {}
        case .draftCard(let card):
            DetailedCardRowView(card: card, index: card.cardNumber)
        case .settingsHeader(let icon, let tint, let title, let subtitle, let badges):
            SettingsHeaderCard(
                icon: icon,
                title: title,
                subtitle: subtitle,
                tint: tint,
                badges: badges
            )
        case .settingsRow(let icon, let tint, let title, let detail, let value):
            SettingsNavigationRow(
                icon: icon,
                tint: tint,
                title: title,
                detail: detail,
                value: value
            )
            .padding(UIConstants.Spacing.large)
            .settingsCardBackground(cornerRadius: UIConstants.Radius.large)
        }
    }
}

private struct ContextMenuLabInfoCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(UIConstants.Spacing.large)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.maximum, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
    }
}

private struct ContextMenuLabStatusCard: View {
    let summary: String

    var body: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("Last Interaction")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(summary)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(UIConstants.Spacing.large)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.Radius.maximum, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

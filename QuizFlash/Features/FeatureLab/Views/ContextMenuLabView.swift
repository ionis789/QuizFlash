//
//  ContextMenuLabView.swift
//  QuizFlash
//
//  Isolated surface for experimenting with the custom context menu.
//

import SwiftUI
import SwiftData

struct ContextMenuLabView: View {
    private let runtime = ContextMenuLabRuntime.shared

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
        .environment(\.modelContext, runtime.container.mainContext)
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
        case settingsHeader(icon: String, tint: Color, title: String, subtitle: String, badges: [String])
        case settingsRow(icon: String, tint: Color, title: String, detail: String?, value: String?)
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

    static func makeFixtures(runtime: ContextMenuLabRuntime.Runtime) -> [ContextMenuLabSurface] {
        let recentDeck = makeDeck(
            title: "Discrete Math Sprint",
            colorHex: "#FF6B4A",
            cardCount: 48,
            lastOpenedAt: .now.addingTimeInterval(-60 * 42)
        )

        let folder = FolderModel(title: "Semester Finals", colorHex: "#F5A623")
        folder.deckCount = 6

        let editorCard = DraftCard(
            cardNumber: 12,
            content: .quiz(
                QuizCardContent(
                    questionZone: .text("Which protocol upgrades an HTTP connection into a persistent full-duplex channel?"),
                    choices: [
                        QuizChoiceDraft(contentZone: .text("WebSocket"), isCorrect: true),
                        QuizChoiceDraft(contentZone: .text("SMTP"), isCorrect: false),
                        QuizChoiceDraft(contentZone: .text("FTP"), isCorrect: false)
                    ],
                    explanationZone: .text("WebSocket starts with HTTP and upgrades the same TCP connection for two-way messaging."),
                    allowsMultipleCorrect: false
                )
            ),
            isPinned: true,
            creationSource: .manual,
            createdAt: .now.addingTimeInterval(-60 * 60 * 26),
            editedAt: .now.addingTimeInterval(-60 * 13)
        )

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
                payload: .recentDeck(recentDeck),
                actions: [
                    .init(title: "Open Deck", systemImage: "arrow.up.right", role: .normal),
                    .init(title: "Move to Folder", systemImage: "folder", role: .normal),
                    .init(title: "Delete", systemImage: "trash", role: .destructive)
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
                    .init(title: "Reset", systemImage: "arrow.counterclockwise", role: .destructive)
                ]
            ),
            .init(
                id: "folder-card",
                title: "Home folder card",
                subtitle: "Folder object with native card depth and a shorter tap target.",
                payload: .folder(folder),
                actions: [
                    .init(title: "Open Folder", systemImage: "folder", role: .normal),
                    .init(title: "Rename", systemImage: "pencil", role: .normal),
                    .init(title: "Delete Folder", systemImage: "trash", role: .destructive)
                ]
            ),
            .init(
                id: "editor-card",
                title: "Deck editor draft card",
                subtitle: "Rich authoring preview with stacked content, chips, and text density.",
                payload: .draftCard(editorCard),
                actions: [
                    .init(title: "Edit", systemImage: "pencil", role: .normal),
                    .init(title: "Convert", systemImage: "arrow.triangle.2.circlepath", role: .normal),
                    .init(title: "Duplicate", systemImage: "plus.square.on.square", role: .normal),
                    .init(title: "Delete", systemImage: "trash", role: .destructive)
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
                    .init(title: "Open", systemImage: "chevron.right", role: .normal),
                    .init(title: "Apply Default", systemImage: "wand.and.stars", role: .normal),
                    .init(title: "Reset Preference", systemImage: "arrow.counterclockwise", role: .destructive)
                ]
            )
        ]
    }

    private static func makeDeck(
        title: String,
        colorHex: String,
        cardCount: Int,
        lastOpenedAt: Date?
    ) -> DeckModel {
        let deck = DeckModel(title: title, colorHex: colorHex)
        deck.cardCount = cardCount
        deck.lastOpenedAt = lastOpenedAt
        deck.editedAt = .now.addingTimeInterval(-60 * 18)
        return deck
    }
}

private enum ContextMenuLabRuntime {
    struct Runtime {
        let container: ModelContainer
        let libraryDeckRow: LibraryDeckRowSnapshot
        let deckGridSections: [DeckCardGridView.CardSection]
    }

    static let shared: Runtime = {
        do {
            let schema = Schema([
                FolderModel.self,
                DeckModel.self,
                CardModel.self,
                ReviewEvent.self,
                UserProfile.self,
                DailyActivityLog.self,
                ExamGoalModel.self,
                DeckPlayModeSettingsModel.self
            ])
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = container.mainContext

            let libraryDeck = DeckModel(title: "Operating Systems Crash Course", colorHex: "#FF6B4A")
            libraryDeck.cardCount = 32
            libraryDeck.lastOpenedAt = .now.addingTimeInterval(-60 * 35)
            libraryDeck.editedAt = .now.addingTimeInterval(-60 * 11)
            context.insert(libraryDeck)

            let deckGridDeck = DeckModel(title: "API Design Interviews", colorHex: "#0EA5E9")
            deckGridDeck.cardCount = 4
            deckGridDeck.lastOpenedAt = .now.addingTimeInterval(-60 * 90)
            deckGridDeck.editedAt = .now.addingTimeInterval(-60 * 7)
            context.insert(deckGridDeck)

            let flashcard = CardModel(
                frontZone: .text("Define idempotency in REST APIs."),
                backZone: .text("The same repeated request leaves server state unchanged after the first success."),
                cardNumber: 1,
                isPinned: true,
                creationSource: .manual
            )
            flashcard.deck = deckGridDeck
            flashcard.interval = 21
            flashcard.consecutiveCorrectAnswers = 4

            let quizCard = CardModel(
                content: .quiz(
                    QuizCardContent(
                        questionZone: .text("Which data structure usually provides O(1) average lookup?"),
                        choices: [
                            QuizChoiceDraft(contentZone: .text("Hash table"), isCorrect: true),
                            QuizChoiceDraft(contentZone: .text("Linked list"), isCorrect: false),
                            QuizChoiceDraft(contentZone: .text("Binary heap"), isCorrect: false)
                        ],
                        explanationZone: .text("Hashing trades ordered traversal for very fast direct access on average."),
                        allowsMultipleCorrect: false
                    )
                ),
                cardNumber: 2,
                isPinned: false,
                creationSource: .ai
            )
            quizCard.deck = deckGridDeck
            quizCard.interval = 3
            quizCard.consecutiveCorrectAnswers = 1

            let writeSource = ZoneModel.text("HTTP status 429 means too many ____.")
            let writeCard = CardModel(
                content: .write(
                    WriteCardContent(
                        sourceZone: writeSource,
                        blankSelection: .init(
                            zoneID: writeSource.id,
                            utf16Range: 27..<35,
                            omittedText: "requests"
                        )
                    )
                ),
                cardNumber: 3,
                isPinned: false,
                creationSource: .manual
            )
            writeCard.deck = deckGridDeck
            writeCard.interval = 0

            let matchCard = CardModel(
                content: .match(
                    MatchCardContent(
                        prompt: "TCP handshake",
                        answer: "SYN, SYN-ACK, ACK"
                    )
                ),
                cardNumber: 4,
                isPinned: false,
                creationSource: .manual
            )
            matchCard.deck = deckGridDeck
            matchCard.interval = 8
            matchCard.consecutiveCorrectAnswers = 2

            for card in [flashcard, quizCard, writeCard, matchCard] {
                context.insert(card)
            }

            try context.save()

            let libraryDeckRow = LibraryDeckRowSnapshot(
                id: libraryDeck.persistentModelID,
                title: libraryDeck.title,
                colorHex: libraryDeck.colorHex,
                createdAt: libraryDeck.createdAt,
                editedAt: libraryDeck.editedAt,
                lastOpenedAt: libraryDeck.lastOpenedAt,
                cardCount: libraryDeck.cardCount,
                folderTitle: nil
            )

            let pinnedCard = makeGridCardInfo(flashcard, reviewHistoryIsEmpty: false)
            let gridCards = [
                makeGridCardInfo(quizCard, reviewHistoryIsEmpty: false),
                makeGridCardInfo(writeCard, reviewHistoryIsEmpty: true),
                makeGridCardInfo(matchCard, reviewHistoryIsEmpty: false)
            ]

            let deckGridSections = [
                DeckCardGridView.CardSection(
                    id: "pinned",
                    title: "Pinned",
                    cards: [pinnedCard]
                ),
                DeckCardGridView.CardSection(
                    id: "recent",
                    title: "Recent",
                    cards: gridCards
                )
            ]

            return Runtime(
                container: container,
                libraryDeckRow: libraryDeckRow,
                deckGridSections: deckGridSections
            )
        } catch {
            fatalError("Failed to create ContextMenuLab runtime: \(error)")
        }
    }()

    private static func makeGridCardInfo(
        _ card: CardModel,
        reviewHistoryIsEmpty: Bool
    ) -> GridCardInfo {
        GridCardInfo(
            id: card.persistentModelID,
            kind: card.kind,
            creationSource: card.creationSource,
            conversionMetadata: card.conversionMetadata,
            cardNumber: card.cardNumber,
            interval: card.interval,
            reviewHistoryIsEmpty: reviewHistoryIsEmpty,
            isPinned: card.isPinned,
            frontText: card.frontText,
            backText: card.backText,
            frontPreviewText: card.frontText,
            backPreviewText: card.backText,
            searchDocumentText: "\(card.frontText) \(card.backText)",
            createdAt: card.createdAt,
            editedAt: card.editedAt
        )
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
                    .font(.system(size: 20, weight: .bold, design: .rounded))
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
                onImport: { onAction("Import") },
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
                onConvertCard: { card in onAction("Convert Card #\(card.cardNumber)") },
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

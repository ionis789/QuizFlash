//
//  DeckView.swift
//  QuizFlash
//
//  Deck detail screen showing the card grid, stats, and play-mode entry points.
//  Business logic is fully delegated to `DeckViewModel`.
//
//  ## iOS 17 Retain Cycle Wrapper
//  `DeckView` is a thin wrapper that lazily creates `DeckViewModel` on appear,
//  preventing the retain cycle that arises when a `@Observable` ViewModel is
//  strongly captured by its own SwiftUI View during `NavigationStack` push.
//  The actual UI lives in `DeckContentView`.

import SwiftUI
import SwiftData
import UIKit
import OSLog

let kDeckScrollSpace = "DeckViewScrollSpace"
let kDeckChromeSpace = "DeckViewChromeSpace"

struct DeckContentView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuizFlash",
        category: "DeckContentView"
    )

    @Environment(\.modelContext) var context
    @Environment(NavigationManager.self) var router
    @Environment(AIWorkspaceCoordinator.self) var aiWorkspaceCoordinator
    @Environment(AppPreferences.self) var appPreferences
    @Environment(\.dismiss) var dismiss
    @Environment(ThemeManager.self) var themeManager
    @Bindable var deck: DeckModel
    let searchQuery: String?
    let ownerTab: AppTabBar

    // The back-button label frozen at push time via DeckNavigationValue.
    // Never read from router state — immune to cross-tab mutation.
    let backLabel: String

    @State var selectedPlayMode: DeckPlayModeDestination? = nil
    @State var selectedPlayModeSettings: DeckPlayModeDestination? = nil
    @State var previewedCard: CardModel? = nil
    @State var cardEditorDestination: CardEditorDestination? = nil
    @State var unavailablePlayMode: DeckPlayModeDestination? = nil
    @State var showAddCardTypeDialog = false
    @State var pendingDeleteCardID: PersistentIdentifier? = nil
    @State var playModeRecentUsageSnapshot: [DeckPlayModeDestination: Date] = [:]
    @State var preparedFlashcardsPlayModeViewModel: FlashCardsPlayModeViewModel?
    @State var flashcardsPreparationTask: Task<Void, Never>?
    @State var presentsFlashcardsAfterPreparation = false
    @Bindable var viewModel: DeckViewModel
    @State var hasLoadedInitialSnapshot = false
    @State var navigationBarHeight: CGFloat =
        UIConstants.Layout.deckNavigationTopPadding
        + UIConstants.Size.capsuleHeight
        + UIConstants.Spacing.small
    @State var navigationBarBottomY: CGFloat = 0

    /// Scroll-driven progress — updated by DeckScrollMonitor via KVO, never by SwiftUI state.
    @State var scrollState = DeckScrollState()

    var isSuspended: Bool {
        router.activeTab != ownerTab
    }

    var tabBarVisibilityRule: TabBarVisibilityRule {
        if viewModel.isSelecting
            || cardEditorDestination != nil {
            return .hidden
        }
        return .implicit
    }

    /// Reserved top spacing that keeps the hero content below the floating chrome.
    var topContentInset: CGFloat {
        navigationBarHeight + UIConstants.Layout.deckHeroChromeClearance
    }

    /// Bottom scroll clearance reserved for floating chrome without creating a large dead zone.
    var bottomContentInset: CGFloat {
        let baseInset = UIConstants.Spacing.small
        guard viewModel.isSelecting else { return baseInset }
        return UIConstants.Size.selectionToolbarBarHeight
            + UIConstants.Layout.bottomChromeBottomPadding
            + UIConstants.Spacing.standard
    }

    func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: appPreferences.resolvedLocale)
    }

    func localizedFormat(_ value: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = AppLocalization.string(value, locale: appPreferences.resolvedLocale)
        return String(format: format, locale: appPreferences.resolvedLocale, arguments: arguments)
    }

    /// Formats deck creation date and card count for display under the deck title.
    var subtitleText: String {
        let count = deck.cardCount
        let formatter = DateFormatter()
        formatter.locale = appPreferences.resolvedLocale
        formatter.calendar = appPreferences.resolvedCalendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let cardCountText = AppLocalization.numbered(
            count,
            singular: "%d card",
            plural: "%d cards",
            locale: appPreferences.resolvedLocale
        )
        return "\(formatter.string(from: deck.createdAt))  •  \(cardCountText)"
    }

    // MARK: - Body

    var body: some View {
        deckContent
            /// Hides the native system navigation bar.
            /// This stabilizes `safeAreaInsets` and prevents layout invalidation during scroll physics (rubber-banding).
            .toolbar(.hidden, for: .navigationBar)
            .customTabBarVisibility(tabBarVisibilityRule)
            .onAppear {
                guard !hasLoadedInitialSnapshot, !isSuspended else { return }
                hasLoadedInitialSnapshot = true
                refreshPlayModeRecentUsageSnapshot()
                viewModel.configureGroupingMode(from: deck.cardGroupingMode)
                viewModel.requestSnapshotLoad(
                    deckID: deck.persistentModelID,
                    container: context.container
                )
                prepareFlashcardsPlayModeIfNeeded()
            }
            .onDisappear {
                guard selectedPlayMode == nil,
                      selectedPlayModeSettings == nil,
                      previewedCard == nil,
                      cardEditorDestination == nil else { return }
                viewModel.tearDown()
                cancelPreparedFlashcardsPlayMode()
                ImageCache.shared.clearCache()
            }
            .onChange(of: deck.cardCount) {
                guard !isSuspended else { return }
                resetPreparedFlashcardsPlayMode()
                viewModel.requestSnapshotLoad(
                    deckID: deck.persistentModelID,
                    container: context.container
                )
                prepareFlashcardsPlayModeIfNeeded()
            }
            .onChange(of: viewModel.sortOrder) {
                guard !isSuspended else { return }
                viewModel.requestSnapshotLoad(
                    deckID: deck.persistentModelID,
                    container: context.container
                )
            }
            .onChange(of: viewModel.searchQuery) {
                guard !isSuspended else { return }
                viewModel.requestSnapshotLoad(
                    deckID: deck.persistentModelID,
                    container: context.container
                )
            }
            .onChange(of: selectedPlayMode) { old, new in
                if let completedMode = old, new == nil {
                    if completedMode == .flashcards {
                        resetPreparedFlashcardsPlayMode()
                    }
                    recordCompletedPlayModeSession(completedMode)
                    deck.lastOpenedAt = Date()
                    do {
                        try context.save()
                    } catch {
                        Self.logger.error(
                            "Failed to persist completed play mode session for deck \(deck.title, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                        viewModel.presentMutationError(error)
                    }
                    guard !isSuspended else { return }
                    viewModel.requestSnapshotLoad(
                        deckID: deck.persistentModelID,
                        container: context.container
                    )
                    if completedMode == .flashcards {
                        prepareFlashcardsPlayModeIfNeeded()
                    }
                }
            }
            .onChange(of: isSuspended) { _, suspended in
                if suspended {
                    viewModel.suspendHeavyWork()
                    CardPreviewCache.shared.flush()
                } else {
                    viewModel.configureGroupingMode(from: deck.cardGroupingMode)
                    viewModel.requestSnapshotLoad(
                        deckID: deck.persistentModelID,
                        container: context.container
                    )
                }
            }
            .alert(
                localizedFormat(
                    viewModel.selectedCards.count == 1 ? "Delete %d card?" : "Delete %d cards?",
                    viewModel.selectedCards.count
                ),
                isPresented: $viewModel.showDeleteConfirmation
            ) {
                Button(localized("Cancel"), role: .cancel) { }
                Button(localized("Delete"), role: .destructive) {
                    withBottomChromeAnimation {
                        viewModel.deleteSelectedCards(from: deck, context: context)
                    }
                }
            } message: { Text(localized("This action cannot be undone.")) }
            .alert(
                localized("Delete this card?"),
                isPresented: Binding(
                    get: { pendingDeleteCardID != nil },
                    set: { if !$0 { pendingDeleteCardID = nil } }
                )
            ) {
                Button(localized("Cancel"), role: .cancel) {
                    pendingDeleteCardID = nil
                }
                Button(localized("Delete"), role: .destructive) {
                    guard let id = pendingDeleteCardID else { return }
                    pendingDeleteCardID = nil
                    viewModel.deleteCard(withID: id, from: deck, context: context)
                }
            } message: {
                Text(localized("This action cannot be undone."))
            }
            .sheet(isPresented: $viewModel.showShareSheet) {
                if let url = viewModel.exportedURL { ShareSheet(items: [url]) }
            }
            .alert(localized("Export Error"), isPresented: $viewModel.showExportError) {
                Button(localized("OK"), role: .cancel) { }
            } message: { Text(viewModel.exportErrorMessage) }
            .alert(localized("Save Error"), isPresented: $viewModel.showMutationError) {
                Button(localized("OK"), role: .cancel) { }
            } message: {
                Text(viewModel.mutationErrorMessage)
            }
            .confirmationDialog(localized("Choose Card Type"), isPresented: $showAddCardTypeDialog, titleVisibility: .visible) {
                Button(localized("Flashcard")) { presentCardEditor(for: .flashcard) }
                Button(localized("Quiz")) { presentCardEditor(for: .quiz) }
                Button(localized("Write")) { presentCardEditor(for: .write) }
                Button(localized("Cancel"), role: .cancel) { }
            } message: {
                Text(localized("Pick the type of card you want to add to this deck."))
            }
            .overlay { exportingOverlay }
    }
}

struct DeckView: View {
    @Environment(ThemeManager.self) private var themeManager

    let deck: DeckModel
    let searchQuery: String?
    let backLabel: String
    let ownerTab: AppTabBar

    @State private var viewModel: DeckViewModel? = nil

    init(deck: DeckModel, searchQuery: String? = nil, backLabel: String, ownerTab: AppTabBar) {
        self.deck = deck
        self.searchQuery = searchQuery
        self.backLabel = backLabel
        self.ownerTab = ownerTab
    }

    var body: some View {
        Group {
            if let vm = viewModel {
                DeckContentView(
                    deck: deck,
                    searchQuery: searchQuery,
                    ownerTab: ownerTab,
                    backLabel: backLabel,
                    viewModel: vm
                )
            } else {
                themeManager.groupedScreenBackground
                    .onAppear {
                        if self.viewModel == nil {
                            self.viewModel = DeckViewModel(searchQuery: searchQuery)
                        }
                    }
            }
        }
    }
}

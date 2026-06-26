//
//  DeckScreenOverlays.swift
//  QuizFlash
//
//  Extracted overlays, helper sheets, and local deck screen actions.
//

import SwiftUI
import SwiftData
extension DeckContentView {
    func handleEditCard(_ gridCard: GridCardInfo) {
        guard !viewModel.isSelecting else { return }
        if let model = context.model(for: gridCard.id) as? CardModel {
            presentCardEditor(for: model)
        }
    }

    func handleTogglePinned(_ gridCard: GridCardInfo) {
        viewModel.togglePinnedState(for: gridCard.id, in: deck, context: context)
    }

    func openPlayMode(_ mode: DeckPlayModeDestination) {
        dismissUnavailablePlayMode()
        guard mode == .flashcards else {
            selectedPlayMode = mode
            return
        }

        prepareFlashcardsPlayModeIfNeeded()
        selectedPlayMode = mode
    }

    func prepareFlashcardsPlayModeIfNeeded() {
        guard deck.cardCount > 0 else { return }
        if let viewModel = preparedFlashcardsPlayModeViewModel,
           viewModel.isSessionStarted,
           !viewModel.cards.isEmpty {
            return
        }
        guard flashcardsPreparationTask == nil else { return }

        var flashcardSettings = deck.playModeSettings?.flashcardSettings ?? FlashcardModeSettings()
        if deck.playModeSettings == nil {
            flashcardSettings.textSize = appPreferences.defaultTextSize
        }

        let sessionViewModel = preparedFlashcardsPlayModeViewModel ?? FlashCardsPlayModeViewModel(
            deck: deck,
            settings: flashcardSettings
        )
        preparedFlashcardsPlayModeViewModel = sessionViewModel

        flashcardsPreparationTask = Task { @MainActor in
            await sessionViewModel.startSession(container: context.container)
            flashcardsPreparationTask = nil
        }
    }

    func resetPreparedFlashcardsPlayMode() {
        flashcardsPreparationTask?.cancel()
        flashcardsPreparationTask = nil
        preparedFlashcardsPlayModeViewModel = nil
    }

    func cancelPreparedFlashcardsPlayMode() {
        flashcardsPreparationTask?.cancel()
        flashcardsPreparationTask = nil
        preparedFlashcardsPlayModeViewModel?.tearDown()
        preparedFlashcardsPlayModeViewModel = nil
    }

    func presentUnavailablePlayMode(_ mode: DeckPlayModeDestination) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            unavailablePlayMode = mode
        }
    }

    func dismissUnavailablePlayMode() {
        guard unavailablePlayMode != nil else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
            unavailablePlayMode = nil
        }
    }

    func recordCompletedPlayModeSession(_ mode: DeckPlayModeDestination) {
        let settings = DeckPlayModeSettingsStore.resolve(for: deck, in: context)
        settings.markRecentlyUsed(mode)
    }

    func refreshPlayModeRecentUsageSnapshot() {
        let settings = deck.playModeSettings
        playModeRecentUsageSnapshot = DeckPlayModeDestination.allCases.reduce(into: [:]) { result, mode in
            if let date = settings?.recentUsageDate(for: mode) {
                result[mode] = date
            }
        }
    }

    func handleDeleteCard(_ gridCard: GridCardInfo) {
        pendingDeleteCardID = gridCard.id
    }

    func exitSelectionModeForExternalAction() {
        guard viewModel.isSelecting else { return }
        withBottomChromeAnimation {
            viewModel.exitSelectionMode()
        }
    }

    func presentCardEditor(for kind: CardKind) {
        exitSelectionModeForExternalAction()
        showAddCardTypeDialog = false
        cardEditorDestination = .create(kind: kind)
    }

    func presentCardEditor(for card: CardModel) {
        guard !viewModel.isSelecting else {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.88)) {
                viewModel.toggleSelection(for: card.persistentModelID)
            }
            return
        }
        exitSelectionModeForExternalAction()
        cardEditorDestination = .edit(DraftCard.from(card))
    }

    func handleCardEditorSave(destination: CardEditorDestination, content: DraftCardContent) {
        switch destination {
        case .create, .createFromDraft:
            viewModel.addCard(content: content, to: deck, context: context)
        case .edit(let draftCard):
            guard let cardID = draftCard.originalCardID,
                  let card = context.model(for: cardID) as? CardModel else {
                cardEditorDestination = nil
                return
            }

            if card.cardContent != content {
                card.cardContent = content
                card.editedAt = Date()
                deck.editedAt = Date()
                CloudSyncCoordinator.shared.enqueueUpsert(for: deck, context: context)
                viewModel.requestSnapshotLoad(
                    deckID: deck.persistentModelID,
                    container: context.container
                )
            }
        }
    }

    @ViewBuilder
    var unavailablePlayModeOverlay: some View {
        if let unavailablePlayMode {
            let prompt = unavailablePlayMode.localizedUnavailablePrompt(
                locale: appPreferences.resolvedLocale,
                in: viewModel.playModeAvailability,
                deck: deck
            )

            ZStack(alignment: .bottom) {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissUnavailablePlayMode()
                    }
                    .transition(.opacity)

                PlayModeUnavailableCard(
                    mode: unavailablePlayMode,
                    prompt: prompt,
                    tintColor: unavailablePlayMode.tintColor(
                        deckColor: Color(hex: deck.colorHex) ?? themeManager.accentColor.color,
                        accentColor: themeManager.accentColor.color
                    ),
                    onDismiss: dismissUnavailablePlayMode
                )
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
                .padding(
                    .bottom,
                    UIConstants.Size.bottomChromeBarHeight
                        + UIConstants.Layout.bottomChromeBottomPadding
                        + UIConstants.Spacing.medium
                )
                .transition(
                    .opacity
                        .combined(with: .scale(scale: 0.94, anchor: .bottom))
                )
            }
            .zIndex(260)
        }
    }

    struct PlayModeUnavailableCard: View {
        let mode: DeckPlayModeDestination
        let prompt: PlayModeUnavailablePrompt
        let tintColor: Color
        let onDismiss: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tintColor.opacity(0.16))
                        .frame(width: 54, height: 54)
                        .overlay {
                            Image(systemName: mode.systemImage)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(tintColor)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(prompt.detail)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: UIConstants.Spacing.small) {
                    Button(AppLocalization.string("Not now", locale: AppPreferences.persistedResolvedLocale), action: onDismiss)
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .quizFlashButtonStyle(.surface)

                }
            }
            .padding(UIConstants.Spacing.large)
            .flashcardStyle(cornerRadius: 30, surfaceRole: .widget)
        }
    }

    struct DeckCardPreviewSheetView: View {
        let card: CardModel
        let flashcardSettings: FlashcardModeSettings
        let safeAreaInsets: UIEdgeInsets

        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        @State private var showStats = false
        @Namespace private var statsTransition

        private var isCompact: Bool { horizontalSizeClass == .compact }

        var body: some View {
            GeometryReader { geo in
                let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)
                let horizontalInset = isCompact
                    ? UIConstants.Layout.compactScreenEdgeInset
                    : UIConstants.Layout.screenEdgeInset
                let panelWidth = min(
                    max(280, geo.size.width * (UIConstants.isPad ? 0.34 : 0.7)),
                    UIConstants.isPad ? 420 : 336
                )

                ZStack {
                    CardPreviewModeView(
                        content: card.cardContent,
                        safeAreaInsets: safeAreaInsets,
                        showsLeadingAccessory: true,
                        leadingAccessory: AnyView(statsButton),
                        contentAlignment: flashcardSettings.contentAlignment,
                        textSize: flashcardSettings.textSize
                    )

                    if showStats {
                        Color.black.opacity(0.16)
                            .ignoresSafeArea()
                            .onTapGesture { closeStats() }
                        statsSurface(width: panelWidth)
                            .padding(.trailing, horizontalInset)
                            .padding(.bottom, resolvedSafeBottomInset + UIConstants.Spacing.large)
                    }
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showStats)
            }
        }

        private var statsButton: some View {
            Button {
                if showStats {
                    closeStats()
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        showStats = true
                    }
                }
            } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
                    .foregroundStyle(showStats ? .primary : .secondary)
            }
            .quizFlashButtonStyle(.surface, shape: .circle, size: 42)
        }

        @ViewBuilder
        private func statsSurface(width: CGFloat) -> some View {
            CardStatsView(card: card, onClose: closeStats)
                .frame(width: width)
                .matchedGeometryEffect(id: "preview.stats.surface", in: statsTransition, anchor: .bottomTrailing)
                .transition(.identity)
                .zIndex(2)
        }

        private func closeStats() {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                showStats = false
            }
        }
    }

    struct CardStatsView: View {
        @Environment(AppPreferences.self) private var appPreferences
        let card: CardModel
        let onClose: () -> Void

        var totalReviews: Int { card.reviewHistory.count }
        var correctReviews: Int { card.reviewHistory.filter { $0.difficultyRaw >= ReviewDifficulty.good.rawValue }.count }
        var accuracy: Int {
            guard totalReviews > 0 else { return 0 }
            return Int((Double(correctReviews) / Double(totalReviews)) * 100)
        }
        var totalXPEarned: Int { card.reviewHistory.reduce(0) { $0 + $1.xpAwarded } }
        private var locale: Locale { appPreferences.resolvedLocale }

        private func localized(_ value: String.LocalizationValue) -> String {
            AppLocalization.string(value, locale: locale)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 40, height: 4)
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: UIConstants.Spacing.standard) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localized("Spaced Repetition Stats"))
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(.primary)
                        Text(localized("Live card memory and schedule snapshot"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    ChromeSoftCircleSymbolButton(
                        systemName: "xmark",
                        accessibilityLabel: localized("Close spaced repetition stats"),
                        action: onClose
                    )
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                    spacing: 12
                ) {
                    StatMetricTile(icon: "arrow.2.squarepath", value: "\(totalReviews)", label: localized("Reviews"), color: .blue)
                    StatMetricTile(icon: "target", value: "\(accuracy)%", label: localized("Accuracy"), color: .green)
                    StatMetricTile(icon: "sparkles", value: "\(totalXPEarned)", label: "XP", color: .yellow)
                    StatMetricTile(icon: "brain.head.profile", value: String(format: "%.1f", card.easeFactor), label: localized("Ease"), color: .purple)
                    StatMetricTile(icon: "calendar.badge.clock", value: "\(card.interval)d", label: localized("Interval"), color: .orange)
                    StatMetricTile(icon: "clock", value: dateString(card.dueDate), label: localized("Due"), color: card.dueDate <= Date() ? .red : .primary)
                }
            }
            .padding(20)
            .flashcardStyle(cornerRadius: 30, surfaceRole: .widget)
        }

        private func dateString(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = appPreferences.resolvedCalendar
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
            return formatter.string(from: date)
        }
    }

    struct StatMetricTile: View {
        let icon: String
        let value: String
        let label: String
        var color: Color = .primary

        var body: some View {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                Text(value)
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .duoControlSurface(cornerRadius: 22, tint: color)
        }
    }
}

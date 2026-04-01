//
//  DeckScreenOverlays.swift
//  QuizFlash
//
//  Extracted overlays, helper sheets, and local deck screen actions.
//

import SwiftUI
import SwiftData
import UIKit

extension DeckContentView {
    func handleEditCard(_ gridCard: GridCardInfo) {
        dismissActiveActionMenu()
        if let model = context.model(for: gridCard.id) as? CardModel {
            presentCardEditor(for: model)
        }
    }

    func handleTogglePinned(_ gridCard: GridCardInfo) {
        dismissActiveActionMenu()
        viewModel.togglePinnedState(for: gridCard.id, in: deck, context: context)
    }

    func handleConvertCard(_ gridCard: GridCardInfo) {
        dismissActiveActionMenu()
        presentConversionConfiguration(
            viewModel.presentSingleCardConversion(for: gridCard.id, in: deck)
        )
    }

    func handlePreviewRecommendedConversion(
        for card: CardModel,
        targetKind: CardKind
    ) {
        previewedCard = nil
        presentConversionConfiguration(
            viewModel.presentSingleCardConversion(
                for: card.persistentModelID,
                in: deck,
                preferredTargetKind: targetKind
            )
        )
    }

    func openPlayMode(_ mode: DeckPlayModeDestination) {
        dismissUnavailablePlayMode()
        selectedPlayMode = mode
    }

    func presentUnavailablePlayMode(_ mode: DeckPlayModeDestination) {
        dismissActiveActionMenu()
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

    func convertUnavailablePlayMode(_ mode: DeckPlayModeDestination) {
        dismissUnavailablePlayMode()
        guard let targetKind = mode.unavailableConversionTargetKind else { return }
        presentConversionConfiguration(
            viewModel.presentDeckConversion(for: deck, preferredTargetKind: targetKind)
        )
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
        dismissActiveActionMenu()
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
                try? context.save()
                viewModel.requestSnapshotLoad(
                    deckID: deck.persistentModelID,
                    container: context.container
                )
            }
        }

        cardEditorDestination = nil
    }

    func presentDeckConversion() {
        dismissActiveActionMenu()
        exitSelectionModeForExternalAction()
        presentConversionConfiguration(
            viewModel.presentDeckConversion(for: deck)
        )
    }

    func presentSelectionConversion() {
        dismissActiveActionMenu()
        presentConversionConfiguration(
            viewModel.presentSelectionConversion(for: deck)
        )
    }

    @discardableResult
    func presentConversionConfiguration(
        _ request: DeckCardConversionRequest?
    ) -> Bool {
        guard let request else { return false }
        return aiWorkspaceCoordinator.seedConversion(
            request: request,
            sourceDeck: deck,
            ownerTab: ownerTab,
            backLabel: backLabel,
            showsConfiguration: true,
            activatesWorkspaceContext: false
        )
    }

    func startDeckSeededConversion() {
        exitSelectionModeForExternalAction()
        aiWorkspaceCoordinator.startConversion(context: context)
        Task { @MainActor in
            await Task.yield()
            router.showCreateDeckEditor(for: deck.persistentModelID)
        }
    }

    func presentActionMenu(for id: PersistentIdentifier) {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.9)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            activeActionMenuCardID = id
        }
    }

    func dismissActiveActionMenu() {
        guard activeActionMenuCardID != nil else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
            activeActionMenuCardID = nil
        }
    }

    @ViewBuilder
    func actionMenuOverlay(
        preferences: [PersistentIdentifier: Anchor<CGRect>]
    ) -> some View {
        GeometryReader { proxy in
            if let card = activeActionMenuCard,
               let anchor = preferences[card.id],
               !viewModel.isSelecting,
               !isSuspended {
                let rect = proxy[anchor]
                let menuWidth = DeckGridCardMetrics.headerMenuWidth
                let menuHeight = DeckGridCardMetrics.headerMenuHeight
                let floatingGap = DeckGridCardMetrics.headerMenuFloatingGap
                let horizontalClearance = DeckGridCardMetrics.headerMenuHorizontalClearance
                let topLimit = navigationBarBottomY + actionMenuTopClearance
                let bottomLimit = proxy.size.height - actionMenuBottomClearance
                let preferredX = rect.minX + DeckGridCardMetrics.sideInset
                let clampedX = min(
                    max(preferredX, horizontalClearance),
                    max(horizontalClearance, proxy.size.width - horizontalClearance - menuWidth)
                )
                let topY = rect.minY - menuHeight - floatingGap
                let bottomY = rect.maxY + floatingGap
                let topSpace = rect.minY - topLimit - floatingGap
                let bottomSpace = bottomLimit - rect.maxY - floatingGap
                let placement: ActionMenuPlacement =
                    (topSpace >= menuHeight || topSpace >= bottomSpace) ? .top : .bottom
                let clampedY = placement == .top
                    ? max(topLimit, topY)
                    : min(bottomY, max(topLimit, bottomLimit - menuHeight))
                let transitionAnchor = UnitPoint(
                    x: clampedX > preferredX ? 1 : 0,
                    y: placement == .top ? 1 : 0
                )

                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissActiveActionMenu()
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { _ in
                                dismissActiveActionMenu()
                            }
                    )
                    .zIndex(199)

                DeckGridHeaderActionMenu(
                    isPinned: card.isPinned,
                    accent: ThemeManager.shared.accentColor.color,
                    onTogglePinned: {
                        dismissActiveActionMenu()
                        handleTogglePinned(card)
                    },
                    onEdit: {
                        dismissActiveActionMenu()
                        handleEditCard(card)
                    },
                    onConvert: {
                        dismissActiveActionMenu()
                        handleConvertCard(card)
                    },
                    onDelete: {
                        dismissActiveActionMenu()
                        handleDeleteCard(card)
                    }
                )
                .offset(
                    x: clampedX,
                    y: clampedY
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(
                                with: .scale(
                                    scale: 0.84,
                                    anchor: transitionAnchor
                                )
                            ),
                        removal: .opacity
                            .combined(
                                with: .scale(
                                    scale: 0.94,
                                    anchor: transitionAnchor
                                )
                            )
                    )
                )
                .zIndex(200)
            }
        }
    }

    @ViewBuilder
    var unavailablePlayModeOverlay: some View {
        if let unavailablePlayMode {
            let prompt = unavailablePlayMode.unavailablePrompt(
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
                        deckColor: Color(hex: deck.colorHex) ?? ThemeManager.shared.accentColor.color,
                        accentColor: ThemeManager.shared.accentColor.color
                    ),
                    onConvert: prompt.actionTitle == nil
                        ? nil
                        : { convertUnavailablePlayMode(unavailablePlayMode) },
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

    enum ActionMenuPlacement {
        case top
        case bottom
    }

    struct PlayModeUnavailableCard: View {
        let mode: DeckPlayModeDestination
        let prompt: PlayModeUnavailablePrompt
        let tintColor: Color
        let onConvert: (() -> Void)?
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
                            .font(.system(size: 20, weight: .bold, design: .rounded))
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
                    Button("Not now", action: onDismiss)
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: UIConstants.Size.capsuleHeight)
                        .background(Color.white.opacity(0.05), in: Capsule())

                    if let onConvert, let actionTitle = prompt.actionTitle {
                        Button(actionTitle, action: onConvert)
                            .buttonStyle(.plain)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(tintColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: UIConstants.Size.capsuleHeight)
                            .background(tintColor.opacity(0.12), in: Capsule())
                    }
                }
            }
            .padding(UIConstants.Spacing.large)
            .widgetStyle(cornerRadius: 30)
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            }
        }
    }

    struct DeckCardPreviewSheetView: View {
        let card: CardModel
        let safeAreaInsets: UIEdgeInsets
        let onOpenRecommendedConversion: (CardKind) -> Void

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
                        onOpenRecommendedConversion: onOpenRecommendedConversion
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
            .buttonStyle(.plain)
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
        let card: CardModel
        let onClose: () -> Void

        var totalReviews: Int { card.reviewHistory.count }
        var correctReviews: Int { card.reviewHistory.filter { $0.difficultyRaw >= ReviewDifficulty.good.rawValue }.count }
        var accuracy: Int {
            guard totalReviews > 0 else { return 0 }
            return Int((Double(correctReviews) / Double(totalReviews)) * 100)
        }
        var totalXPEarned: Int { card.reviewHistory.reduce(0) { $0 + $1.xpAwarded } }
        private static let dueDateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
            return formatter
        }()

        var body: some View {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 40, height: 4)
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: UIConstants.Spacing.standard) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Spaced Repetition Stats")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Live card memory and schedule snapshot")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 42)
                            .glassButton(shape: .circle)
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                    spacing: 12
                ) {
                    StatMetricTile(icon: "arrow.2.squarepath", value: "\(totalReviews)", label: "Reviews", color: .blue)
                    StatMetricTile(icon: "target", value: "\(accuracy)%", label: "Accuracy", color: .green)
                    StatMetricTile(icon: "sparkles", value: "\(totalXPEarned)", label: "XP", color: .yellow)
                    StatMetricTile(icon: "brain.head.profile", value: String(format: "%.1f", card.easeFactor), label: "Ease", color: .purple)
                    StatMetricTile(icon: "calendar.badge.clock", value: "\(card.interval)d", label: "Interval", color: .orange)
                    StatMetricTile(icon: "clock", value: dateString(card.dueDate), label: "Due", color: card.dueDate <= Date() ? .red : .primary)
                }
            }
            .padding(20)
            .widgetStyle(cornerRadius: 30)
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        }

        private func dateString(_ date: Date) -> String {
            Self.dueDateFormatter.string(from: date)
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
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

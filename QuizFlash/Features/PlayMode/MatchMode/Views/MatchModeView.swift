//
//  MatchModeView.swift
//  QuizFlash
//
//  Preview-based prompt and answer matching runtime.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Match Mode View

/// Lazy wrapper that avoids initializing the heavy match view model in the full-screen cover path.
struct MatchModeView: View {
    @Environment(ThemeManager.self) private var themeManager

    let deck: DeckModel
    let safeAreaInsets: UIEdgeInsets
    let availability: PlayModeCardAvailability

    @State private var viewModel: MatchModeViewModel?

    var body: some View {
        Group {
            if let viewModel {
                MatchModeSessionView(
                    deck: deck,
                    safeAreaInsets: safeAreaInsets,
                    availability: availability,
                    viewModel: viewModel
                )
            } else {
                themeManager.screenBackground
                    .onAppear {
                        if viewModel == nil {
                            viewModel = MatchModeViewModel(
                                deck: deck,
                                settings: deck.playModeSettings?.matchSettings ?? MatchModeSettings()
                            )
                        }
                    }
            }
        }
    }
}

// MARK: - MatchModeSessionView

/// Real gameplay surface for the round-based match mode.
private struct MatchModeSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.fullScreenSheetDragProgress) private var fullScreenSheetDragProgress
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let deck: DeckModel
    let safeAreaInsets: UIEdgeInsets
    let availability: PlayModeCardAvailability

    @Bindable var viewModel: MatchModeViewModel

    @State private var headerHeight: CGFloat = 0
    @State private var mismatchHapticTask: Task<Void, Never>?
    @State private var editingMatchBatch: MatchRoundBatchEditorPayload?

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var chromeButtonSize: CGFloat { isCompact ? 54 : UIConstants.Size.actionButton }
    private var playSurfaceHorizontalPadding: CGFloat { isCompact ? 12 : 24 }
    private var headerBottomPadding: CGFloat { isCompact ? 10 : 14 }
    private var topBlurHeight: CGFloat { headerHeight + (isCompact ? 8 : 12) }
    private var topSheetCornerRadius: CGFloat {
        fullScreenSheetDragProgress > 0.001 ? 50 : 0
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let resolvedSafeTopInset = max(safeAreaInsets.top, geo.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)
            let preferredRoundSize = viewModel.settings.roundSize.rawValue
            let roundCapacity = min(preferredRoundSize, isCompact && !isLandscape ? 6 : 8)
            let boardTopInset = headerHeight + headerBottomPadding

            ZStack(alignment: .top) {
                if fullScreenSheetDismiss == nil {
                    CardPreviewModeBackground()
                        .ignoresSafeArea()
                }

                if viewModel.isComplete {
                    completionOverlay
                } else {
                    content(geo: geo, topContentInset: boardTopInset)
                        .padding(.horizontal, 0)
                        .padding(.bottom, max(resolvedSafeBottomInset, UIConstants.Spacing.large))

                    TopProgressiveBlurOverlay(
                        topHeight: topBlurHeight,
                        revealProgress: 1,
                        tintColor: .black,
                        configuration: ScreenTopProgressiveBlurConfiguration(
                            maxBlurRadius: 3.2,
                            fadeExtension: isCompact ? 20 : 28,
                            tintOpacityTop: 0.52,
                            tintOpacityMiddle: 0.18
                        ),
                        revealAnimation: nil
                    )
                    .zIndex(0.5)

                    header(
                        safeTopInset: resolvedSafeTopInset,
                        horizontalPadding: playSurfaceHorizontalPadding
                    )
                    .zIndex(1)
                }
            }
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: topSheetCornerRadius,
                        bottomLeading: 0,
                        bottomTrailing: 0,
                        topTrailing: topSheetCornerRadius
                    ),
                    style: .continuous
                )
            )
            .fullScreenSheetDragActivationHeight(editingMatchBatch == nil ? headerHeight : 0)
            .task(id: roundCapacity) {
                await viewModel.startSession(
                    container: context.container,
                    roundCapacity: roundCapacity
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenSheet(
            item: $editingMatchBatch,
            configuration: .sheet(
                heightMode: .fullScreen,
                dragActivationArea: .fixed(132),
                backgroundReceivesDragProgress: false,
                showsBackdropBlur: true,
                showsDefaultTopProgressiveBlur: true,
                hidesTabBar: true,
                coversTabBar: true
            )
        ) { payload, sheetSafeAreaInsets in
            MatchRoundBatchEditorView(
                payload: payload,
                safeAreaInsets: sheetSafeAreaInsets
            ) { items in
                handleMatchBatchSave(items)
            }
        } background: {
            themeManager.screenBackground
        }
        .onChange(of: viewModel.mismatchAnimationToken) { oldValue, newValue in
            guard newValue > oldValue else { return }
            mismatchHapticTask?.cancel()
            let preference = appPreferences.matchHapticsPreference
            let rhythm = viewModel.settings.feedbackIntensity
            mismatchHapticTask = Task {
                await MatchBoardHaptics.playMismatchSequence(
                    for: preference,
                    rhythm: rhythm
                )
            }
        }
        .onChange(of: viewModel.totalMatchedCount) { oldValue, newValue in
            guard newValue > oldValue else { return }
            MatchBoardHaptics.playCorrectMatch(for: appPreferences.matchHapticsPreference)
        }
        .onDisappear {
            guard editingMatchBatch == nil else { return }
            mismatchHapticTask?.cancel()
            viewModel.tearDown()
        }
    }

    private func header(safeTopInset: CGFloat, horizontalPadding: CGFloat) -> some View {
        MatchSessionHeader(
            deckTitle: viewModel.resolvedDeckTitle,
            roundLabel: viewModel.roundLabel,
            matchedCount: viewModel.totalMatchedCount,
            totalCount: max(viewModel.allPairs.count, 1),
            isRetryRound: viewModel.isRetryRound,
            safeTopInset: safeTopInset,
            horizontalPadding: horizontalPadding,
            buttonSize: chromeButtonSize,
            measuredHeight: $headerHeight
        ) {
            HStack(spacing: isCompact ? 10 : 12) {
                editButton
                dismissButton
            }
        }
    }

    @ViewBuilder
    private func content(geo: GeometryProxy, topContentInset: CGFloat) -> some View {
        switch viewModel.loadState {
        case .idle, .loading:
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            centeredStateCard(
                icon: "rectangle.stack.badge.minus",
                title: "Match Isn't Available",
                message: "This deck doesn't have usable pairs for Match right now."
            )
        case .invalid:
            centeredStateCard(
                icon: "text.badge.xmark",
                title: "Match Needs Cleaner Pairs",
                message: "This deck couldn't build clean prompt-and-answer pairs from the current content.",
                bullets: matchInvalidBullets
            )
        case .failed:
            centeredStateCard(
                icon: "exclamationmark.triangle.fill",
                title: "Match Unavailable",
                message: viewModel.errorMessage.isEmpty ? "The match session couldn't be prepared right now." : viewModel.errorMessage
            )
        case .ready:
            if viewModel.activeRound != nil {
                matchBoard(availableSize: geo.size, topContentInset: topContentInset)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func centeredStateCard(
        icon: String,
        title: String,
        message: String,
        bullets: [String] = []
    ) -> some View {
        VStack {
            Spacer(minLength: 0)
            PlayModeMessageCard(
                icon: icon,
                title: title,
                message: message,
                bullets: bullets
            )
            .frame(maxWidth: 520)
            Spacer(minLength: 0)
        }
    }

    private func matchBoard(availableSize: CGSize, topContentInset: CGFloat) -> some View {
        let boardSpacing = isCompact ? 3.0 : 6.0
        let tileMinHeight = viewModel.settings.contentDensity == .compact ? 86.0 : 100.0

        return GeometryReader { boardGeo in
            let laneHeight = max(0, boardGeo.size.height)

            ZStack {
                HStack(alignment: .top, spacing: boardSpacing) {
                    matchLane(height: laneHeight, topInset: topContentInset) {
                        ForEach(viewModel.remainingPromptPairs) { pair in
                            MatchTileButton(
                                content: pair.promptContent,
                                removalOffsetX: 18,
                                isSelected: viewModel.selectedPromptID == pair.id,
                                isConfirmed: viewModel.confirmingMatchID == pair.id,
                                isRemoving: viewModel.removingMatchID == pair.id,
                                isMismatch: viewModel.mismatchPromptID == pair.id,
                                mismatchToken: viewModel.mismatchAnimationToken,
                                density: viewModel.settings.contentDensity,
                                fontScale: appPreferences.matchCardFontScale,
                                minHeight: tileMinHeight,
                                action: { handlePromptTap(pair.id) }
                            )
                        }
                    }

                    Color.white.opacity(0.08)
                        .frame(width: 1)
                        .padding(.top, topContentInset + 4)
                        .padding(.bottom, 6)
                        .frame(maxHeight: .infinity, alignment: .top)

                    matchLane(height: laneHeight, topInset: topContentInset) {
                        ForEach(viewModel.remainingAnswerPairs) { pair in
                            MatchTileButton(
                                content: pair.answerContent,
                                removalOffsetX: -18,
                                isSelected: viewModel.selectedAnswerID == pair.id,
                                isConfirmed: viewModel.confirmingMatchID == pair.id,
                                isRemoving: viewModel.removingMatchID == pair.id,
                                isMismatch: viewModel.mismatchAnswerID == pair.id,
                                mismatchToken: viewModel.mismatchAnimationToken,
                                density: viewModel.settings.contentDensity,
                                fontScale: appPreferences.matchCardFontScale,
                                minHeight: tileMinHeight,
                                action: { handleAnswerTap(pair.id) }
                            )
                        }
                    }
                }
                .id(viewModel.boardTransitionID)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .overlay {
            if viewModel.activeRound == nil {
                centeredStateCard(
                    icon: "checkmark.circle.fill",
                    title: "Round Cleared",
                    message: "Preparing the next prompt."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.18), value: viewModel.boardTransitionID)
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: viewModel.totalMatchedCount)
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: viewModel.remainingPromptPairs.count)
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: viewModel.remainingAnswerPairs.count)
    }

    private func matchLane<Content: View>(
        height: CGFloat,
        topInset: CGFloat,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                content()
            }
            .padding(.top, topInset)
            .padding(.horizontal, isCompact ? 4 : 8)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: height, alignment: .top)
    }

    private var dismissButton: some View {
        Button(action: dismissSheet) {
            Image(systemName: "xmark")
                .font(.system(size: 22, weight: .bold))
                .fontDesign(.rounded)
                .foregroundStyle(.primary)
                .frame(width: chromeButtonSize, height: chromeButtonSize)
                .background(
                    ThemeManager.shared.roleColor(.circularToolbarFill),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
    }

    private var editButton: some View {
        Button(action: openCurrentCardEditor) {
            Image(systemName: "pencil")
                .font(.system(size: 20, weight: .bold))
                .fontDesign(.rounded)
                .foregroundStyle(ThemeManager.shared.accentColor.color)
                .frame(width: chromeButtonSize, height: chromeButtonSize)
                .background(
                    ThemeManager.shared.roleColor(.circularToolbarFill),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canEditVisibleRound)
        .opacity(viewModel.canEditVisibleRound ? 1 : 0.36)
        .accessibilityLabel(AppLocalization.string("Edit", locale: appPreferences.resolvedLocale))
    }

    private var completionOverlay: some View {
        PlayModeCompletionOverlay(
            headline: "Match Complete!",
            xpEarned: viewModel.sessionXP,
            stats: [
                PlayModeCompletionStat(title: "Pairs", value: "\(viewModel.totalMatchedCount)", icon: "link", color: .green),
                PlayModeCompletionStat(title: "Mismatches", value: "\(viewModel.totalMismatchCount)", icon: "xmark.circle.fill", color: .orange),
                PlayModeCompletionStat(title: "Perfect Rounds", value: "\(viewModel.perfectRounds)", icon: "sparkles", color: .yellow),
                PlayModeCompletionStat(title: "Skipped", value: "\(viewModel.diagnostics.skippedInvalidCount)", icon: "text.badge.xmark", color: .red),
                PlayModeCompletionStat(title: "Time", value: viewModel.formattedSessionDuration, icon: "timer", color: .blue)
            ],
            primaryActionTitle: "Continue",
            primaryAction: dismissSheet,
            secondaryActionTitle: nil,
            secondaryAction: nil
        )
    }

    private var matchInvalidBullets: [String] {
        var bullets = ["Both sides of a pair need short, readable preview text before Match can use them."]

        let reasonSummaries = viewModel.diagnostics.nonZeroReasonCounts.compactMap { reason, count in
            switch reason {
            case .missingPromptPreview:
                return "\(count) card\(count == 1 ? "" : "s") had no readable prompt preview."
            case .missingAnswerPreview:
                return "\(count) card\(count == 1 ? "" : "s") had no readable answer preview."
            default:
                return nil
            }
        }

        bullets.append(contentsOf: reasonSummaries)
        return bullets
    }

    private func dismissSheet() {
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            dismiss()
        }
    }

    private func openCurrentCardEditor() {
        let items = viewModel.editableRoundPairs.compactMap { pair -> MatchRoundBatchEditorItem? in
            guard let card = context.model(for: pair.id) as? CardModel else { return nil }
            return MatchRoundBatchEditorItem(card: card)
        }

        guard !items.isEmpty else { return }
        editingMatchBatch = MatchRoundBatchEditorPayload(
            deckTitle: viewModel.resolvedDeckTitle,
            roundLabel: viewModel.roundLabel,
            items: items
        )
    }

    private func handleMatchBatchSave(_ items: [MatchRoundBatchEditorItem]) {
        var changedIDs: [PersistentIdentifier] = []
        let editedAt = Date()

        for item in items {
            guard item.hasChanges,
                  let card = context.model(for: item.id) as? CardModel else { continue }

            let content = item.persistedContent(for: card)
            guard card.cardContent != content else { continue }

            card.cardContent = content
            card.editedAt = editedAt
            changedIDs.append(card.persistentModelID)
        }

        guard !changedIDs.isEmpty else { return }

        deck.editedAt = Date()
        try? context.save()

        Task {
            await viewModel.refreshPairSnapshots(for: changedIDs)
        }
    }

    private func handlePromptTap(_ id: PersistentIdentifier) {
        guard canInteractWithTile(id) else { return }
        MatchBoardHaptics.playCardTap(for: appPreferences.matchHapticsPreference)
        viewModel.selectPrompt(id)
    }

    private func handleAnswerTap(_ id: PersistentIdentifier) {
        guard canInteractWithTile(id) else { return }
        MatchBoardHaptics.playCardTap(for: appPreferences.matchHapticsPreference)
        viewModel.selectAnswer(id)
    }

    private func canInteractWithTile(_ id: PersistentIdentifier) -> Bool {
        viewModel.loadState == .ready &&
        !viewModel.isComplete &&
        !viewModel.matchedIDs.contains(id) &&
        viewModel.confirmingMatchID == nil &&
        viewModel.removingMatchID == nil &&
        viewModel.mismatchPromptID == nil &&
        viewModel.mismatchAnswerID == nil
    }
}

// MARK: - Match Round Batch Editor

private struct MatchRoundBatchEditorPayload: Identifiable {
    let id = UUID()
    let deckTitle: String
    let roundLabel: String
    let items: [MatchRoundBatchEditorItem]
}

private struct MatchRoundBatchEditorItem: Identifiable, Equatable {
    let id: PersistentIdentifier
    let cardNumber: Int
    let sourceKind: CardKind
    let originalPrompt: String
    let originalAnswer: String
    var prompt: String
    var answer: String

    init(card: CardModel) {
        let matchContent = Self.matchContent(from: card.cardContent)

        id = card.persistentModelID
        cardNumber = card.cardNumber
        sourceKind = card.kind
        originalPrompt = matchContent.prompt
        originalAnswer = matchContent.answer
        prompt = matchContent.prompt
        answer = matchContent.answer
    }

    var hasChanges: Bool {
        normalizedPrompt != originalPrompt || normalizedAnswer != originalAnswer
    }

    var canSave: Bool {
        !normalizedPrompt.isEmpty && !normalizedAnswer.isEmpty
    }

    var normalizedPrompt: String { Self.normalizedSingleLine(prompt) }
    var normalizedAnswer: String { Self.normalizedSingleLine(answer) }

    func persistedContent(for card: CardModel) -> DraftCardContent {
        let matchContent = MatchCardContent(
            prompt: normalizedPrompt,
            answer: normalizedAnswer
        )

        switch card.cardContent {
        case .flashcard(let content):
            return .flashcard(
                FlashcardCardContent(
                    frontZone: .text(matchContent.prompt),
                    backZone: .text(matchContent.answer),
                    frontType: content.frontType,
                    backType: content.backType
                )
            )
        case .match:
            return .match(matchContent)
        default:
            return .match(matchContent)
        }
    }

    private static func matchContent(from content: DraftCardContent) -> MatchCardContent {
        switch content {
        case .match(let matchContent):
            return matchContent
        case .flashcard(let flashcardContent):
            return MatchCardContent(
                prompt: editableText(from: flashcardContent.frontZone),
                answer: editableText(from: flashcardContent.backZone)
            )
        default:
            return content.matchCompatibilityContent
        }
    }

    private static func editableText(from zone: ZoneModel) -> String {
        if zone.isLeaf, zone.contentType == .text || zone.contentType == .code {
            return zone.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let preview = zone.previewText(maxLength: 800)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return preview == "Empty" ? "" : preview
    }

    private static func normalizedSingleLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MatchRoundBatchEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.fullScreenSheetTopChromeClearance) private var topChromeClearance
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppPreferences.self) private var appPreferences

    @State private var items: [MatchRoundBatchEditorItem]
    @FocusState private var focusedField: Field?

    private let payload: MatchRoundBatchEditorPayload
    private let safeAreaInsets: UIEdgeInsets
    private let onSave: ([MatchRoundBatchEditorItem]) -> Void

    private var locale: Locale { appPreferences.resolvedLocale }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var topPadding: CGFloat {
        max(
            safeAreaInsets.top + UIConstants.Layout.deckNavigationTopPadding,
            topChromeClearance
        )
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    init(
        payload: MatchRoundBatchEditorPayload,
        safeAreaInsets: UIEdgeInsets,
        onSave: @escaping ([MatchRoundBatchEditorItem]) -> Void
    ) {
        self.payload = payload
        self.safeAreaInsets = safeAreaInsets
        self.onSave = onSave
        _items = State(initialValue: payload.items)
    }

    private enum Field: Hashable {
        case prompt(PersistentIdentifier)
        case answer(PersistentIdentifier)
    }

    private var canSave: Bool {
        items.allSatisfy(\.canSave)
    }

    var body: some View {
        ZStack(alignment: .top) {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: UIConstants.Spacing.standard) {
                topChrome
                editorList
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let firstID = items.first?.id {
                focusedField = .prompt(firstID)
            }
        }
    }

    private var topChrome: some View {
        HStack(spacing: UIConstants.Spacing.standard) {
            chromeButton(systemName: "xmark", tint: .secondary, isEnabled: true) {
                close()
            }
            .accessibilityLabel(localized("Cancel"))

            VStack(spacing: 2) {
                Text(payload.deckTitle)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(payload.roundLabel)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity)

            chromeButton(systemName: "checkmark", tint: accent, isEnabled: canSave) {
                save()
            }
            .accessibilityLabel(localized("Save"))
        }
        .padding(.top, topPadding)
        .padding(.horizontal, UIConstants.Spacing.extraLarge)
    }

    private var editorList: some View {
        Group {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach($items) { $item in
                        editorCard(item: $item)
                    }
                }
                .padding(.horizontal, UIConstants.Spacing.large)
                .padding(.top, 2)
                .padding(.bottom, safeAreaInsets.bottom + UIConstants.Spacing.huge)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func chromeButton(
        systemName: String,
        tint: Color,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(isEnabled ? tint : Color.secondary.opacity(0.45))
                .frame(width: 54, height: 54)
                .background {
                    Circle()
                        .fill(chromeButtonBackground)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func editorCard(item: Binding<MatchRoundBatchEditorItem>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("#\(item.wrappedValue.cardNumber)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.12), in: Capsule())
            }

            editorSection(
                title   : localized("PROMPT"),
                text: item.prompt,
                field: .prompt(item.wrappedValue.id),
                placeholder: localized("Example: Capital of France")
            )

            Divider()
                .overlay(borderColor)
                .padding(.vertical, 1)

            editorSection(
                title: localized("ANSWER"),
                text: item.answer,
                field: .answer(item.wrappedValue.id),
                placeholder: localized("Example: Paris")
            )
        }
        .padding(.vertical, 10)
    }

    private func editorSection(
        title: String,
        text: Binding<String>,
        field: Field,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            TextEditor(text: text)
                .focused($focusedField, equals: field)
                .scrollContentBackground(.hidden)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(minHeight: editorHeight(for: text.wrappedValue), alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(editorBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(placeholder)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            focusedField == field ? accent.opacity(0.35) : borderColor,
                            lineWidth: 1
                        )
                }
        }
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.black, Color(white: 0.08)]
                : [Color(uiColor: .systemGroupedBackground), Color(uiColor: .secondarySystemGroupedBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var editorBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.035) : Color.black.opacity(0.035)
    }

    private var chromeButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.78)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
    }

    private func editorHeight(for text: String) -> CGFloat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitLines = max(1, trimmed.components(separatedBy: .newlines).count)
        let estimatedWrappedLines = max(1, Int(ceil(Double(trimmed.count) / 42.0)))
        let lineCount = max(explicitLines, estimatedWrappedLines)
        return min(max(CGFloat(lineCount) * 25 + 28, 74), 128)
    }

    private func close() {
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            dismiss()
        }
    }

    private func save() {
        guard canSave else { return }
        onSave(items)
        close()
    }
}

// MARK: - MatchTileButton

/// One prompt or answer tile inside the match board.
private struct MatchTileButton: View {
    @Environment(ThemeManager.self) private var themeManager

    @State private var shakeToken: CGFloat = 0

    let content: MatchPlayableSideContent
    let removalOffsetX: CGFloat
    let isSelected: Bool
    let isConfirmed: Bool
    let isRemoving: Bool
    let isMismatch: Bool
    let mismatchToken: Int
    let density: MatchContentDensity
    let fontScale: CGFloat
    let minHeight: CGFloat
    let action: () -> Void

    var body: some View {
        MatchMiniPreviewSurface(
            content: content,
            fontScale: fontScale
        )
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous)
                .fill(baseBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous)
                        .fill(stateOverlay)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
        .contentShape(RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous))
        .simultaneousGesture(
            TapGesture().onEnded {
                action()
            }
        )
        .modifier(
            MatchShakeEffect(animatableData: shakeToken)
        )
        .opacity(isRemoving ? 0 : 1)
        .shadow(
            color: (isConfirmed || isRemoving) ? accent.opacity(0.12) : .clear,
            radius: (isConfirmed || isRemoving) ? 8 : 0,
            y: (isConfirmed || isRemoving) ? 2 : 0
        )
        .animation(.easeInOut(duration: 0.16), value: isConfirmed)
        .animation(.easeInOut(duration: 0.2), value: isRemoving)
        .animation(.easeInOut(duration: 0.16), value: isSelected)
        .animation(.easeInOut(duration: 0.16), value: isMismatch)
        .onChange(of: mismatchToken) { _, _ in
            guard isMismatch else { return }
            withAnimation(.linear(duration: 0.14)) {
                shakeToken += 1
            }
        }
    }

    private var tileCornerRadius: CGFloat { 22 }
    private var accent: Color { themeManager.accentColor.color }
    private var danger: Color { themeManager.color(.dangerPrimary) }

    private var baseBackground: Color {
        themeManager.color(.surfacePrimary).opacity(0.96)
    }

    private var stateOverlay: Color {
        if isMismatch {
            return danger.opacity(0.08)
        }

        if isConfirmed || isRemoving {
            return accent.opacity(0.12)
        }

        if isSelected {
            return accent.opacity(0.10)
        }

        return .clear
    }

    private var borderColor: Color {
        if isMismatch {
            return danger.opacity(0.28)
        }

        if isConfirmed || isRemoving {
            return accent.opacity(0.44)
        }

        if isSelected {
            return accent.opacity(0.38)
        }

        return themeManager.textPrimary.opacity(0.08)
    }

    private var borderWidth: CGFloat {
        if isMismatch || isConfirmed || isRemoving || isSelected {
            return 1.25
        }

        return 1
    }
}

private struct MatchMiniPreviewSurface: View {
    let content: MatchPlayableSideContent
    let fontScale: CGFloat

    var body: some View {
        let zone = content.renderZone

        CardFaceView(zone: zone, fontScale: fontScale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct MatchSessionHeader<Trailing: View>: View {
    let deckTitle: String
    let roundLabel: String
    let matchedCount: Int
    let totalCount: Int
    let isRetryRound: Bool
    let safeTopInset: CGFloat
    let horizontalPadding: CGFloat
    let buttonSize: CGFloat
    @Binding var measuredHeight: CGFloat
    @ViewBuilder let trailing: () -> Trailing

    @State private var leadingWidth: CGFloat = 0
    @State private var trailingWidth: CGFloat = UIConstants.Size.actionButton

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                let titleSideReserve = max(leadingWidth, trailingWidth, buttonSize)

                titleBlock
                    .padding(.horizontal, titleSideReserve + UIConstants.Spacing.large)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 0) {
                    summaryCapsule
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.width
                        } action: { newWidth in
                            if abs(leadingWidth - newWidth) > 0.5 {
                                leadingWidth = newWidth
                            }
                        }
                    Spacer(minLength: 0)
                    trailing()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.width
                        } action: { newWidth in
                            if abs(trailingWidth - newWidth) > 0.5 {
                                trailingWidth = newWidth
                            }
                        }
                }
            }
            .frame(height: buttonSize)
        }
        .padding(.top, safeTopInset + UIConstants.Layout.deckNavigationTopPadding)
        .padding(.horizontal, max(horizontalPadding, UIConstants.Layout.compactScreenEdgeInset))
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            if abs(measuredHeight - newHeight) > 0.5 {
                measuredHeight = newHeight
            }
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 2) {
            Text(deckTitle)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(ThemeManager.shared.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)
                .multilineTextAlignment(.center)

            HStack(spacing: 7) {
                Text(roundLabel)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)

                if isRetryRound {
                    Text("RETRY")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.orange.opacity(0.95))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.14), in: Capsule())
                }
            }
        }
    }

    private var summaryCapsule: some View {
        HStack(spacing: 6) {
            Text("\(matchedCount)")
                .foregroundStyle(ThemeManager.shared.accentColor.color)
            Text("/")
                .foregroundStyle(ThemeManager.shared.textSecondary.opacity(0.62))
            Text("\(totalCount)")
                .foregroundStyle(ThemeManager.shared.textPrimary.opacity(0.88))
        }
        .font(.system(size: 14, weight: .black, design: .rounded))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(ThemeManager.shared.roleColor(.labelSurfaceFill).opacity(0.72), in: Capsule())
        .overlay {
            Capsule()
                .stroke(ThemeManager.shared.accentColor.color.opacity(0.16), lineWidth: 1)
        }
    }
}

// MARK: - MatchShakeEffect

/// Lightweight horizontal shake used when the player mismatches a prompt and answer.
private struct MatchShakeEffect: GeometryEffect {
    var travelDistance: CGFloat = 3.5
    var shakesPerUnit: CGFloat = 2
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = travelDistance * sin(animatableData * .pi * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

// MARK: - MatchBoardHaptics

/// Small UI-only haptic adapter for Match interactions.
@MainActor
private enum MatchBoardHaptics {
    static func playCardTap(for preference: AppStudyHapticsPreference) {
        switch preference {
        case .off:
            return
        case .subtle:
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        case .standard:
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.prepare()
            generator.impactOccurred(intensity: 0.7)
        }
    }

    static func playCorrectMatch(for preference: AppStudyHapticsPreference) {
        switch preference {
        case .off:
            return
        case .subtle:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred(intensity: 0.82)
        case .standard:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }
    }

    static func playMismatchSequence(
        for preference: AppStudyHapticsPreference,
        rhythm: MatchFeedbackIntensity
    ) async {
        guard preference != .off else { return }

        playMismatchPulseStart(for: preference)
    }

    private static func playMismatchPulseStart(for preference: AppStudyHapticsPreference) {
        switch preference {
        case .off:
            return
        case .subtle:
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.prepare()
            generator.impactOccurred(intensity: 0.42)
        case .standard:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred(intensity: 0.74)
        }
    }

}

//
//  QuizModeView.swift
//  QuizFlash
//
//  One-question-at-a-time multiple-choice gameplay runtime.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Quiz Mode View

/// Lazy wrapper that avoids initializing the quiz view model inside the full-screen cover path.
struct QuizModeView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let deck: DeckModel
    let safeAreaInsets: UIEdgeInsets
    let availability: PlayModeCardAvailability

    @State private var viewModel: QuizModeViewModel?

    var body: some View {
        Group {
            if let viewModel {
                QuizModeSessionView(
                    deck: deck,
                    safeAreaInsets: safeAreaInsets,
                    availability: availability,
                    viewModel: viewModel
                )
            } else {
                themeManager.screenBackground
                    .onAppear {
                        if viewModel == nil {
                            viewModel = QuizModeViewModel(
                                deck: deck,
                                settings: resolvedSettings
                            )
                        }
                    }
            }
        }
    }

    private var resolvedSettings: QuizModeSettings {
        var settings = deck.playModeSettings?.quizSettings ?? QuizModeSettings()
        if deck.playModeSettings == nil {
            settings.textSize = appPreferences.defaultTextSize
        }
        return settings
    }
}

// MARK: - QuizModeSessionView

/// Interactive quiz surface with authored choice order and an optional retry pass.
private struct QuizModeSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(DevelopmentPreferences.self) private var developmentPreferences

    let deck: DeckModel
    let safeAreaInsets: UIEdgeInsets
    let availability: PlayModeCardAvailability

    @Bindable var viewModel: QuizModeViewModel

    @State private var measuredChoiceZoneWidths: [UUID: CGFloat] = [:]
    @State private var questionLeafDebugSnapshots: [ZoneContentLeafLayoutDebugSnapshot] = []
    @State private var choiceLeafDebugSnapshots: [UUID: [ZoneContentLeafLayoutDebugSnapshot]] = [:]
    @State private var questionBlockDebugBounds: [ZoneContentRenderBlockBounds] = []
    @State private var choiceBlockDebugBounds: [UUID: [ZoneContentRenderBlockBounds]] = [:]
    @State private var explanationBlockDebugBounds: [ZoneContentRenderBlockBounds] = []
    @State private var showsQuizLayoutDebug = false
    @State private var showsExplanationSheet = false
    @State private var didCopyQuizLayoutDebug = false
    @State private var editingCard: CardModel?
    @State private var measuredExplanationSheetHeight: CGFloat = 0
    @State private var measuredFloatingControlsHeight: CGFloat = 0
    @State private var measuredQuizDebugControlsHeight: CGFloat = 0
    @State private var isQuestionContentVisible = false
    @State private var areFloatingControlsVisible = false
    @State private var isQuestionTransitioning = false
    @State private var questionTransitionTask: Task<Void, Never>?

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var tintColor: Color { Color(hex: deck.colorHex) ?? ThemeManager.shared.accentColor.color }
    private var contentHorizontalPadding: CGFloat { 8 }
    private var contentTopPadding: CGFloat { 12 }
    private var contentBottomPadding: CGFloat { 12 }
    private var minimumReservedFloatingControlsHeight: CGFloat { 48 }
    private var questionContentHiddenScale: CGFloat { 0.952 }
    private var questionContentTransition: Animation {
        .spring(response: 0.36, dampingFraction: 0.84)
    }
    private var playModeTextScale: CGFloat {
        CGFloat(viewModel.settings.textSize.playModeScale)
    }

    var body: some View {
        GeometryReader { geo in
            let resolvedSafeTopInset = max(safeAreaInsets.top, geo.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)
            let headerHorizontalPadding: CGFloat = isCompact ? 20 : 32

            ZStack {
                if fullScreenSheetDismiss == nil {
                    CardPreviewModeBackground()
                        .ignoresSafeArea()
                }

                if viewModel.isComplete {
                    completionOverlay
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                        .clipped()
                } else if viewModel.isShowingRetryPrompt {
                    retryCompletionOverlay
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                        .clipped()
                } else {
                    VStack(spacing: 0) {
                        header(
                            safeTopInset: resolvedSafeTopInset,
                            horizontalPadding: headerHorizontalPadding
                        )

                        content(safeBottomInset: resolvedSafeBottomInset)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                if !viewModel.isShowingRetryPrompt && !viewModel.isComplete {
                    quizFloatingControls()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            ceil(proxy.size.height)
                        } action: { newHeight in
                            updateMeasuredFloatingControlsHeight(newHeight)
                        }
                        .padding(.horizontal, contentHorizontalPadding)
                        .padding(.bottom, quizFloatingControlsBottomPadding(safeBottomInset: resolvedSafeBottomInset))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .zIndex(25)
                }

                if developmentPreferences.playModeDeveloperModeEnabled
                    && !viewModel.isShowingRetryPrompt
                    && !viewModel.isComplete {
                    quizLayoutDebugButton
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            ceil(proxy.size.height)
                        } action: { newHeight in
                            updateMeasuredQuizDebugControlsHeight(newHeight)
                        }
                        .padding(.trailing, contentHorizontalPadding)
                        .padding(.bottom, quizDebugBottomPadding(safeBottomInset: resolvedSafeBottomInset))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .zIndex(30)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .clipped()
            .keepsScreenAwake()
            .task {
                await viewModel.startSession(container: context.container)
                showQuestionContentIfReady()
            }
        }
        .fullScreenCover(item: $editingCard) { card in
            NavigationStack {
                CardEditorView(
                    destination: .edit(DraftCard.from(card)),
                    textSizeOverride: viewModel.settings.textSize
                ) { content in
                    saveEditedQuiz(card, content: content)
                    editingCard = nil
                }
            }
        }
        .fullScreenSheet(
            isPresented: $showsExplanationSheet,
            configuration: .sheet(
                heightMode: explanationSheetHeightMode,
                dragActivationArea: .fullSurface,
                showsDragIndicator: false,
                showsBackdropBlur: true,
                showsDefaultTopProgressiveBlur: false,
                showsCloseButton: false,
                hidesTabBar: true,
                coversTabBar: false
            )
        ) { safeArea in
            explanationSheetContent(safeAreaInsets: safeArea)
        } background: {
            QuizExplanationSheetBackground()
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: viewModel.currentCard?.id) { _, _ in
            showsExplanationSheet = false
            measuredExplanationSheetHeight = 0
        }
        .onChange(of: viewModel.loadState) { _, _ in
            showQuestionContentIfReady()
        }
        .onChange(of: viewModel.isComplete) { _, isComplete in
            if isComplete {
                showsExplanationSheet = false
            }
        }
        .onChange(of: viewModel.evaluationFeedbackTrigger) { _, trigger in
            guard trigger > 0, let result = viewModel.evaluationFeedbackWasCorrect else { return }
            emitQuizEvaluationHaptic(isCorrect: result)
        }
        .onDisappear {
            questionTransitionTask?.cancel()
            viewModel.tearDown()
        }
    }

    private func header(safeTopInset: CGFloat, horizontalPadding: CGFloat) -> some View {
        HStack(spacing: UIConstants.Spacing.standard) {
            editCurrentQuizButton

            quizProgressBar

            dismissButton
        }
        .padding(.top, safeTopInset + UIConstants.Spacing.tiny)
        .padding(.horizontal, horizontalPadding)
    }

    private var editCurrentQuizButton: some View {
        ChromeSoftCircleSymbolButton(
            systemName: "pencil",
            accessibilityLabel: "Edit current quiz",
            action: openCurrentQuizEditor,
            size: UIConstants.Size.actionButton,
            tint: ThemeManager.shared.accentColor.color
        )
        .disabled(viewModel.currentCard == nil)
        .opacity(viewModel.currentCard == nil ? 0.35 : 1)
    }

    private var quizProgressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                ThemeManager.shared.accentColor.color.opacity(0.82),
                                ThemeManager.shared.accentColor.color,
                                Color.white.opacity(0.92),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: max(
                            0,
                            min(
                                proxy.size.width,
                                proxy.size.width * max(0, min(viewModel.progressFraction, 1))
                            )
                        )
                    )
            }
        }
        .frame(height: 6)
    }

    private func openCurrentQuizEditor() {
        guard let currentCard = viewModel.currentCard,
              let cardModel = context.model(for: currentCard.id) as? CardModel,
              case .quiz = cardModel.cardContent else {
            return
        }

        showsExplanationSheet = false
        editingCard = cardModel
    }

    private func saveEditedQuiz(_ card: CardModel, content: DraftCardContent) {
        guard case .quiz = content else { return }

        card.cardContent = content
        card.editedAt = Date()
        deck.editedAt = Date()

        do {
            try context.save()
            CloudSyncCoordinator.shared.enqueueUpsert(for: deck, context: context)
            viewModel.refreshCurrentCard(from: card)
        } catch {
            context.rollback()
            assertionFailure("Failed to save edited quiz card: \(error.localizedDescription)")
        }
    }

    @ViewBuilder
    private func content(safeBottomInset: CGFloat) -> some View {
        switch viewModel.loadState {
        case .idle, .loading:
            preparingQuizIndicator
        case .empty:
            centeredMessageCard(
                icon: "questionmark.square.dashed",
                title: "No Quiz Cards Yet",
                message: "This deck needs quiz cards before Quiz mode can start."
            )
        case .invalid:
            centeredMessageCard(
                icon: "checklist.unchecked",
                title: "Quiz Cards Need More Structure",
                message: "Quiz mode found cards of the right type, but all of them failed runtime validation.",
                bullets: invalidBullets
            )
        case .failed:
            centeredMessageCard(
                icon: "exclamationmark.triangle.fill",
                title: "Quiz Unavailable",
                message: viewModel.errorMessage.isEmpty ? "The quiz session couldn't be prepared right now." : viewModel.errorMessage
            )
        case .ready:
            if let currentCard = viewModel.currentCard {
                questionFlow(for: currentCard, safeBottomInset: safeBottomInset)
                    .opacity(isQuestionContentVisible ? 1 : 0.001)
                    .scaleEffect(isQuestionContentVisible ? 1 : questionContentHiddenScale)
                    .animation(questionContentTransition, value: isQuestionContentVisible)
            } else {
                centeredMessageCard(
                    icon: "questionmark.circle",
                    title: "Waiting For Question Data",
                    message: "The next quiz question is being prepared."
                )
            }
        }
    }

    private var preparingQuizIndicator: some View {
        VStack {
            Spacer(minLength: 0)

            VStack(spacing: UIConstants.Spacing.large) {
                Image(systemName: "hourglass")
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .symbolRenderingMode(.hierarchical)

                ProgressActivityDots(color: Color.white.opacity(0.76))
            }
            .accessibilityLabel(
                AppLocalization.string("Preparing Quiz", locale: appPreferences.resolvedLocale)
            )

            Spacer(minLength: 0)
        }
    }

    private func questionFlow(for card: QuizPlayableCard, safeBottomInset: CGFloat) -> some View {
        GeometryReader { proxy in
            let screenWidth = max(proxy.size.width, 1)
            let screenHeight = max(proxy.size.height, 1)
            let contentWidth = max(screenWidth - (contentHorizontalPadding * 2), 1)
            let contentHeight = max(screenHeight - contentTopPadding - contentBottomPadding, 1)
            let questionViewportHeight = max(screenHeight * 0.30, 1)
            let answerGroupWidth = choiceGroupWidth(availableWidth: contentWidth)
            let answerBottomOverlayInset = quizAnswerBottomOverlayInset(safeBottomInset: safeBottomInset)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                    QuizQuestionScrollViewport(maxHeight: questionViewportHeight) {
                        QuizPlaybackZoneContent(
                            zone: card.questionZone,
                            fontScale: playModeTextScale,
                            availableWidth: contentWidth,
                            centersLeafBlocks: true,
                            alignLeafBlocksToGroupLeading: false,
                            showsZoneSurfaces: false,
                            textVerticalPadding: 0,
                            textHorizontalPaddingOverride: 0,
                            showsLayoutDebug: showsQuizLayoutDebug,
                            onLeafDebugSnapshotsChange: updateQuestionLeafDebugSnapshots,
                            onBlockBoundsChange: updateQuestionBlockDebugBounds
                        )
                    }

                    quizQuestionSeparator
                }
                .quizDebugOutline(
                    isVisible: showsQuizLayoutDebug,
                    color: .orange,
                    label: "QUESTION w=\(Self.metric(contentWidth)) screen=\(Self.metric(screenWidth)) padH=\(Self.metric(contentHorizontalPadding))"
                )

                QuizAnswerList(
                    choices: card.choices,
                    selectedChoiceIDs: viewModel.selectedChoiceIDs,
                    incorrectChoiceIDs: viewModel.incorrectChoiceIDs,
                    revealedMissedCorrectChoiceIDs: viewModel.revealedMissedCorrectChoiceIDs,
                    wrongFeedbackChoiceIDs: viewModel.wrongFeedbackChoiceIDs,
                    wrongFeedbackTrigger: viewModel.wrongFeedbackTrigger,
                    isEvaluated: viewModel.isEvaluated,
                    allowsSelection: allowsChoiceSelection,
                    fontScale: playModeTextScale,
                    groupWidth: answerGroupWidth,
                    layoutWidth: contentWidth,
                    topContentInset: UIConstants.Spacing.large,
                    bottomOverlayInset: answerBottomOverlayInset,
                    showsLayoutDebug: showsQuizLayoutDebug,
                    selectChoice: { viewModel.selectChoice($0) },
                    onMeasuredWidthChange: { choiceID, width in
                        updateMeasuredChoiceWidth(width, for: choiceID)
                    },
                    onLeafDebugSnapshotsChange: { choiceID, snapshots in
                        updateChoiceLeafDebugSnapshots(snapshots, for: choiceID)
                    },
                    onBlockBoundsChange: { choiceID, bounds in
                        updateChoiceBlockDebugBounds(bounds, for: choiceID)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .quizDebugOutline(
                    isVisible: showsQuizLayoutDebug,
                    color: .green,
                    label: "ANSWERS viewport w=\(Self.metric(contentWidth)) group=\(Self.metric(answerGroupWidth)) avoidB=\(Self.metric(answerBottomOverlayInset))"
                )
            }
            .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.top, contentTopPadding)
            .padding(.bottom, contentBottomPadding)
            .frame(width: screenWidth, height: screenHeight, alignment: .topLeading)
            .quizDebugOutline(
                isVisible: showsQuizLayoutDebug,
                color: .cyan,
                label: "FLOW screen=\(Self.metric(screenWidth)) content=\(Self.metric(contentWidth)) padH=\(Self.metric(contentHorizontalPadding)) padT=\(Self.metric(contentTopPadding)) padB=\(Self.metric(contentBottomPadding))"
            )
        }
        .onChange(of: card.id) { _, _ in
            measuredChoiceZoneWidths = [:]
            questionLeafDebugSnapshots = []
            choiceLeafDebugSnapshots = [:]
            questionBlockDebugBounds = []
            choiceBlockDebugBounds = [:]
            explanationBlockDebugBounds = []
        }
    }

    private func explanationSheetContent(safeAreaInsets: UIEdgeInsets) -> some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = 24
            let topPadding: CGFloat = 72
            let bottomPadding = max(safeAreaInsets.bottom, UIConstants.Spacing.extraLarge)
            let contentWidth = max(proxy.size.width - (horizontalPadding * 2), 1)
            let availableScrollHeight = max(proxy.size.height - topPadding - bottomPadding, 1)
            let needsScroll = measuredExplanationSheetHeight > proxy.size.height + 1

            ZStack(alignment: .topTrailing) {
                ScrollView(.vertical, showsIndicators: needsScroll) {
                    if let explanationZone = viewModel.currentCard?.explanationZone {
                        QuizPlaybackZoneContent(
                            zone: explanationZone,
                            fontScale: playModeTextScale,
                            availableWidth: contentWidth,
                            centersLeafBlocks: false,
                            alignLeafBlocksToGroupLeading: false,
                            showsLayoutDebug: showsQuizLayoutDebug,
                            onBlockBoundsChange: updateExplanationBlockDebugBounds
                        )
                        .frame(width: contentWidth, alignment: .topLeading)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, topPadding)
                        .padding(.bottom, bottomPadding)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            ceil(proxy.size.height)
                        } action: { newHeight in
                            updateMeasuredExplanationSheetHeight(newHeight)
                        }
                        .frame(
                            minHeight: needsScroll ? nil : availableScrollHeight,
                            alignment: .top
                        )
                    }
                }
                .scrollDisabled(!needsScroll)

                ChromeSoftCircleSymbolButton(
                    systemName: "xmark",
                    accessibilityLabel: AppLocalization.string("Close", locale: appPreferences.resolvedLocale),
                    action: { showsExplanationSheet = false }
                )
                .padding(.top, UIConstants.Spacing.medium)
                .padding(.trailing, UIConstants.Spacing.medium)
            }
        }
    }

    private var explanationSheetHeightMode: FullScreenSheetHeightMode {
        .absolute(measuredExplanationSheetHeight > 0 ? measuredExplanationSheetHeight : 340)
    }

    private func updateMeasuredExplanationSheetHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        if abs(measuredExplanationSheetHeight - height) > 0.5 {
            measuredExplanationSheetHeight = height
        }
    }

    private var quizQuestionSeparator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(height: 1)
    }

    private func centeredMessageCard(
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
            .frame(maxWidth: 560)
            Spacer(minLength: 0)
        }
    }

    private func quizFloatingControls() -> some View {
        HStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: UIConstants.Spacing.small) {
                if showsMissedCorrectFloatingButton {
                    quizMissedCorrectFloatingButton
                }

                if showsExplanationFloatingButton {
                    quizExplanationFloatingButton
                }
            }
            .bottomChromeVisibility(isSecondaryFloatingControlsVisible)
            .accessibilityHidden(!isSecondaryFloatingControlsVisible)

            Spacer(minLength: UIConstants.Spacing.standard)

            quizPrimaryFloatingButton(
                title: viewModel.primaryActionTitle,
                isDisabled: isPrimaryActionDisabled,
                action: handlePrimaryAction
            )
            .bottomChromeVisibility(isPrimaryFloatingButtonVisible)
            .accessibilityHidden(!isPrimaryFloatingButtonVisible)
        }
    }

    private var quizMissedCorrectFloatingButton: some View {
        Button(action: viewModel.revealMissedCorrectChoices) {
            Image(systemName: "lightbulb.max.fill")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(viewModel.canRevealMissedCorrectChoices ? Color.orange : Color.orange.opacity(0.62))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canRevealMissedCorrectChoices)
        .accessibilityLabel("Show missed correct answers")
    }

    private var quizExplanationFloatingButton: some View {
        Button(action: openExplanationSheet) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(.orange)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Explain")
    }

    private func quizPrimaryFloatingButton(
        title: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Capsule(style: .continuous)
                    .fill(primaryFloatingBackground(isDisabled: isDisabled))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(isDisabled ? 0.08 : 0.20), lineWidth: 1)
                    }

                Text(title)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(isDisabled ? Color.white.opacity(0.42) : .white)
                    .lineLimit(1)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .contentTransition(.identity)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .animation(nil, value: title)
        .animation(nil, value: isDisabled)
    }

    private func primaryFloatingBackground(isDisabled: Bool) -> Color {
        if isDisabled {
            return Color(white: 0.2)
        }

        return primaryFloatingTint
    }

    private var quizLayoutDebugButton: some View {
        VStack(alignment: .trailing, spacing: UIConstants.Spacing.small) {
            if showsQuizLayoutDebug {
                Button(action: copyQuizLayoutDebugReport) {
                    Label(didCopyQuizLayoutDebug ? "Copied" : "Copy Layout", systemImage: "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(white: 0.18).opacity(0.86), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Button {
                showsQuizLayoutDebug.toggle()
            } label: {
                Label(showsQuizLayoutDebug ? "Hide Quiz Debug" : "Quiz Debug", systemImage: "ruler")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(showsQuizLayoutDebug ? Color.purple.opacity(0.95) : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.18).opacity(0.86), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func copyQuizLayoutDebugReport() {
        UIPasteboard.general.string = quizLayoutDebugReport
        didCopyQuizLayoutDebug = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            didCopyQuizLayoutDebug = false
        }
    }

    private var quizLayoutDebugReport: String {
        var lines: [String] = [
            "QuizFlash Quiz Layout Debug",
            "timestamp: \(Self.debugTimestamp())",
            "deck: \(viewModel.resolvedDeckTitle)",
            "loadState: \(String(describing: viewModel.loadState))",
            "isEvaluated: \(viewModel.isEvaluated)",
            "lastEvaluationWasCorrect: \(String(describing: viewModel.lastEvaluationWasCorrect))",
            "selectedChoiceIDs: \(viewModel.selectedChoiceIDs.map(\.uuidString).sorted().joined(separator: ", "))",
            "incorrectChoiceIDs: \(viewModel.incorrectChoiceIDs.map(\.uuidString).sorted().joined(separator: ", "))",
            "missedCorrectChoiceIDs: \(viewModel.missedCorrectChoiceIDs.map(\.uuidString).sorted().joined(separator: ", "))",
            "revealedMissedCorrectChoiceIDs: \(viewModel.revealedMissedCorrectChoiceIDs.map(\.uuidString).sorted().joined(separator: ", "))",
            "contentHorizontalPadding: \(Self.metric(contentHorizontalPadding))",
            "contentTopPadding: \(Self.metric(contentTopPadding))",
            "contentBottomPadding: \(Self.metric(contentBottomPadding))",
            "floatingControlsHeight: \(Self.metric(measuredFloatingControlsHeight))",
            "quizDebugControlsHeight: \(Self.metric(measuredQuizDebugControlsHeight))",
            "textScale: \(String(format: "%.2f", playModeTextScale))",
            "zoneCornerRadius: \(Self.metric(ZoneContentMetrics.zoneCornerRadius))",
            "minimumFixedAnswerZoneHeight: \(Self.metric(QuizChoiceRow.minimumFixedZoneHeight))",
            "feedbackStyle: native zone surface border",
            "",
        ]

        guard let card = viewModel.currentCard else {
            lines.append("currentCard: <none>")
            return lines.joined(separator: "\n")
        }

        lines += [
            "cardNumber: \(card.cardNumber)",
            "cardID: \(card.id)",
            "allowsMultipleCorrect: \(card.allowsMultipleCorrect)",
            "questionText: \(Self.debugPreview(card.questionZone.text))",
            "",
            "QUESTION ZONE TREE",
        ]
        lines.append(contentsOf: Self.zoneTreeLines(for: card.questionZone, path: "question.root", depth: 0))
        lines += [
            "",
            "QUESTION LEAF METRICS",
        ]
        if questionLeafDebugSnapshots.isEmpty {
            lines.append("no question leaf metrics captured; enable Quiz Debug and wait one render pass before copying")
        } else {
            for leaf in questionLeafDebugSnapshots {
                lines.append(contentsOf: Self.leafLines(for: leaf))
            }
        }
        lines += [
            "",
            "QUESTION BLOCK BOUNDS",
        ]
        lines.append(contentsOf: Self.blockBoundsLines(for: questionBlockDebugBounds))

        lines += [
            "",
            "choices:",
        ]

        for (index, choice) in card.choices.enumerated() {
            let measuredWidth = measuredChoiceZoneWidths[choice.id].map { Self.metric($0) } ?? "<none>"
            let selected = viewModel.selectedChoiceIDs.contains(choice.id)
            let markedWrong = viewModel.incorrectChoiceIDs.contains(choice.id)

            lines += [
                "- index: \(index)",
                "  id: \(choice.id.uuidString)",
                "  correct: \(choice.isCorrect)",
                "  selected: \(selected)",
                "  markedWrong: \(markedWrong)",
                "  measuredZoneWidth: \(measuredWidth)",
                "  text: \(Self.debugPreview(choice.contentZone.text))",
                "  zoneTree:",
            ]
            lines.append(contentsOf: Self.zoneTreeLines(for: choice.contentZone, path: "choice[\(index)].root", depth: 2))
            lines.append("  blockBounds:")
            lines.append(contentsOf: Self.blockBoundsLines(for: choiceBlockDebugBounds[choice.id] ?? []).map { "  \($0)" })
            lines.append("  leafMetrics:")
            if let snapshots = choiceLeafDebugSnapshots[choice.id], !snapshots.isEmpty {
                for leaf in snapshots {
                    lines.append(contentsOf: Self.leafLines(for: leaf).map { "  \($0)" })
                }
            } else {
                lines.append("    <none captured>")
            }
        }

        if let explanationZone = card.explanationZone {
            lines += [
                "",
                "EXPLANATION ZONE TREE",
            ]
            lines.append(contentsOf: Self.zoneTreeLines(for: explanationZone, path: "explanation.root", depth: 0))
            lines += [
                "",
                "EXPLANATION BLOCK BOUNDS",
            ]
            lines.append(contentsOf: Self.blockBoundsLines(for: explanationBlockDebugBounds))
        }

        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private var dismissButton: some View {
        if shouldConfirmDismiss {
            Menu {
                Button {
                    dismissSheet()
                } label: {
                    Label(localized("Close and keep progress"), systemImage: "checkmark.circle")
                }

                Button {
                } label: {
                    Label(localized("Continue playing"), systemImage: "play.fill")
                }
            } label: {
                ChromeSoftCircleSymbol(
                    systemName: "xmark",
                    size: UIConstants.Size.actionButton
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("Close"))
        } else {
            ChromeSoftCircleSymbolButton(
                systemName: "xmark",
                accessibilityLabel: localized("Close"),
                action: dismissSheet,
                size: UIConstants.Size.actionButton
            )
        }
    }

    private func headerMetric(value: Int, symbol: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)

            Text("\(value)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.94))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
        }
    }

    private var completionOverlay: some View {
        PlayModeCompletionOverlay(
            headline: "Session Complete!",
            xpEarned: viewModel.sessionXP,
            stats: completionStats,
            primaryActionTitle: "Continue",
            primaryAction: dismissSheet,
            secondaryActionTitle: nil,
            secondaryAction: nil
        )
    }

    private var retryCompletionOverlay: some View {
        PlayModeCompletionOverlay(
            headline: "Session Complete!",
            xpEarned: viewModel.sessionXP,
            stats: completionStats,
            primaryActionTitle: "Retry Wrong Questions",
            primaryAction: advanceQuestionWithFade,
            secondaryActionTitle: "Continue",
            secondaryAction: dismissSheet
        )
    }

    private var completionStats: [PlayModeCompletionStat] {
        [
            PlayModeCompletionStat(title: "Accuracy", value: "\(sessionAccuracy)%", icon: "target", color: .green),
            PlayModeCompletionStat(title: "Time", value: viewModel.formattedSessionDuration, icon: "timer", color: .blue),
            PlayModeCompletionStat(title: "Correct", value: "\(viewModel.correctCount)", icon: "checkmark.circle.fill", color: .green),
            PlayModeCompletionStat(title: "Wrong", value: "\(viewModel.wrongCount)", icon: "xmark.circle.fill", color: .red),
        ]
    }

    private var showsFloatingQuizControls: Bool {
        showsPrimaryFloatingButton || showsExplanationFloatingButton || showsMissedCorrectFloatingButton
    }

    private func quizFloatingControlsBottomPadding(safeBottomInset: CGFloat) -> CGFloat {
        max(safeBottomInset, UIConstants.Spacing.large)
    }

    private func quizAnswerBottomOverlayInset(safeBottomInset: CGFloat) -> CGFloat {
        let baseInset = contentBottomPadding
        let floatingBottomExtent = quizFloatingControlsBottomPadding(safeBottomInset: safeBottomInset)
            + max(measuredFloatingControlsHeight, minimumReservedFloatingControlsHeight)
        guard floatingBottomExtent > baseInset else { return 0 }
        return ceil(floatingBottomExtent - baseInset + UIConstants.Spacing.small)
    }

    private func updateMeasuredFloatingControlsHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        if abs(measuredFloatingControlsHeight - height) > 0.5 {
            measuredFloatingControlsHeight = height
        }
    }

    private func updateMeasuredQuizDebugControlsHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        if abs(measuredQuizDebugControlsHeight - height) > 0.5 {
            measuredQuizDebugControlsHeight = height
        }
    }

    private var showsPrimaryFloatingButton: Bool {
        switch viewModel.loadState {
        case .ready:
            return viewModel.isShowingRetryPrompt
                || viewModel.requiresSubmitAction
                || didAnswerCorrectly
                || didEvaluateMultipleAnswerCard
        default:
            return false
        }
    }

    private var showsExplanationFloatingButton: Bool {
        (didAnswerCorrectly || didEvaluateMultipleAnswerCard)
            && viewModel.currentCard?.explanationZone != nil
    }

    private var showsMissedCorrectFloatingButton: Bool {
        viewModel.hasMissedCorrectChoices
    }

    private var isSecondaryFloatingControlsVisible: Bool {
        areFloatingControlsVisible && (showsExplanationFloatingButton || showsMissedCorrectFloatingButton)
    }

    private var isPrimaryFloatingButtonVisible: Bool {
        areFloatingControlsVisible && showsPrimaryFloatingButton
    }

    private var isExplanationFloatingButtonVisible: Bool {
        areFloatingControlsVisible && showsExplanationFloatingButton
    }

    private var isPrimaryActionDisabled: Bool {
        if isQuestionTransitioning { return true }
        if viewModel.isShowingRetryPrompt { return false }
        if viewModel.isEvaluated { return false }
        return !viewModel.canSubmitAnswer
    }

    private var primaryFloatingTint: Color {
        if viewModel.isShowingRetryPrompt { return .orange }
        if viewModel.isEvaluated { return ThemeManager.shared.accentColor.color }
        return .green
    }

    private var didAnswerCorrectly: Bool {
        viewModel.isEvaluated && viewModel.lastEvaluationWasCorrect == true
    }

    private var didEvaluateMultipleAnswerCard: Bool {
        viewModel.isEvaluated && viewModel.currentCard?.allowsMultipleCorrect == true
    }

    private var allowsChoiceSelection: Bool {
        guard !viewModel.isEvaluated else {
            return viewModel.lastEvaluationWasCorrect == false
                && viewModel.currentCard?.allowsMultipleCorrect == false
        }
        return true
    }

    private var headerSubtitle: String {
        if viewModel.isShowingRetryPrompt {
            return "MAIN PASS COMPLETE"
        }
        return viewModel.isRetryPass ? "RETRY PASS" : "QUIZ"
    }

    private var sessionAccuracy: Int {
        let totalAnswers = viewModel.correctCount + viewModel.wrongCount
        guard totalAnswers > 0 else { return 0 }
        return Int((Double(viewModel.correctCount) / Double(totalAnswers)) * 100)
    }

    private var invalidBullets: [String] {
        var bullets = [
            "Question required.",
            "At least 2 non-empty choices required.",
            "At least 1 correct choice required.",
            "Single-answer cards must have exactly 1 correct choice.",
        ]

        let reasonSummaries = viewModel.diagnostics.nonZeroReasonCounts.compactMap { reason, count -> String? in
            switch reason {
            case .missingQuestion:
                return "\(count) card\(count == 1 ? "" : "s") had no question content."
            case .insufficientChoices:
                return "\(count) card\(count == 1 ? "" : "s") had fewer than 2 non-empty choices."
            case .missingCorrectChoice:
                return "\(count) card\(count == 1 ? "" : "s") had no correct choice."
            case .multipleCorrectChoicesDisallowed:
                return "\(count) single-answer card\(count == 1 ? "" : "s") had multiple correct choices."
            }
        }

        bullets.append(contentsOf: reasonSummaries)
        return bullets
    }

    private func handlePrimaryAction() {
        if viewModel.isShowingRetryPrompt {
            advanceQuestionWithFade()
            return
        }

        guard viewModel.currentCard != nil else { return }

        if !viewModel.isEvaluated {
            viewModel.submitAnswer()
        } else {
            advanceQuestionWithFade()
        }
    }

    private func openExplanationSheet() {
        guard viewModel.currentCard?.explanationZone != nil else { return }
        viewModel.revealExplanation()
        measuredExplanationSheetHeight = 0
        showsExplanationSheet = true
    }

    private func quizDebugBottomPadding(safeBottomInset: CGFloat) -> CGFloat {
        let basePadding = max(safeBottomInset, UIConstants.Spacing.large)
        return showsFloatingQuizControls ? basePadding + 64 : basePadding
    }

    private func choiceGroupWidth(availableWidth: CGFloat) -> CGFloat {
        let clampedWidth = max(availableWidth, 1)
        let measuredWidth = measuredChoiceZoneWidths.values.max() ?? 0
        guard measuredWidth > 0 else { return clampedWidth }
        return min(max(ceil(measuredWidth), 1), clampedWidth)
    }

    private func updateMeasuredChoiceWidth(_ width: CGFloat, for choiceID: UUID) {
        guard width > 0 else { return }
        let roundedWidth = ceil(width)
        if abs((measuredChoiceZoneWidths[choiceID] ?? 0) - roundedWidth) > 0.5 {
            measuredChoiceZoneWidths[choiceID] = roundedWidth
        }
    }

    private func updateQuestionLeafDebugSnapshots(_ snapshots: [ZoneContentLeafLayoutDebugSnapshot]) {
        let sortedSnapshots = snapshots.sorted { $0.path < $1.path }
        guard sortedSnapshots != questionLeafDebugSnapshots else { return }
        questionLeafDebugSnapshots = sortedSnapshots
    }

    private func updateChoiceLeafDebugSnapshots(
        _ snapshots: [ZoneContentLeafLayoutDebugSnapshot],
        for choiceID: UUID
    ) {
        let sortedSnapshots = snapshots.sorted { $0.path < $1.path }
        guard choiceLeafDebugSnapshots[choiceID] != sortedSnapshots else { return }
        choiceLeafDebugSnapshots[choiceID] = sortedSnapshots
    }

    private func updateQuestionBlockDebugBounds(_ bounds: [ZoneContentRenderBlockBounds]) {
        guard bounds != questionBlockDebugBounds else { return }
        questionBlockDebugBounds = bounds
    }

    private func updateChoiceBlockDebugBounds(
        _ bounds: [ZoneContentRenderBlockBounds],
        for choiceID: UUID
    ) {
        guard choiceBlockDebugBounds[choiceID] != bounds else { return }
        choiceBlockDebugBounds[choiceID] = bounds
    }

    private func updateExplanationBlockDebugBounds(_ bounds: [ZoneContentRenderBlockBounds]) {
        guard bounds != explanationBlockDebugBounds else { return }
        explanationBlockDebugBounds = bounds
    }

    private static func metric(_ value: CGFloat) -> String {
        String(format: "%.0f", ceil(value))
    }

    private static func debugTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func debugPreview(_ value: String, limit: Int = 180) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: "\\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "..."
    }

    private static func zoneTreeLines(for zone: ZoneModel, path: String, depth: Int) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        if zone.isLeaf {
            var line = "\(indent)- \(path) leaf type=\(zone.contentType.rawValue) hasContent=\(zone.hasContent) sizeMode=\(zone.sizeMode.rawValue) verticalAlignment=\(zone.verticalAlignment.rawValue)"
            if zone.contentType == .text || zone.contentType == .code {
                line += " rawChars=\(zone.text.count) rawLines=\(max(zone.text.components(separatedBy: .newlines).count, 1)) preview=\"\(singleLinePreview(zone.text, limit: 140))\""
            }
            return [line]
        }

        let children = zone.children ?? []
        var lines = [
            "\(indent)- \(path) container direction=\(zone.direction.rawValue) children=\(children.count) filledChildren=\(children.filter(\.hasContent).count)",
        ]
        for (index, child) in children.enumerated() {
            lines.append(contentsOf: zoneTreeLines(for: child, path: "\(path).\(index)", depth: depth + 1))
        }
        return lines
    }

    private static func leafLines(for leaf: ZoneContentLeafLayoutDebugSnapshot) -> [String] {
        let maxEstimatedLine = leaf.estimatedLineWidths.max() ?? 0
        let textWidthLimit = leaf.textWidthLimit ?? leaf.contentLayoutWidth
        let rightSpaceAfterBlock = max(leaf.availableWidth - leaf.leadingInset - leaf.blockSize.width, 0)
        let remainingTextWidth = max(textWidthLimit - maxEstimatedLine, 0)
        let lineWidths = leaf.estimatedLineWidths.map { metric($0) }.joined(separator: ", ")
        let renderedLineWidths = leaf.renderedLineWidths.map { metric($0) }.joined(separator: ", ")
        let renderedLines = leaf.renderedLineTexts.enumerated()
            .map { index, lineText in
                let lineWidth = index < leaf.renderedLineWidths.count ? leaf.renderedLineWidths[index] : 0
                return "    \(index + 1). [\(metric(lineWidth))] \"\(lineText)\""
            }
            .joined(separator: "\n")
        let renderedTokenLines = tokenDebugLines(for: leaf.renderedTokenLines)
        let renderedScrollableMath = scrollableMathDebugLines(for: leaf.renderedScrollableMath)
        let mathGestureDebug = gestureDebugLine(for: leaf.mathGestureDebug)
        let renderStatusDebug = renderStatusDebugLine(for: leaf.renderStatusDebug)

        return [
            "- \(leaf.path) id=\(leaf.zoneID.uuidString)",
            "  type=\(leaf.contentType.rawValue) hasContent=\(leaf.hasContent) math=\(leaf.containsMath) inlineCode=\(leaf.containsInlineCode)",
            "  blockAlignment raw=\(leaf.rawBlockAlignment.rawValue) resolved=\(leaf.resolvedBlockAlignment.rawValue)",
            "  availableWidth=\(metric(leaf.availableWidth)) estimated=\(size(leaf.estimatedSize)) rendered=\(size(leaf.renderedContentSize))",
            "  block=\(size(leaf.blockSize)) leadingInset=\(metric(leaf.leadingInset)) rightSpaceAfterBlock=\(metric(rightSpaceAfterBlock))",
            "  measurements updates=\(leaf.measurementUpdateCount) resets=\(leaf.measurementResetCount) rawMeasured=\(size(leaf.rawMeasuredContentSize)) frameH=\(leaf.contentFrameHeight.map(metric) ?? "nil") slack=\(metric(leaf.blockHeightSlack))",
            "  contentLayoutWidth=\(metric(leaf.contentLayoutWidth)) textWidthLimit=\(metric(textWidthLimit)) remainingTextWidthAfterWidestLine=\(metric(remainingTextWidth))",
            "  textInsets=\(metric(leaf.textHorizontalInsets)) intrinsicText=\(leaf.usesIntrinsicTextMeasurement)",
            "  sizeMode=\(leaf.zoneSizeMode.rawValue)",
            "  style=\(leaf.textStyle.rawValue) font=\(leaf.fontFamily.rawValue) bold=\(leaf.isBold) italic=\(leaf.isItalic) highlight=\(leaf.highlightColor.rawValue)",
            "  rawChars=\(leaf.rawTextCharacterCount) rawExplicitLines=\(leaf.rawTextLineCount) displayChars=\(leaf.textCharacterCount) displayExplicitLines=\(leaf.textLineCount)",
            "  estimatedLineWidths=[\(lineWidths)] renderedLineWidths=[\(renderedLineWidths)]",
            "  rawText:",
            leaf.rawText.isEmpty ? "  <empty>" : indentMultiline(leaf.rawText, prefix: "  | "),
            "  normalizedDisplayText:",
            leaf.normalizedDisplayText.isEmpty ? "  <empty>" : indentMultiline(leaf.normalizedDisplayText, prefix: "  | "),
            "  healedDisplayText:",
            leaf.healedDisplayText.isEmpty ? "  <empty>" : indentMultiline(leaf.healedDisplayText, prefix: "  | "),
            "  renderedLines:",
            renderedLines.isEmpty ? "    <none>" : renderedLines,
            "  renderedTokenLines:",
            renderedTokenLines.isEmpty ? "    <none>" : renderedTokenLines,
            "  renderedScrollableMath:",
            renderedScrollableMath.isEmpty ? "    <none>" : renderedScrollableMath,
            "  renderStatusDebug:",
            renderStatusDebug,
            "  mathGestureDebug:",
            mathGestureDebug,
            "  preview=\"\(leaf.textPreview)\"",
        ]
    }

    private static func blockBoundsLines(for bounds: [ZoneContentRenderBlockBounds]) -> [String] {
        guard !bounds.isEmpty else { return ["<none captured; enable Quiz Debug and wait one render pass>"] }

        return bounds.map { bound in
            let textWidth = bound.textWidthLimit
                .map { String(format: "%.0f", ceil($0)) } ?? "n/a"
            return "- \(bound.path) \(bound.kind) id=\(bound.zoneID.uuidString.prefix(6)) frame=(x:\(metric(bound.frame.minX)), y:\(metric(bound.frame.minY)), w:\(metric(bound.frame.width)), h:\(metric(bound.frame.height))) available=\(metric(bound.availableWidth)) block=\(size(bound.blockSize)) insets=(lead:\(metric(bound.leadingInset)), trail:\(metric(bound.trailingInset))) align=(raw:\(bound.rawBlockAlignment.rawValue), resolved:\(bound.resolvedBlockAlignment.rawValue)) textPadding=(h:\(metric(bound.textHorizontalInsets)), v:\(metric(bound.textVerticalPadding))) contentWidth=\(metric(bound.contentLayoutWidth)) textWidthLimit=\(textWidth)"
        }
    }

    private static func tokenDebugLines(for lines: [MixedMathRenderedLineDebug]) -> String {
        guard !lines.isEmpty else { return "" }

        return lines.enumerated()
            .map { offset, line in
                let remaining = max(line.widthLimit - line.width, 0)
                let nextFirstToken = offset + 1 < lines.count ? lines[offset + 1].tokens.first : nil
                let nextFitText: String
                if let nextFirstToken {
                    let fitsAlone = nextFirstToken.width <= remaining
                    nextFitText = " nextFirst=\"\(singleLinePreview(nextFirstToken.text, limit: 44))\" width=\(metric(nextFirstToken.width)) fitsRemainingWithoutSpace=\(fitsAlone)"
                } else {
                    nextFitText = ""
                }

                let tokens = line.tokens
                    .map { token in
                        "      - \(token.kind) \"\(singleLinePreview(token.text, limit: 90))\" frame=(x:\(metric(token.left)), y:\(metric(token.top)), w:\(metric(token.width)), h:\(metric(token.height)), r:\(metric(token.right)), b:\(metric(token.bottom)))"
                    }
                    .joined(separator: "\n")

                let header = "    \(line.index). frame=(x:\(metric(line.left)), y:\(metric(line.top)), w:\(metric(line.width)), h:\(metric(line.height)), r:\(metric(line.right)), b:\(metric(line.bottom))) limit=\(metric(line.widthLimit)) remaining=\(metric(remaining))\(nextFitText)"
                return tokens.isEmpty ? header : "\(header)\n\(tokens)"
            }
            .joined(separator: "\n")
    }

    private static func scrollableMathDebugLines(for rows: [MixedMathScrollableDebug]) -> String {
        guard !rows.isEmpty else { return "" }

        return rows.enumerated()
            .map { index, row in
                "    \(index + 1). kind=\(row.kind) wrapperHeight=\(metric(row.wrapperHeight)) clientHeight=\(metric(row.clientHeight)) scrollHeight=\(metric(row.scrollHeight)) visualHeight=\(metric(row.visualHeight)) visualTop=\(metric(row.visualTop)) visualBottom=\(metric(row.visualBottom)) paddingTop=\(metric(row.paddingTop)) paddingBottom=\(metric(row.paddingBottom)) topAdjustment=\(metric(row.topAdjustment))"
            }
            .joined(separator: "\n")
    }

    private static func gestureDebugLine(for snapshot: MixedMathGestureDebugSnapshot?) -> String {
        guard let snapshot else { return "    <none>" }

        return "    decision=\(snapshot.decision) reason=\"\(snapshot.reason)\" direction=\"\(snapshot.direction)\" location=(x:\(metric(snapshot.location.x)), y:\(metric(snapshot.location.y))) h=\(metric(snapshot.horizontalMagnitude)) v=\(metric(snapshot.verticalMagnitude)) canLeft=\(snapshot.canScrollLeft) canRight=\(snapshot.canScrollRight) regions=\(snapshot.regionCount)"
    }

    private static func renderStatusDebugLine(for snapshot: MixedMathRenderStatusDebug?) -> String {
        guard let snapshot else { return "    <none>" }

        return "    stage=\(snapshot.stage) contentLen=\(snapshot.contentLength) childCount=\(snapshot.childCount) textLen=\(snapshot.textLength) body=\(metric(snapshot.bodyWidth))x\(metric(snapshot.bodyHeight)) content=\(metric(snapshot.contentWidth))x\(metric(snapshot.contentHeight)) scroll=\(metric(snapshot.contentScrollWidth))x\(metric(snapshot.contentScrollHeight)) inlineCode=\(snapshot.inlineCodeCount) math=\(snapshot.mathCount) displayMath=\(snapshot.displayMathCount) codeScroll=\(snapshot.inlineCodeScrollCount) inlineMathScroll=\(snapshot.inlineMathScrollCount) layoutReports=\(snapshot.layoutMetricReportCount) lineReports=\(snapshot.lineDebugReportCount)"
    }

    private static func singleLinePreview(_ value: String, limit: Int) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "..."
    }

    private static func indentMultiline(_ value: String, prefix: String) -> String {
        value.components(separatedBy: .newlines)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    private static func size(_ size: CGSize) -> String {
        "\(metric(size.width)) x \(metric(size.height))"
    }

    private func dismissSheet() {
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            dismiss()
        }
    }

    private var shouldConfirmDismiss: Bool {
        viewModel.currentIndex > 0
            || viewModel.isEvaluated
            || !viewModel.selectedChoiceIDs.isEmpty
            || viewModel.correctCount > 0
            || viewModel.wrongCount > 0
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: appPreferences.resolvedLocale)
    }

    private func emitQuizEvaluationHaptic(isCorrect: Bool) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(isCorrect ? .success : .error)
    }

    private func advanceQuestionWithFade() {
        guard !isQuestionTransitioning else { return }

        questionTransitionTask?.cancel()
        isQuestionTransitioning = true
        showsExplanationSheet = false

        questionTransitionTask = Task { @MainActor in
            withAnimation(questionContentTransition) {
                isQuestionContentVisible = false
            }
            withBottomChromeAnimation {
                areFloatingControlsVisible = false
            }

            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }

            viewModel.advance()

            try? await Task.sleep(nanoseconds: 35_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(questionContentTransition) {
                isQuestionContentVisible = true
            }
            withBottomChromeAnimation {
                areFloatingControlsVisible = true
            }

            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }

            isQuestionTransitioning = false
            questionTransitionTask = nil
        }
    }

    private func showQuestionContentIfReady() {
        guard viewModel.loadState == .ready,
              !viewModel.isShowingRetryPrompt,
              viewModel.currentCard != nil else {
            return
        }
        guard !isQuestionContentVisible || !areFloatingControlsVisible else { return }

        questionTransitionTask?.cancel()
        questionTransitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 35_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(questionContentTransition) {
                isQuestionContentVisible = true
            }
            withBottomChromeAnimation {
                areFloatingControlsVisible = true
            }

            questionTransitionTask = nil
        }
    }
}

// MARK: - Explanation Sheet

private struct QuizExplanationSheetBackground: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.94)

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.24)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Quiz Layout Debug

private struct QuizDebugOutline: ViewModifier {
    let isVisible: Bool
    let color: Color
    let label: String

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if isVisible {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(color.opacity(0.95), style: StrokeStyle(lineWidth: 1.3, dash: [5, 4]))

                        Text(label)
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(color)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .offset(x: 4, y: 4)
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}

private extension View {
    func quizDebugOutline(isVisible: Bool, color: Color, label: String) -> some View {
        modifier(QuizDebugOutline(isVisible: isVisible, color: color, label: label))
    }
}

// MARK: - QuizAnswerList

/// Vertical answer list that scrolls only when the choices exceed their allotted
/// height. The question and explanation remain outside this scroll surface.
struct QuizAnswerList: View {
    let choices: [QuizChoiceDraft]
    let selectedChoiceIDs: Set<UUID>
    let incorrectChoiceIDs: Set<UUID>
    let revealedMissedCorrectChoiceIDs: Set<UUID>
    let wrongFeedbackChoiceIDs: Set<UUID>
    let wrongFeedbackTrigger: Int
    let isEvaluated: Bool
    let allowsSelection: Bool
    let fontScale: CGFloat
    let groupWidth: CGFloat
    let layoutWidth: CGFloat
    let topContentInset: CGFloat
    let bottomOverlayInset: CGFloat
    let showsLayoutDebug: Bool
    let selectChoice: (UUID) -> Void
    let onMeasuredWidthChange: (UUID, CGFloat) -> Void
    let onLeafDebugSnapshotsChange: (UUID, [ZoneContentLeafLayoutDebugSnapshot]) -> Void
    let onBlockBoundsChange: (UUID, [ZoneContentRenderBlockBounds]) -> Void

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let viewportHeight = max(ceil(proxy.size.height), 1)
            let effectiveViewportHeight = max(viewportHeight - bottomOverlayInset, 1)
            let needsScroll = contentHeight > effectiveViewportHeight + 1
            let centersContent = !needsScroll
            let centeringHeight = centersContent ? effectiveViewportHeight : viewportHeight
            let centeredContentTopInset = max((centeringHeight - contentHeight) / 2, 0)
            let centeredContentBottom = centeredContentTopInset + contentHeight
            let contentWouldBeCovered = bottomOverlayInset > 0 && centeredContentBottom > effectiveViewportHeight + 1

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.extraLarge) {
                    ForEach(choices) { choice in
                        QuizChoiceRow(
                            choice: choice,
                            isSelected: selectedChoiceIDs.contains(choice.id),
                            isMarkedWrong: incorrectChoiceIDs.contains(choice.id),
                            isRevealedMissedCorrect: revealedMissedCorrectChoiceIDs.contains(choice.id),
                            wrongFeedbackTrigger: wrongFeedbackChoiceIDs.contains(choice.id) ? wrongFeedbackTrigger : 0,
                            isEvaluated: isEvaluated,
                            isCorrect: choice.isCorrect,
                            allowsSelection: allowsSelection,
                            fontScale: fontScale,
                            groupWidth: groupWidth,
                            layoutWidth: layoutWidth,
                            showsLayoutDebug: showsLayoutDebug,
                            action: { selectChoice(choice.id) },
                            onMeasuredWidthChange: { width in
                                onMeasuredWidthChange(choice.id, width)
                            },
                            onLeafDebugSnapshotsChange: { snapshots in
                                onLeafDebugSnapshotsChange(choice.id, snapshots)
                            },
                            onBlockBoundsChange: { bounds in
                                onBlockBoundsChange(choice.id, bounds)
                            }
                        )
                    }
                }
                .frame(width: layoutWidth, alignment: .topLeading)
                .padding(.top, topContentInset)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    ceil(proxy.size.height)
                } action: { newHeight in
                    updateContentHeight(newHeight)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: centersContent ? centeringHeight : nil,
                    alignment: centersContent ? .center : .top
                )
                .padding(.bottom, needsScroll ? bottomOverlayInset : 0)
                .quizDebugOutline(
                    isVisible: showsLayoutDebug,
                    color: .pink,
                    label: "ANSWER CONTENT h=\(Self.metric(contentHeight)) bottom=\(Self.metric(centeredContentBottom)) effective=\(Self.metric(effectiveViewportHeight)) covered=\(contentWouldBeCovered.description) scroll=\(needsScroll.description)"
                )
            }
            .scrollDisabled(!needsScroll)
            .quizDebugOutline(
                isVisible: showsLayoutDebug,
                color: needsScroll ? .red : .green,
                label: "ANSWER VIEWPORT \(Self.metric(groupWidth))x\(Self.metric(viewportHeight)) avoidB=\(Self.metric(bottomOverlayInset)) contentH=\(Self.metric(contentHeight))"
            )
        }
    }

    private func updateContentHeight(_ newHeight: CGFloat) {
        guard newHeight > 0 else { return }
        if abs(contentHeight - newHeight) > 0.5 {
            contentHeight = newHeight
        }
    }

    private static func metric(_ value: CGFloat) -> String {
        String(format: "%.0f", ceil(value))
    }
}

// MARK: - QuizChoiceRow

private struct CorrectAnswerFeedbackFrame {
    var scale: CGFloat = 1
    var verticalOffset: CGFloat = 0
}

/// One authored quiz choice row with immediate correctness styling after evaluation.
struct QuizChoiceRow: View {
    let choice: QuizChoiceDraft
    let isSelected: Bool
    let isMarkedWrong: Bool
    let isRevealedMissedCorrect: Bool
    let wrongFeedbackTrigger: Int
    let isEvaluated: Bool
    let isCorrect: Bool
    let allowsSelection: Bool
    let fontScale: CGFloat
    let groupWidth: CGFloat
    let layoutWidth: CGFloat
    let showsLayoutDebug: Bool
    let action: () -> Void
    let onMeasuredWidthChange: (CGFloat) -> Void
    let onLeafDebugSnapshotsChange: ([ZoneContentLeafLayoutDebugSnapshot]) -> Void
    let onBlockBoundsChange: ([ZoneContentRenderBlockBounds]) -> Void

    @State private var lastTapTime: TimeInterval = 0
    @State private var measuredContentWidth: CGFloat = 0
    @State private var tappableZoneFrame: CGRect = .zero
    @State private var wrongWiggleOffset: CGFloat = 0
    @State private var wrongScale: CGFloat = 1
    @State private var correctFeedbackAnimationTrigger = 0

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            QuizPlaybackZoneContent(
                zone: displayZone,
                fontScale: fontScale,
                availableWidth: choiceContentWidth,
                centersLeafBlocks: false,
                alignLeafBlocksToGroupLeading: false,
                zoneHighlightStrokeStyle: missedCorrectFeedback
                    ? StrokeStyle(lineWidth: 2.5, dash: [8, 5], dashPhase: 0)
                    : StrokeStyle(lineWidth: 2),
                showsLayoutDebug: showsLayoutDebug,
                onTap: handleTap,
                onMeasuredWidthChange: updateMeasuredContentWidth,
                onLeafDebugSnapshotsChange: onLeafDebugSnapshotsChange,
                onBlockBoundsChange: { bounds in
                    updateTappableZoneFrame(from: bounds)
                    onBlockBoundsChange(bounds)
                }
            )
            .keyframeAnimator(
                initialValue: CorrectAnswerFeedbackFrame(),
                trigger: correctFeedbackAnimationTrigger
            ) { content, frame in
                content
                    .scaleEffect(frame.scale, anchor: .center)
                    .offset(y: frame.verticalOffset)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(0.94, duration: 0.10)
                    LinearKeyframe(0.94, duration: 0.045)
                    CubicKeyframe(1.0, duration: 0.12)
                    CubicKeyframe(0.985, duration: 0.07)
                    SpringKeyframe(1.0, duration: 0.16, spring: .smooth)
                }

                KeyframeTrack(\.verticalOffset) {
                    CubicKeyframe(3, duration: 0.10)
                    LinearKeyframe(3, duration: 0.045)
                    CubicKeyframe(-10, duration: 0.12)
                    CubicKeyframe(2, duration: 0.07)
                    SpringKeyframe(0, duration: 0.16, spring: .smooth)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: layoutWidth, alignment: .topLeading)
        .contentShape(Rectangle())
        .simultaneousGesture(
            SpatialTapGesture()
                .onEnded { value in
                    guard tappableZoneHitFrame.contains(value.location) else { return }
                    handleTap()
                }
        )
        .opacity(isEvaluated || isSelected ? 1 : 0.98)
        .offset(x: wrongWiggleOffset)
        .scaleEffect(wrongFeedback ? wrongScale : 1, anchor: .center)
        .zIndex(correctFeedback ? 1 : 0)
        .onChange(of: wrongFeedback) { _, isActive in
            if !isActive {
                wrongWiggleOffset = 0
                wrongScale = 1
            }
        }
        .onChange(of: wrongFeedbackTrigger) { _, trigger in
            guard trigger > 0, wrongFeedback else { return }
            runWrongFeedbackSequence()
        }
        .onChange(of: correctFeedback) { _, isActive in
            if isActive {
                correctFeedbackAnimationTrigger &+= 1
            }
        }
        .animation(.easeOut(duration: 0.16), value: isSelected)
        .animation(.easeOut(duration: 0.16), value: isEvaluated)
        .animation(.easeOut(duration: 0.16), value: correctFeedback)
        .quizDebugOutline(
            isVisible: showsLayoutDebug,
            color: .pink,
            label: "ROW group=\(Self.metric(groupWidth)) layout=\(Self.metric(layoutWidth)) content=\(Self.metric(measuredContentWidth))"
        )
    }

    static let minimumFixedZoneHeight: CGFloat = 86

    private var correctFeedback: Bool {
        isSelected && isEvaluated && isCorrect
    }

    private var wrongFeedback: Bool {
        isMarkedWrong
    }

    private var missedCorrectFeedback: Bool {
        isRevealedMissedCorrect && isEvaluated && isCorrect && !isSelected
    }

    private var selectionFeedback: Bool {
        isSelected && !isEvaluated
    }

    private var displayZone: ZoneModel {
        guard choice.contentZone.isLeaf else {
            return choice.contentZone
        }

        var zone = choice.contentZone
        zone.verticalAlignment = .center
        if wrongFeedback {
            zone.highlightColor = .red
        } else if correctFeedback {
            zone.highlightColor = .green
        } else if missedCorrectFeedback {
            zone.highlightColor = .green
        } else if selectionFeedback {
            zone.highlightColor = .accent
        }

        if rendersCodeAnswer(zone) {
            zone.sizeMode = .fixed
            zone.fixedWidth = measuredCodeAnswerZoneWidth(for: zone)
            zone.fixedHeight = max(zone.fixedHeight ?? 0, Self.minimumFixedZoneHeight)
            return zone
        }

        switch zone.sizeMode {
        case .auto:
            break
        case .fillWidth:
            break
        case .fixed:
            zone.fixedHeight = max(zone.fixedHeight ?? 0, Self.minimumFixedZoneHeight)
        }
        return zone
    }

    private func rendersCodeAnswer(_ zone: ZoneModel) -> Bool {
        zone.contentType == .code || zone.text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```")
    }

    private func measuredCodeAnswerZoneWidth(for zone: ZoneModel) -> CGFloat {
        let code = strippedCodeText(zone.text)
        let measuredText = code.isEmpty ? " " : code
        let font = UIFont.monospacedSystemFont(
            ofSize: codeAnswerFontSize(for: zone),
            weight: .regular
        )
        let widestLine = measuredText
            .components(separatedBy: .newlines)
            .map { line in
                let value = line.isEmpty ? " " : line
                return ceil((value as NSString).size(withAttributes: [.font: font]).width)
            }
            .max() ?? 1
        let codeInternalPadding = CodeSnippetMetrics.contentPadding * 2
        let zoneHorizontalPadding = ZoneContentMetrics.textHorizontalPadding
        return min(ceil(widestLine + codeInternalPadding + zoneHorizontalPadding), layoutWidth)
    }

    private func codeAnswerFontSize(for zone: ZoneModel) -> CGFloat {
        ZoneTextTypography.fontSize(for: zone.textStyle, fontScale: fontScale) * CodeSnippetMetrics.relativeFontScale
    }

    private func strippedCodeText(_ text: String) -> String {
        var stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stripped.hasPrefix("```") else { return stripped }

        let lines = stripped.components(separatedBy: .newlines)
        stripped = lines.dropFirst().joined(separator: "\n")
        if stripped.hasSuffix("```") {
            stripped = String(stripped.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return stripped
    }

    private func handleTap() {
        guard allowsSelection else { return }

        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastTapTime > 0.22 else { return }
        lastTapTime = now
        action()
    }

    private func runWrongFeedbackSequence() {
        wrongWiggleOffset = 0
        withAnimation(.easeOut(duration: 0.16)) {
            wrongScale = 0.96
        }
        withAnimation(.linear(duration: 0.055).repeatCount(3, autoreverses: true)) {
            wrongWiggleOffset = 6
        }
    }

    private func updateMeasuredContentWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        let roundedWidth = ceil(width)
        if abs(measuredContentWidth - roundedWidth) > 0.5 {
            measuredContentWidth = roundedWidth
        }
        onMeasuredWidthChange(width)
    }

    private func updateTappableZoneFrame(from bounds: [ZoneContentRenderBlockBounds]) {
        guard let rootFrame = bounds.first(where: { $0.zoneID == choice.contentZone.id })?.frame,
              rootFrame != tappableZoneFrame else {
            return
        }
        tappableZoneFrame = rootFrame
    }

    private var choiceContentWidth: CGFloat {
        max(layoutWidth, 1)
    }

    private var tappableZoneHitFrame: CGRect {
        guard tappableZoneFrame.width > 0, tappableZoneFrame.height > 0 else {
            let measuredWidth = measuredContentWidth > 0 ? measuredContentWidth : groupWidth
            let width = max(min(measuredWidth, layoutWidth), 1)
            return CGRect(
                x: max((layoutWidth - width) / 2, 0),
                y: 0,
                width: width,
                height: .greatestFiniteMagnitude
            )
        }

        return tappableZoneFrame.insetBy(dx: -8, dy: -8)
    }

    private static func metric(_ value: CGFloat) -> String {
        String(format: "%.0f", ceil(value))
    }
}

// MARK: - QuizPlaybackZoneContent

struct QuizQuestionScrollViewport<Content: View>: View {
    let maxHeight: CGFloat
    let content: Content
    @State private var measuredContentHeight: CGFloat = 0

    init(maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        self.content = content()
    }

    private var contentOverflows: Bool {
        measuredContentHeight > maxHeight + 0.5
    }

    private var viewportHeight: CGFloat {
        guard measuredContentHeight > 0 else { return maxHeight }
        return min(max(measuredContentHeight, 1), maxHeight)
    }

    var body: some View {
        ScrollView(.vertical) {
            content
                .onGeometryChange(for: CGFloat.self) { proxy in
                    ceil(proxy.size.height)
                } action: { newHeight in
                    guard newHeight > 0 else { return }
                    if abs(measuredContentHeight - newHeight) > 0.5 {
                        measuredContentHeight = newHeight
                    }
                }
        }
        .scrollIndicators(contentOverflows ? .visible : .hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .frame(height: viewportHeight, alignment: .top)
    }
}

/// Quiz-mode wrapper around the shared zone-content renderer so questions and choices
/// use the same rich text, math, code, and local-overflow behavior as flashcards.
struct QuizPlaybackZoneContent: View {
    let zone: ZoneModel
    let fontScale: CGFloat
    let availableWidth: CGFloat
    let centersLeafBlocks: Bool
    var alignLeafBlocksToGroupLeading: Bool = false
    var showsZoneSurfaces: Bool = true
    var textVerticalPadding: CGFloat = ZoneContentMetrics.textVerticalPadding
    var textHorizontalPaddingOverride: CGFloat? = nil
    var zoneHighlightStrokeStyle: StrokeStyle = StrokeStyle(lineWidth: 2)
    var showsLayoutDebug: Bool = false
    var onTap: (() -> Void)?
    var onMeasuredWidthChange: ((CGFloat) -> Void)?
    var onLeafDebugSnapshotsChange: (([ZoneContentLeafLayoutDebugSnapshot]) -> Void)?
    var onBlockBoundsChange: (([ZoneContentRenderBlockBounds]) -> Void)?

    var body: some View {
        let width = max(availableWidth, 1)

        ZoneContentRenderView(
            zone: zone,
            fontScale: fontScale,
            availableWidth: width,
            centersLeafBlocks: centersLeafBlocks,
            alignLeafBlocksToGroupLeading: alignLeafBlocksToGroupLeading,
            animatesLayoutChanges: false,
            showsDebugGuides: showsLayoutDebug,
            showsZoneSurfaces: showsZoneSurfaces,
            showsCodeBlockZoneSurfaces: true,
            usesBorderOnlyZoneHighlights: true,
            zoneHighlightStrokeStyle: zoneHighlightStrokeStyle,
            textVerticalPadding: textVerticalPadding,
            textHorizontalPaddingOverride: textHorizontalPaddingOverride,
            collectsDebugMetrics: showsLayoutDebug,
            onTap: onTap,
            onBlockBoundsChange: onBlockBoundsChange,
            onRootBlockWidthChange: onMeasuredWidthChange
        )
        .frame(width: width, alignment: .topLeading)
        .coordinateSpace(name: ZoneContentRenderCoordinateSpace.name)
        .transaction { transaction in
            transaction.animation = nil
        }
        .onPreferenceChange(ZoneContentLeafDebugPreferenceKey.self) { snapshots in
            guard showsLayoutDebug else { return }
            onLeafDebugSnapshotsChange?(snapshots.sorted { $0.path < $1.path })
        }
        .background(alignment: .topLeading) {
            if showsLayoutDebug {
                QuizGridDebugFrame(width: width)
            }
        }
    }
}

struct QuizGridDebugFrame: View {
    let width: CGFloat

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    Color.cyan.opacity(0.9),
                    style: StrokeStyle(lineWidth: 1.6, dash: [7, 5])
                )
                .frame(
                    width: max(width, 1),
                    height: max(proxy.size.height, 1),
                    alignment: .topLeading
                )
                .overlay(alignment: .topLeading) {
                    Text("GRID \(Self.metric(width))x\(Self.metric(proxy.size.height))")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.cyan)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .offset(x: 4, y: 4)
                }
                .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }

    private static func metric(_ value: CGFloat) -> String {
        String(format: "%.0f", ceil(value))
    }
}

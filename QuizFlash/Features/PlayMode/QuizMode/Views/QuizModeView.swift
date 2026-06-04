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
                                settings: deck.playModeSettings?.quizSettings ?? QuizModeSettings()
                            )
                        }
                    }
            }
        }
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

    @State private var headerHeight: CGFloat = 0
    @State private var measuredChoiceZoneWidths: [UUID: CGFloat] = [:]
    @State private var showsQuizLayoutDebug = false
    @State private var showsExplanationSheet = false
    @State private var didCopyQuizLayoutDebug = false
    @State private var editingCard: CardModel?
    @State private var measuredExplanationSheetHeight: CGFloat = 0

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var tintColor: Color { Color(hex: deck.colorHex) ?? ThemeManager.shared.accentColor.color }
    private var contentHorizontalPadding: CGFloat { 8 }
    private var contentTopPadding: CGFloat { 12 }
    private var contentBottomPadding: CGFloat { 12 }
    private var playModeTextScale: CGFloat {
        let textSize = deck.playModeSettings?.flashcardSettings.textSize ?? .large
        return CGFloat(textSize.playModeScale) * appPreferences.cardContentFontScale
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
                } else {
                    VStack(spacing: 0) {
                        header(
                            safeTopInset: resolvedSafeTopInset,
                            horizontalPadding: headerHorizontalPadding
                        )

                        content
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                if showsFloatingQuizControls {
                    quizFloatingControls()
                        .padding(.horizontal, contentHorizontalPadding)
                        .padding(.bottom, max(resolvedSafeBottomInset, UIConstants.Spacing.large))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(25)
                }

                if developmentPreferences.playModeDeveloperModeEnabled {
                    quizLayoutDebugButton
                        .padding(.trailing, contentHorizontalPadding)
                        .padding(.bottom, quizDebugBottomPadding(safeBottomInset: resolvedSafeBottomInset))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .zIndex(30)
                }
            }
            .fullScreenSheetDragActivationHeight(headerHeight)
            .task {
                await viewModel.startSession(container: context.container)
            }
        }
        .fullScreenCover(item: $editingCard) { card in
            NavigationStack {
                CardEditorView(destination: .edit(DraftCard.from(card))) { content in
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
        .onChange(of: viewModel.isComplete) { _, isComplete in
            if isComplete {
                showsExplanationSheet = false
            }
        }
        .onDisappear {
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
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            if abs(headerHeight - newHeight) > 0.5 {
                headerHeight = newHeight
            }
        }
    }

    private var editCurrentQuizButton: some View {
        Button(action: openCurrentQuizEditor) {
            Image(systemName: "pencil")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(ThemeManager.shared.accentColor.color)
                .frame(
                    width: UIConstants.Size.capsuleHeight,
                    height: UIConstants.Size.capsuleHeight
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.currentCard == nil)
        .opacity(viewModel.currentCard == nil ? 0.35 : 1)
        .accessibilityLabel("Edit current quiz")
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
                                Color.white.opacity(0.92)
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
            viewModel.refreshCurrentCard(from: card)
        } catch {
            context.rollback()
            assertionFailure("Failed to save edited quiz card: \(error.localizedDescription)")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            centeredMessageCard(
                icon: "hourglass",
                title: "Preparing Quiz",
                message: "Validating questions and choices before the first question appears."
            )
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
            if viewModel.isShowingRetryPrompt {
                retryPromptCard
            } else if let currentCard = viewModel.currentCard {
                questionFlow(for: currentCard)
            } else {
                centeredMessageCard(
                    icon: "questionmark.circle",
                    title: "Waiting For Question Data",
                    message: "The next quiz question is being prepared."
                )
            }
        }
    }

    private func questionFlow(for card: QuizPlayableCard) -> some View {
        GeometryReader { proxy in
            let screenWidth = max(proxy.size.width, 1)
            let screenHeight = max(proxy.size.height, 1)
            let contentWidth = max(screenWidth - (contentHorizontalPadding * 2), 1)
            let contentHeight = max(screenHeight - contentTopPadding - contentBottomPadding, 1)
            let answerGroupWidth = choiceGroupWidth(availableWidth: contentWidth)

            VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                    QuizPlayZoneContent(
                        zone: card.questionZone,
                        fontScale: playModeTextScale,
                        availableWidth: contentWidth,
                        centersLeafBlocks: true,
                        alignLeafBlocksToGroupLeading: false,
                        showsLayoutDebug: showsQuizLayoutDebug
                    )

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
                    isEvaluated: viewModel.isEvaluated,
                    allowsSelection: !viewModel.isEvaluated || viewModel.lastEvaluationWasCorrect == false,
                    fontScale: playModeTextScale,
                    groupWidth: answerGroupWidth,
                    layoutWidth: contentWidth,
                    showsLayoutDebug: showsQuizLayoutDebug,
                    selectChoice: { viewModel.selectChoice($0) },
                    onMeasuredWidthChange: { choiceID, width in
                        updateMeasuredChoiceWidth(width, for: choiceID)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .quizDebugOutline(
                    isVisible: showsQuizLayoutDebug,
                    color: .green,
                    label: "ANSWERS viewport w=\(Self.metric(contentWidth)) group=\(Self.metric(answerGroupWidth))"
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
                        QuizPlayZoneContent(
                            zone: explanationZone,
                            fontScale: playModeTextScale,
                            availableWidth: contentWidth,
                            centersLeafBlocks: false,
                            alignLeafBlocksToGroupLeading: true,
                            showsLayoutDebug: showsQuizLayoutDebug
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
                    action: { showsExplanationSheet = false },
                    symbolSize: UIConstants.Size.iconStandard
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

    private var retryPromptCard: some View {
        centeredMessageCard(
            icon: "arrow.counterclockwise",
            title: "Main Pass Complete",
            message: "Retry the questions you missed to mirror the flashcards wrong-card flow.",
            bullets: [
                "\(viewModel.firstPassFailedIDs.count) wrong question\(viewModel.firstPassFailedIDs.count == 1 ? "" : "s") queued for retry.",
                "Correct answers in the retry pass earn another full review write."
            ]
        )
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
            if showsExplanationFloatingButton {
                quizExplanationFloatingButton
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Spacer(minLength: UIConstants.Spacing.standard)

            if showsPrimaryFloatingButton {
                quizPrimaryFloatingButton(
                    title: viewModel.primaryActionTitle,
                    systemImage: primaryFloatingSymbol,
                    isDisabled: isPrimaryActionDisabled,
                    action: handlePrimaryAction
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: showsFloatingQuizControls)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: viewModel.isEvaluated)
    }

    private var quizExplanationFloatingButton: some View {
        Button(action: openExplanationSheet) {
            Image(systemName: "lightbulb.max.fill")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.orange)
                .frame(width: 54, height: 54)
                .background {
                    Circle()
                        .fill(Color(white: 0.15))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Explain")
    }

    private func quizPrimaryFloatingButton(
        title: String,
        systemImage: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(isDisabled ? Color.white.opacity(0.42) : .white)
                .lineLimit(1)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background {
                    Capsule(style: .continuous)
                        .fill(primaryFloatingBackground(isDisabled: isDisabled))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(isDisabled ? 0.08 : 0.20), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
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
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
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
            "contentHorizontalPadding: \(Self.metric(contentHorizontalPadding))",
            "contentTopPadding: \(Self.metric(contentTopPadding))",
            "contentBottomPadding: \(Self.metric(contentBottomPadding))",
            "textScale: \(String(format: "%.2f", playModeTextScale))",
            "zoneCornerRadius: \(Self.metric(FlashcardGridContentMetrics.zoneCornerRadius))",
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
            ]
        }

        return lines.joined(separator: "\n")
    }

    private var dismissButton: some View {
        Button(action: dismissSheet) {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .bold))
                .fontDesign(.rounded)
                .foregroundStyle(.primary)
                .frame(width: UIConstants.Size.capsuleHeight, height: UIConstants.Size.capsuleHeight)
        }
        .buttonStyle(.plain)
    }

    private func headerMetric(value: Int, symbol: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(tint)

            Text("\(value)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.94))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
        }
    }

    private var completionOverlay: some View {
        PlayModeCompletionOverlay(
            headline: "Quiz Complete!",
            xpEarned: viewModel.sessionXP,
            stats: [
                PlayModeCompletionStat(title: "Accuracy", value: "\(sessionAccuracy)%", icon: "target", color: .green),
                PlayModeCompletionStat(title: "Correct", value: "\(viewModel.correctCount)", icon: "checkmark.circle.fill", color: .green),
                PlayModeCompletionStat(title: "Wrong", value: "\(viewModel.wrongCount)", icon: "xmark.circle.fill", color: .red),
                PlayModeCompletionStat(title: "Retry Pass", value: "\(viewModel.retryPassCount)", icon: "arrow.counterclockwise", color: .orange),
                PlayModeCompletionStat(title: "Skipped", value: "\(viewModel.diagnostics.skippedInvalidCount)", icon: "text.badge.xmark", color: .red),
                PlayModeCompletionStat(title: "Time", value: viewModel.formattedSessionDuration, icon: "timer", color: .blue)
            ],
            primaryActionTitle: "Continue",
            primaryAction: dismissSheet,
            secondaryActionTitle: nil,
            secondaryAction: nil
        )
    }

    private var showsFloatingQuizControls: Bool {
        showsPrimaryFloatingButton || showsExplanationFloatingButton
    }

    private var showsPrimaryFloatingButton: Bool {
        switch viewModel.loadState {
        case .ready:
            return viewModel.isShowingRetryPrompt || viewModel.requiresSubmitAction || didAnswerCorrectly
        default:
            return false
        }
    }

    private var showsExplanationFloatingButton: Bool {
        didAnswerCorrectly && viewModel.currentCard?.explanationZone != nil
    }

    private var isPrimaryActionDisabled: Bool {
        if viewModel.isShowingRetryPrompt { return false }
        if viewModel.isEvaluated { return false }
        return !viewModel.canSubmitAnswer
    }

    private var primaryFloatingSymbol: String {
        if viewModel.isShowingRetryPrompt { return "arrow.counterclockwise" }
        if viewModel.isEvaluated { return "arrow.right" }
        return "checkmark"
    }

    private var primaryFloatingTint: Color {
        if viewModel.isShowingRetryPrompt { return .orange }
        if viewModel.isEvaluated { return ThemeManager.shared.accentColor.color }
        return .green
    }

    private var didAnswerCorrectly: Bool {
        viewModel.isEvaluated && viewModel.lastEvaluationWasCorrect == true
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
            "Single-answer cards must have exactly 1 correct choice."
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
            showsExplanationSheet = false
            viewModel.advance()
            return
        }

        guard viewModel.currentCard != nil else { return }

        if !viewModel.isEvaluated {
            viewModel.submitAnswer()
        } else {
            showsExplanationSheet = false
            viewModel.advance()
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

    private func dismissSheet() {
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            dismiss()
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
private struct QuizAnswerList: View {
    let choices: [QuizChoiceDraft]
    let selectedChoiceIDs: Set<UUID>
    let incorrectChoiceIDs: Set<UUID>
    let isEvaluated: Bool
    let allowsSelection: Bool
    let fontScale: CGFloat
    let groupWidth: CGFloat
    let layoutWidth: CGFloat
    let showsLayoutDebug: Bool
    let selectChoice: (UUID) -> Void
    let onMeasuredWidthChange: (UUID, CGFloat) -> Void

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let viewportHeight = max(ceil(proxy.size.height), 1)
            let needsScroll = contentHeight > viewportHeight + 1
            let groupLeadingInset = max((layoutWidth - groupWidth) / 2, 0)

            ScrollView(.vertical, showsIndicators: needsScroll) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.extraLarge) {
                    ForEach(choices) { choice in
                        QuizChoiceRow(
                            choice: choice,
                            isSelected: selectedChoiceIDs.contains(choice.id),
                            isMarkedWrong: incorrectChoiceIDs.contains(choice.id),
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
                            }
                        )
                    }
                }
                .frame(width: layoutWidth, alignment: .topLeading)
                .offset(x: groupLeadingInset)
                .frame(width: layoutWidth, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    ceil(proxy.size.height)
                } action: { newHeight in
                    updateContentHeight(newHeight)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: needsScroll ? nil : viewportHeight,
                    alignment: needsScroll ? .top : .center
                )
                .padding(.bottom, needsScroll ? UIConstants.Spacing.large : 0)
                .quizDebugOutline(
                    isVisible: showsLayoutDebug,
                    color: .pink,
                    label: "ANSWER CONTENT h=\(Self.metric(contentHeight)) scroll=\(needsScroll.description)"
                )
            }
            .scrollDisabled(!needsScroll)
            .quizDebugOutline(
                isVisible: showsLayoutDebug,
                color: needsScroll ? .red : .green,
                label: "ANSWER VIEWPORT \(Self.metric(groupWidth))x\(Self.metric(viewportHeight)) contentH=\(Self.metric(contentHeight))"
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

/// One authored quiz choice row with immediate correctness styling after evaluation.
private struct QuizChoiceRow: View {
    let choice: QuizChoiceDraft
    let isSelected: Bool
    let isMarkedWrong: Bool
    let isEvaluated: Bool
    let isCorrect: Bool
    let allowsSelection: Bool
    let fontScale: CGFloat
    let groupWidth: CGFloat
    let layoutWidth: CGFloat
    let showsLayoutDebug: Bool
    let action: () -> Void
    let onMeasuredWidthChange: (CGFloat) -> Void

    @State private var lastTapTime: TimeInterval = 0
    @State private var measuredContentWidth: CGFloat = 0
    @State private var wrongWiggleOffset: CGFloat = 0
    @State private var wrongScale: CGFloat = 1

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            QuizPlayZoneContent(
                zone: displayZone,
                fontScale: fontScale,
                availableWidth: choiceContentWidth,
                centersLeafBlocks: false,
                alignLeafBlocksToGroupLeading: true,
                showsLayoutDebug: showsLayoutDebug,
                onTap: handleTap,
                onMeasuredWidthChange: updateMeasuredContentWidth
            )

            Spacer(minLength: 0)
        }
        .frame(width: layoutWidth, alignment: .topLeading)
        .contentShape(Rectangle())
        .simultaneousGesture(
            SpatialTapGesture()
                .onEnded { value in
                    guard value.location.x <= tappableZoneWidth else { return }
                    handleTap()
                }
        )
        .allowsHitTesting(allowsSelection)
        .opacity(isEvaluated || isSelected ? 1 : 0.98)
        .offset(x: wrongWiggleOffset)
        .scaleEffect(wrongFeedback ? wrongScale : 1, anchor: .leading)
        .zIndex(correctFeedback ? 1 : 0)
        .onChange(of: wrongFeedback) { _, isActive in
            if isActive {
                runWrongFeedbackSequence()
            } else {
                wrongScale = 1
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isSelected)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isEvaluated)
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: correctFeedback)
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
        let zoneHorizontalPadding = FlashcardGridContentMetrics.textHorizontalPadding
        return min(ceil(widestLine + codeInternalPadding + zoneHorizontalPadding), layoutWidth)
    }

    private func codeAnswerFontSize(for zone: ZoneModel) -> CGFloat {
        baseFontSize(for: zone) * fontScale * CodeSnippetMetrics.relativeFontScale
    }

    private func baseFontSize(for zone: ZoneModel) -> CGFloat {
        switch zone.textStyle {
        case .caption: return 16
        case .body: return 22
        case .headline: return 26
        case .title: return 32
        }
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
        wrongScale = 1
        wrongWiggleOffset = 0
        withAnimation(.linear(duration: 0.065).repeatCount(5, autoreverses: true)) {
            wrongWiggleOffset = 8
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 390_000_000)
            withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) {
                wrongWiggleOffset = 0
            }
            withAnimation(.smooth(duration: 0.22, extraBounce: 0)) {
                wrongScale = 0.9
            }
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

    private var choiceContentWidth: CGFloat {
        max(layoutWidth, 1)
    }

    private var tappableZoneWidth: CGFloat {
        let measuredWidth = measuredContentWidth > 0 ? measuredContentWidth : groupWidth
        return max(min(measuredWidth, layoutWidth), 1)
    }

    private static func metric(_ value: CGFloat) -> String {
        String(format: "%.0f", ceil(value))
    }
}

// MARK: - QuizPlayZoneContent

/// Quiz-mode wrapper around the flashcard grid renderer so questions and choices
/// use the same rich text, math, code, and local-overflow behavior as flashcards.
private struct QuizPlayZoneContent: View {
    let zone: ZoneModel
    let fontScale: CGFloat
    let availableWidth: CGFloat
    let centersLeafBlocks: Bool
    var alignLeafBlocksToGroupLeading: Bool = false
    var showsLayoutDebug: Bool = false
    var onTap: (() -> Void)?
    var onMeasuredWidthChange: ((CGFloat) -> Void)?

    var body: some View {
        let width = max(availableWidth, 1)

        FlashcardGridFaceView(
            zone: zone,
            fontScale: fontScale,
            availableWidth: width,
            centersLeafBlocks: centersLeafBlocks,
            alignLeafBlocksToGroupLeading: alignLeafBlocksToGroupLeading,
            showsDebugGuides: showsLayoutDebug,
            showsZoneSurfaces: true,
            showsCodeBlockZoneSurfaces: true,
            usesBorderOnlyZoneHighlights: true,
            collectsDebugMetrics: showsLayoutDebug,
            onTap: onTap,
            onRootBlockWidthChange: onMeasuredWidthChange
        )
            .frame(width: width, alignment: .topLeading)
            .background(alignment: .topLeading) {
                if showsLayoutDebug {
                    QuizGridDebugFrame(width: width)
                }
            }
    }
}

private struct QuizGridDebugFrame: View {
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

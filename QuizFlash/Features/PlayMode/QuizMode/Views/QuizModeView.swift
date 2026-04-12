//
//  QuizModeView.swift
//  QuizFlash
//
//  One-question-at-a-time multiple-choice gameplay runtime.
//

import SwiftUI
import SwiftData

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

    let deck: DeckModel
    let safeAreaInsets: UIEdgeInsets
    let availability: PlayModeCardAvailability

    @Bindable var viewModel: QuizModeViewModel

    @State private var headerHeight: CGFloat = 0

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var tintColor: Color { Color(hex: deck.colorHex) ?? ThemeManager.shared.accentColor.color }

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
                            .padding(.horizontal, isCompact ? 16 : 32)
                            .padding(.top, UIConstants.Spacing.medium)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if showsBottomCTA {
                            bottomCTA
                                .padding(.horizontal, isCompact ? 16 : 32)
                                .padding(.top, UIConstants.Spacing.medium)
                                .padding(.bottom, max(resolvedSafeBottomInset, UIConstants.Spacing.large))
                        }
                    }
                }
            }
            .fullScreenSheetDragActivationHeight(headerHeight)
            .task {
                await viewModel.startSession(container: context.container)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear {
            viewModel.tearDown()
        }
    }

    private func header(safeTopInset: CGFloat, horizontalPadding: CGFloat) -> some View {
        PlayModeSessionHeader(
            deckTitle: viewModel.resolvedDeckTitle,
            subtitle: headerSubtitle,
            progressLabel: viewModel.progressLabel,
            progressFraction: viewModel.progressFraction,
            safeTopInset: safeTopInset,
            horizontalPadding: horizontalPadding,
            measuredHeight: $headerHeight
        ) {
            HStack(spacing: UIConstants.Spacing.medium) {
                headerMetric(value: viewModel.correctCount, symbol: "checkmark.circle.fill", tint: .green)
                headerMetric(value: viewModel.wrongCount, symbol: "xmark.circle.fill", tint: .red)
            }
        } trailing: {
            dismissButton
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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                PlayModeContentCard(cornerRadius: UIConstants.Radius.maximum) {
                    Text("QUESTION")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)

                    CardFaceView(zone: card.questionZone)
                }

                PlayModeContentCard {
                    Text(answerInstruction(for: card))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: UIConstants.Spacing.small) {
                        ForEach(card.choices) { choice in
                            QuizChoiceRow(
                                choice: choice,
                                isSelected: viewModel.selectedChoiceIDs.contains(choice.id),
                                isEvaluated: viewModel.isEvaluated,
                                isCorrect: choice.isCorrect,
                                action: { viewModel.selectChoice(choice.id) }
                            )
                        }
                    }
                }

                if viewModel.shouldShowExplanation, let explanationZone = card.explanationZone {
                    PlayModeContentCard {
                        Text("EXPLANATION")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)

                        CardFaceView(zone: explanationZone)
                    }
                } else if viewModel.isEvaluated,
                          card.explanationZone != nil,
                          viewModel.settings.explanationTiming == .manualReveal {
                    Button(action: viewModel.revealExplanation) {
                        Label("Reveal Explanation", systemImage: "text.append")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tintColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, UIConstants.Spacing.standard)
                            .background(
                                tintColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, UIConstants.Spacing.large)
        }
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

    private var bottomCTA: some View {
        Button(action: handlePrimaryAction) {
            Text(viewModel.primaryActionTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, UIConstants.Spacing.standard)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: UIConstants.Radius.card))
                .foregroundStyle(.white)
                .shadow(color: Color.accentColor.opacity(0.3), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(isPrimaryActionDisabled)
        .opacity(isPrimaryActionDisabled ? 0.45 : 1)
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

    private var showsBottomCTA: Bool {
        switch viewModel.loadState {
        case .ready:
            return viewModel.isShowingRetryPrompt || viewModel.isEvaluated || viewModel.requiresSubmitAction
        default:
            return false
        }
    }

    private var isPrimaryActionDisabled: Bool {
        if viewModel.isShowingRetryPrompt { return false }
        if viewModel.isEvaluated { return false }
        return !viewModel.canSubmitAnswer
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
            default:
                return nil
            }
        }

        bullets.append(contentsOf: reasonSummaries)
        return bullets
    }

    private func handlePrimaryAction() {
        if viewModel.isShowingRetryPrompt {
            viewModel.advance()
            return
        }

        guard viewModel.currentCard != nil else { return }

        if !viewModel.isEvaluated {
            viewModel.submitAnswer()
        } else {
            viewModel.advance()
        }
    }

    private func answerInstruction(for card: QuizPlayableCard) -> String {
        if card.allowsMultipleCorrect {
            return "Select every correct answer, then submit."
        }

        return viewModel.settings.answerValidation == .instantCheck
            ? "Tap one answer to check it immediately."
            : "Select one answer, then submit."
    }

    private func dismissSheet() {
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            dismiss()
        }
    }
}

// MARK: - QuizChoiceRow

/// One authored quiz choice row with immediate correctness styling after evaluation.
private struct QuizChoiceRow: View {
    let choice: QuizChoiceDraft
    let isSelected: Bool
    let isEvaluated: Bool
    let isCorrect: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                ZStack {
                    Circle()
                        .fill(badgeBackground)
                        .frame(width: 28, height: 28)

                    Image(systemName: badgeSymbol)
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(badgeForeground)
                }

                CardFaceView(zone: choice.contentZone)

                Spacer(minLength: 0)
            }
            .padding(UIConstants.Spacing.medium)
            .background(background)
            .overlay {
                RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                    .stroke(borderColor, lineWidth: isSelected || isEvaluated ? 1.25 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isEvaluated)
        .opacity(isEvaluated || isSelected ? 1 : 0.98)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isSelected)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isEvaluated)
    }

    private var background: some ShapeStyle {
        if isEvaluated {
            if isCorrect {
                return AnyShapeStyle(Color.green.opacity(0.18))
            }
            if isSelected {
                return AnyShapeStyle(Color.red.opacity(0.16))
            }
        } else if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.16))
        }

        return AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
    }

    private var borderColor: Color {
        if isEvaluated {
            if isCorrect { return .green.opacity(0.75) }
            if isSelected { return .red.opacity(0.65) }
        }

        return isSelected ? Color.accentColor.opacity(0.75) : Color.white.opacity(0.08)
    }

    private var badgeBackground: Color {
        if isEvaluated {
            if isCorrect { return .green.opacity(0.2) }
            if isSelected { return .red.opacity(0.18) }
        }

        return isSelected ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.08)
    }

    private var badgeForeground: Color {
        if isEvaluated {
            if isCorrect { return .green }
            if isSelected { return .red }
        }

        return isSelected ? .accentColor : .secondary
    }

    private var badgeSymbol: String {
        if isEvaluated {
            if isCorrect { return "checkmark" }
            if isSelected { return "xmark" }
        }

        return isSelected ? "checkmark" : "circle.fill"
    }
}

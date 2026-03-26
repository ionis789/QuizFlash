//
//  WriteModeView.swift
//  QuizFlash
//
//  Anchored-blank manual recall gameplay runtime.
//

import SwiftUI
import SwiftData

// MARK: - Write Mode View

/// Lazy wrapper that avoids initializing the write view model inside the full-screen cover path.
struct WriteModeView: View {
    @Environment(ThemeManager.self) private var themeManager

    let deck: DeckModel
    let safeAreaInsets: UIEdgeInsets
    let availability: PlayModeCardAvailability

    @State private var viewModel: WriteModeViewModel?

    var body: some View {
        Group {
            if let viewModel {
                WriteModeSessionView(
                    deck: deck,
                    safeAreaInsets: safeAreaInsets,
                    availability: availability,
                    viewModel: viewModel
                )
            } else {
                themeManager.screenBackground
                    .onAppear {
                        if viewModel == nil {
                            viewModel = WriteModeViewModel(
                                deck: deck,
                                settings: deck.playModeSettings?.writeSettings ?? WriteModeSettings()
                            )
                        }
                    }
            }
        }
    }
}

// MARK: - WriteModeSessionView

/// Interactive write-mode surface with anchored blank rendering and a later retry pass.
private struct WriteModeSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var context

    let deck: DeckModel
    let safeAreaInsets: UIEdgeInsets
    let availability: PlayModeCardAvailability

    @Bindable var viewModel: WriteModeViewModel

    @State private var headerHeight: CGFloat = 0
    @FocusState private var isInputFocused: Bool

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var tintColor: Color { ThemeManager.shared.accentColor.color }

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
        .task(id: focusToken) {
            guard shouldFocusInput else { return }
            try? await Task.sleep(for: .milliseconds(150))
            guard shouldFocusInput else { return }
            isInputFocused = true
        }
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
                title: "Preparing Write Mode",
                message: "Validating anchored blanks and building prompt strings before the first recall check."
            )
        case .empty:
            centeredMessageCard(
                icon: "pencil.and.scribble",
                title: "No Write Cards Yet",
                message: "This deck needs write cards before Write mode can start."
            )
        case .invalid:
            centeredMessageCard(
                icon: "rectangle.and.pencil.and.ellipsis",
                title: "Write Cards Need Valid Blanks",
                message: "Write mode found cards of the right type, but all of them failed runtime validation.",
                bullets: invalidBullets
            )
        case .failed:
            centeredMessageCard(
                icon: "exclamationmark.triangle.fill",
                title: "Write Mode Unavailable",
                message: viewModel.errorMessage.isEmpty ? "The write session couldn't be prepared right now." : viewModel.errorMessage
            )
        case .ready:
            if viewModel.isShowingRetryPrompt {
                retryPromptCard
            } else if let currentPrompt = viewModel.currentPrompt {
                promptFlow(for: currentPrompt)
            } else {
                centeredMessageCard(
                    icon: "pencil.line",
                    title: "Waiting For Prompt Data",
                    message: "The next write prompt is being prepared."
                )
            }
        }
    }

    private func promptFlow(for prompt: WritePlayableCard) -> some View {
        let resolvedInputMode = viewModel.resolvedInputMode(for: prompt)

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                PlayModeContentCard(cornerRadius: UIConstants.Radius.maximum) {
                    Text("PROMPT")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)

                    anchoredPromptView(for: prompt)
                }

                PlayModeContentCard {
                    Text(answerEntryTitle(for: resolvedInputMode))
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)

                    if resolvedInputMode == .assistedBuilder {
                        assistedBuilderInput(for: prompt)
                    } else {
                        TextField("Enter the missing text", text: $viewModel.currentInput, axis: .vertical)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .padding(UIConstants.Spacing.standard)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: UIConstants.Radius.card))
                            .focused($isInputFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .submitLabel(.done)
                            .disabled(viewModel.isEvaluated)
                            .onSubmit {
                                guard viewModel.canCheckAnswer else { return }
                                isInputFocused = false
                                viewModel.checkAnswer()
                            }
                    }

                    if viewModel.isEvaluated {
                        feedbackCard(isCorrect: viewModel.lastCheckWasCorrect == true)
                        if !viewModel.shouldShowCanonicalAnswer {
                            Button(action: viewModel.revealAnswer) {
                                Label("Reveal Stored Answer", systemImage: "eye")
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
                    } else {
                        Text(inputFootnote(for: resolvedInputMode))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.bottom, UIConstants.Spacing.large)
        }
    }

    private var retryPromptCard: some View {
        centeredMessageCard(
            icon: "arrow.counterclockwise",
            title: "Main Pass Complete",
            message: "Retry the prompts you missed. Wrong retry answers do not loop immediately in v1.",
            bullets: [
                "\(viewModel.firstPassFailedIDs.count) prompt\(viewModel.firstPassFailedIDs.count == 1 ? "" : "s") queued for retry.",
                "Correct retry answers earn one additional full review write."
            ]
        )
    }

    private func feedbackCard(isCorrect: Bool) -> some View {
        HStack(spacing: UIConstants.Spacing.small) {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isCorrect ? Color.green : Color.red)

            Text(isCorrect ? "Correct. The typed answer matches the stored blank." : "Not a match. Reveal the stored answer to see it restored directly inside the prompt.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, UIConstants.Spacing.standard)
        .padding(.vertical, UIConstants.Spacing.small)
        .background((isCorrect ? Color.green : Color.red).opacity(0.12), in: RoundedRectangle(cornerRadius: UIConstants.Radius.card))
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
            Text(primaryActionTitle)
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
                .glassButton(shape: .circle)
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
            headline: "Write Complete!",
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
            return viewModel.currentPrompt != nil || viewModel.isShowingRetryPrompt
        default:
            return false
        }
    }

    private var primaryActionTitle: String {
        if viewModel.isShowingRetryPrompt { return "Retry Wrong Prompts" }
        return viewModel.isEvaluated ? "Continue" : "Check"
    }

    private var isPrimaryActionDisabled: Bool {
        if viewModel.isShowingRetryPrompt { return false }
        return viewModel.isEvaluated ? false : !viewModel.canCheckAnswer
    }

    private var headerSubtitle: String {
        if viewModel.isShowingRetryPrompt {
            return "MAIN PASS COMPLETE"
        }
        return viewModel.isRetryPass ? "RETRY PASS" : "WRITE"
    }

    private var sessionAccuracy: Int {
        let totalAnswers = viewModel.correctCount + viewModel.wrongCount
        guard totalAnswers > 0 else { return 0 }
        return Int((Double(viewModel.correctCount) / Double(totalAnswers)) * 100)
    }

    private var invalidBullets: [String] {
        var bullets = [
            "Source text required.",
            "Stored omitted text required.",
            "The saved UTF-16 blank anchor must still match the current source text."
        ]

        let reasonSummaries = viewModel.diagnostics.nonZeroReasonCounts.compactMap { reason, count -> String? in
            switch reason {
            case .missingSourceText:
                return "\(count) card\(count == 1 ? "" : "s") had empty source text."
            case .missingOmittedText:
                return "\(count) card\(count == 1 ? "" : "s") had no stored omitted text."
            case .invalidBlankAnchor:
                return "\(count) card\(count == 1 ? "" : "s") had a blank anchor that no longer matched the source text."
            default:
                return nil
            }
        }

        bullets.append(contentsOf: reasonSummaries)
        return bullets
    }

    private var focusToken: String {
        guard let prompt = viewModel.currentPrompt else { return "none" }
        return "\(prompt.id)-\(viewModel.isEvaluated)-\(viewModel.currentInput)"
    }

    private var shouldFocusInput: Bool {
        guard let prompt = viewModel.currentPrompt else { return false }
        return viewModel.resolvedInputMode(for: prompt) == .freeText &&
        !viewModel.isEvaluated &&
        !viewModel.isShowingRetryPrompt &&
        viewModel.loadState == .ready
    }

    private func handlePrimaryAction() {
        if viewModel.isShowingRetryPrompt {
            viewModel.advance()
            return
        }

        if viewModel.isEvaluated {
            viewModel.advance()
            return
        }

        guard viewModel.canCheckAnswer else { return }
        isInputFocused = false
        viewModel.checkAnswer()
    }

    private func dismissSheet() {
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            dismiss()
        }
    }

    private func answerEntryTitle(for inputMode: WriteAnswerInputMode) -> String {
        switch inputMode {
        case .auto, .freeText:
            return "TYPE THE MISSING TEXT"
        case .assistedBuilder:
            return "BUILD THE MISSING TEXT"
        }
    }

    private func inputFootnote(for inputMode: WriteAnswerInputMode) -> String {
        switch inputMode {
        case .auto, .freeText:
            return viewModel.settings.strictness == .exact
                ? "Exact matching is enabled for this deck. Check becomes available once the input is not empty."
                : "Normalized matching is enabled for this deck. Check becomes available once the input is not empty."
        case .assistedBuilder:
            return "Tap segments in order to rebuild the omitted answer. Use Backspace or Clear to adjust the response."
        }
    }

    private func assistedBuilderInput(for prompt: WritePlayableCard) -> some View {
        let segments = WriteBlankTextHelper.assistedBuilderSegments(for: prompt.omittedText)

        return VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                Text(viewModel.currentInput.isEmpty ? "Build the answer from the segments below." : viewModel.currentInput)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(viewModel.currentInput.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(UIConstants.Spacing.standard)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: UIConstants.Radius.card))

                HStack(spacing: UIConstants.Spacing.small) {
                    Button("Backspace") {
                        viewModel.removeLastBuilderSegment()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.currentInput.isEmpty || viewModel.isEvaluated)

                    Button("Clear") {
                        viewModel.clearBuilderInput()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.currentInput.isEmpty || viewModel.isEvaluated)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: UIConstants.Spacing.small)], spacing: UIConstants.Spacing.small) {
                ForEach(Array(segments.enumerated()), id: \.offset) { item in
                    let segment = item.element
                    Button(action: {
                        viewModel.appendBuilderSegment(segment)
                    }) {
                        Text(segmentLabel(for: segment))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, UIConstants.Spacing.standard)
                            .padding(.vertical, UIConstants.Spacing.small)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isEvaluated)
                }
            }
        }
    }

    private func segmentLabel(for segment: String) -> String {
        if segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Space"
        }
        return segment
    }

    @ViewBuilder
    private func anchoredPromptView(for prompt: WritePlayableCard) -> some View {
        if MathTextSanitizer.needsRichPreview(prompt.sourceText) {
            MixedMathTextView(
                text: viewModel.shouldShowCanonicalAnswer ? prompt.sourceText : prompt.blankedPrompt,
                fontSize: 22,
                textColor: .primary,
                alignment: .leading,
                isInteractive: false,
                allowsReadOnlyOverflowScrolling: true
            )
        } else {
            inlineAnchoredPrompt(for: prompt)
        }
    }

    private func inlineAnchoredPrompt(for prompt: WritePlayableCard) -> some View {
        let blankDisplay = viewModel.shouldShowCanonicalAnswer ? prompt.omittedText : "____"
        let blankTint = viewModel.shouldShowCanonicalAnswer ? tintColor : Color.primary
        let underlineTint = viewModel.shouldShowCanonicalAnswer ? tintColor : Color.secondary

        return (
            Text(prompt.prefixText) +
            Text(blankDisplay)
                .fontWeight(.black)
                .foregroundStyle(blankTint)
                .underline(true, color: underlineTint) +
            Text(prompt.suffixText)
        )
        .font(.system(size: 22, weight: .medium, design: .rounded))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

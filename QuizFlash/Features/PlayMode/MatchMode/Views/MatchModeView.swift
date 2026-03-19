//
//  MatchModeView.swift
//  QuizFlash
//
//  Preview-based prompt and answer matching runtime.
//

import SwiftUI
import SwiftData

// MARK: - Match Mode View

/// Lazy wrapper that avoids initializing the heavy match view model in the full-screen cover path.
struct MatchModeView: View {
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
                Color(uiColor: .systemBackground)
                    .onAppear {
                        if viewModel == nil {
                            viewModel = MatchModeViewModel(deck: deck)
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var context

    let deck: DeckModel
    let safeAreaInsets: UIEdgeInsets
    let availability: PlayModeCardAvailability

    @Bindable var viewModel: MatchModeViewModel

    @State private var headerHeight: CGFloat = 0

    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let resolvedSafeTopInset = max(safeAreaInsets.top, geo.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)
            let headerHorizontalPadding: CGFloat = isCompact ? 20 : 32
            let headerBottomPadding: CGFloat = isCompact ? 18 : 28
            let roundCapacity = isCompact && !isLandscape ? 6 : 8

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
                        .padding(.bottom, headerBottomPadding)

                        content(geo: geo)
                            .padding(.horizontal, isCompact ? 16 : (isLandscape ? geo.size.width * 0.10 : 32))
                            .padding(.bottom, max(resolvedSafeBottomInset, UIConstants.Spacing.large))
                    }
                }
            }
            .fullScreenSheetDragActivationHeight(headerHeight)
            .task(id: roundCapacity) {
                await viewModel.startSession(
                    container: context.container,
                    roundCapacity: roundCapacity
                )
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
            subtitle: viewModel.roundLabel,
            progressLabel: viewModel.progressLabel,
            progressFraction: viewModel.progressFraction,
            safeTopInset: safeTopInset,
            horizontalPadding: horizontalPadding,
            measuredHeight: $headerHeight
        ) {
            HStack(spacing: UIConstants.Spacing.medium) {
                headerMetric(value: viewModel.totalMatchedCount, symbol: "checkmark.circle.fill", tint: .green)
                headerMetric(value: viewModel.totalMismatchCount, symbol: "xmark.circle.fill", tint: .orange)
            }
        } trailing: {
            dismissButton
        }
    }

    @ViewBuilder
    private func content(geo: GeometryProxy) -> some View {
        switch viewModel.loadState {
        case .idle, .loading:
            centeredStateCard(
                icon: "hourglass",
                title: "Preparing Match",
                message: "Building preview-text pairs and chunking the deck into round-sized boards."
            )
        case .empty:
            centeredStateCard(
                icon: "rectangle.stack.badge.minus",
                title: "No Match Cards Yet",
                message: "This deck needs flashcards before Match can build prompt-and-answer pairs."
            )
        case .invalid:
            centeredStateCard(
                icon: "text.badge.xmark",
                title: "Match Needs Readable Previews",
                message: "Flashcards exist for this deck, but Match v1 only works when both sides can produce readable preview text.",
                bullets: matchInvalidBullets
            )
        case .failed:
            centeredStateCard(
                icon: "exclamationmark.triangle.fill",
                title: "Match Unavailable",
                message: viewModel.errorMessage.isEmpty ? "The match session couldn't be prepared right now." : viewModel.errorMessage
            )
        case .ready:
            if let activeRound = viewModel.activeRound {
                matchBoard(for: activeRound, availableSize: geo.size)
            } else {
                centeredStateCard(
                    icon: "square.grid.2x2.fill",
                    title: "Waiting For Round Data",
                    message: "The next board is being prepared."
                )
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

    private func matchBoard(for round: MatchRoundState, availableSize: CGSize) -> some View {
        let lookup = Dictionary(uniqueKeysWithValues: round.pairs.map { ($0.id, $0) })
        let activePromptIDs = round.promptOrder.filter { !viewModel.matchedIDs.contains($0) }
        let activeAnswerIDs = round.answerOrder.filter { !viewModel.matchedIDs.contains($0) }
        let laneCount = max(activePromptIDs.count, 1)
        let laneSpacing = UIConstants.Spacing.small
        let totalSpacing = CGFloat(max(0, laneCount - 1)) * laneSpacing
        let approximateHeader: CGFloat = viewModel.isRetryRound ? 70 : 42
        let availableHeight = max(260, availableSize.height - headerHeight - approximateHeader - 40)
        let tileHeight = max(54, min(92, (availableHeight - totalSpacing) / CGFloat(max(laneCount, 1))))

        return VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            if viewModel.isRetryRound {
                retryRoundBanner
            }

            HStack(alignment: .top, spacing: UIConstants.Spacing.small) {
                VStack(spacing: laneSpacing) {
                    ForEach(activePromptIDs, id: \.self) { id in
                        if let pair = lookup[id] {
                            MatchTileButton(
                                text: pair.promptPreview,
                                tint: .blue,
                                isSelected: viewModel.selectedPromptID == id,
                                isMismatch: viewModel.mismatchPromptID == id,
                                mismatchToken: viewModel.mismatchAnimationToken,
                                height: tileHeight,
                                action: { viewModel.selectPrompt(id) }
                            )
                        }
                    }
                }

                VStack(spacing: laneSpacing) {
                    ForEach(activeAnswerIDs, id: \.self) { id in
                        if let pair = lookup[id] {
                            MatchTileButton(
                                text: pair.answerPreview,
                                tint: .green,
                                isSelected: viewModel.selectedAnswerID == id,
                                isMismatch: viewModel.mismatchAnswerID == id,
                                mismatchToken: viewModel.mismatchAnimationToken,
                                height: tileHeight,
                                action: { viewModel.selectAnswer(id) }
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var retryRoundBanner: some View {
        Text("Resolve the missed pairs from this round before the next chunk.")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, UIConstants.Spacing.medium)
            .padding(.vertical, UIConstants.Spacing.small)
            .background(Color.orange.opacity(0.14), in: Capsule())
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
        var bullets = ["Match v1 only keeps flashcards whose question and answer can both render as readable text previews."]

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
}

// MARK: - MatchTileButton

/// One prompt or answer tile inside the match board.
private struct MatchTileButton: View {
    let text: String
    let tint: Color
    let isSelected: Bool
    let isMismatch: Bool
    let mismatchToken: Int
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
                .padding(.horizontal, UIConstants.Spacing.medium)
                .background(background)
                .overlay {
                    RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                        .stroke(borderColor, lineWidth: isSelected || isMismatch ? 1.5 : 1)
                }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 0.98 : 1)
        .modifier(
            MatchShakeEffect(animatableData: isMismatch ? CGFloat(mismatchToken) : 0)
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isSelected)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isMismatch)
    }

    private var background: some ShapeStyle {
        if isMismatch {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.orange.opacity(0.28), Color.red.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        if isSelected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [tint.opacity(0.26), tint.opacity(0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
    }

    private var borderColor: Color {
        if isMismatch { return .red.opacity(0.7) }
        if isSelected { return tint.opacity(0.65) }
        return Color.white.opacity(0.08)
    }
}

// MARK: - MatchShakeEffect

/// Lightweight horizontal shake used when the player mismatches a prompt and answer.
private struct MatchShakeEffect: GeometryEffect {
    var travelDistance: CGFloat = 7
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = travelDistance * sin(animatableData * .pi * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

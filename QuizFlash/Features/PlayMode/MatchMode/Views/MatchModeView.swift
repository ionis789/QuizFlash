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

    let deck: DeckModel
    let safeAreaInsets: UIEdgeInsets
    let availability: PlayModeCardAvailability

    @Bindable var viewModel: MatchModeViewModel

    @State private var headerHeight: CGFloat = 0
    @State private var mismatchHapticTask: Task<Void, Never>?

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var topSheetCornerRadius: CGFloat {
        fullScreenSheetDragProgress > 0.001 ? 50 : 0
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let resolvedSafeTopInset = max(safeAreaInsets.top, geo.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)
            let headerHorizontalPadding: CGFloat = isCompact ? 14 : 24
            let headerBottomPadding: CGFloat = isCompact ? 10 : 18
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

                    header(
                        safeTopInset: resolvedSafeTopInset,
                        horizontalPadding: headerHorizontalPadding
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
            .fullScreenSheetDragActivationHeight(headerHeight)
            .task(id: roundCapacity) {
                await viewModel.startSession(
                    container: context.container,
                    roundCapacity: roundCapacity
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
            mismatchHapticTask?.cancel()
            viewModel.tearDown()
        }
    }

    private func header(safeTopInset: CGFloat, horizontalPadding: CGFloat) -> some View {
        MatchSessionHeader(
            deckTitle: viewModel.resolvedDeckTitle,
            roundLabel: viewModel.roundLabel,
            progressLabel: viewModel.progressLabel,
            progressFraction: viewModel.progressFraction,
            matchedCount: viewModel.totalMatchedCount,
            mismatchCount: viewModel.totalMismatchCount,
            isRetryRound: viewModel.isRetryRound,
            safeTopInset: safeTopInset,
            horizontalPadding: horizontalPadding,
            measuredHeight: $headerHeight
        ) {
            dismissButton
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
        let boardSpacing = isCompact ? 8.0 : 12.0
        let tileMinHeight = viewModel.settings.contentDensity == .compact ? 86.0 : 100.0

        return GeometryReader { boardGeo in
            let laneHeight = max(0, boardGeo.size.height)

            ZStack {
                HStack(alignment: .top, spacing: boardSpacing) {
                    matchLane(height: laneHeight, topInset: topContentInset) {
                        ForEach(viewModel.remainingPromptPairs) { pair in
                            MatchTileButton(
                                content: pair.promptContent,
                                accent: .blue,
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

                    Color.white.opacity(0.1)
                        .frame(width: 1)
                        .padding(.top, topContentInset + 6)
                        .padding(.bottom, 6)
                        .frame(maxHeight: .infinity, alignment: .top)

                    matchLane(height: laneHeight, topInset: topContentInset) {
                        ForEach(viewModel.remainingAnswerPairs) { pair in
                            MatchTileButton(
                                content: pair.answerContent,
                                accent: .green,
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
            LazyVStack(spacing: 6) {
                content()
            }
            .padding(.top, topInset)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: height, alignment: .top)
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

// MARK: - MatchTileButton

/// One prompt or answer tile inside the match board.
private struct MatchTileButton: View {
    let content: MatchPlayableSideContent
    let accent: Color
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
            RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                .fill(background)
        }
        .overlay {
            RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
        .contentShape(RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
        .simultaneousGesture(
            TapGesture().onEnded {
                action()
            }
        )
        .scaleEffect(isSelected ? 0.98 : 1)
        .modifier(
            MatchShakeEffect(animatableData: isMismatch ? CGFloat(mismatchToken) : 0)
        )
        .opacity(isRemoving ? 0 : 1)
        .shadow(
            color: (isConfirmed || isRemoving) ? .green.opacity(0.2) : .clear,
            radius: (isConfirmed || isRemoving) ? 10 : 0,
            y: (isConfirmed || isRemoving) ? 2 : 0
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isSelected)
        .animation(.easeOut(duration: 0.08), value: isConfirmed)
        .animation(.easeOut(duration: 0.16), value: isRemoving)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isMismatch)
    }

    private var background: some ShapeStyle {
        if isMismatch {
            return AnyShapeStyle(Color.red.opacity(0.18))
        }

        if isConfirmed || isRemoving {
            return AnyShapeStyle(Color.green.opacity(0.28))
        }

        if isSelected {
            return AnyShapeStyle(accent.opacity(0.28))
        }

        return AnyShapeStyle(Color(uiColor: .secondarySystemBackground).opacity(0.98))
    }

    private var borderColor: Color {
        if isMismatch {
            return .red.opacity(0.44)
        }

        if isConfirmed || isRemoving {
            return .green.opacity(0.64)
        }

        if isSelected {
            return accent.opacity(0.62)
        }

        return .clear
    }

    private var borderWidth: CGFloat {
        if isMismatch || isConfirmed || isRemoving || isSelected {
            return 1.25
        }

        return 0
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
    let progressLabel: String
    let progressFraction: Double
    let matchedCount: Int
    let mismatchCount: Int
    let isRetryRound: Bool
    let safeTopInset: CGFloat
    let horizontalPadding: CGFloat
    @Binding var measuredHeight: CGFloat
    @ViewBuilder let trailing: () -> Trailing

    @State private var leadingWidth: CGFloat = 0
    @State private var trailingWidth: CGFloat = UIConstants.Size.actionButton

    var body: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 50, height: 5)
                .accessibilityHidden(true)

            GeometryReader { proxy in
                let titleSideReserve = max(leadingWidth, trailingWidth)
                let titleWidth = max(
                    0,
                    proxy.size.width - (titleSideReserve * 2) - 20
                )

                ZStack {
                    VStack(spacing: 4) {
                        Text(deckTitle)
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: titleWidth)

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
            }
            .frame(height: UIConstants.Size.capsuleHeight)
        }
        .padding(.top, safeTopInset + 4)
        .padding(.horizontal, horizontalPadding)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            if abs(measuredHeight - newHeight) > 0.5 {
                measuredHeight = newHeight
            }
        }
    }

    private var summaryCapsule: some View {
        HStack(spacing: 8) {
            Text("\(matchedCount)")
                .foregroundStyle(.green.opacity(0.96))
            Text("|")
                .foregroundStyle(.white.opacity(0.24))
            Text("\(mismatchCount)")
                .foregroundStyle(.orange.opacity(0.95))
            Text("•")
                .foregroundStyle(.white.opacity(0.24))
            Text("\(Int((max(0, min(progressFraction, 1)) * 100).rounded()))%")
                .foregroundStyle(.white.opacity(0.82))
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: .black, design: .rounded))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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

        let secondPulseDelay = rhythm == .subtle ? 110 : 145
        try? await Task.sleep(for: .milliseconds(secondPulseDelay))
        guard !Task.isCancelled else { return }

        playMismatchPulseEnd(for: preference)
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

    private static func playMismatchPulseEnd(for preference: AppStudyHapticsPreference) {
        switch preference {
        case .off:
            return
        case .subtle:
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.prepare()
            generator.impactOccurred(intensity: 0.34)
        case .standard:
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred(intensity: 0.92)
        }
    }
}

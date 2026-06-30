//
//  CardPreviewModeView.swift
//  QuizFlash
//

import SwiftUI
import UIKit

// MARK: - Card Preview Mode View

/// Immersive preview surface for supported persisted card kinds.
struct CardPreviewModeView: View {
    @Environment(AppPreferences.self) private var appPreferences
    let content: DraftCardContent
    let safeAreaInsets: UIEdgeInsets
    let showsLeadingAccessory: Bool
    let leadingAccessory: AnyView
    let contentAlignment: FlashcardContentAlignment
    let textSize: FlashcardTextSize
    let showsQuizCloseButton: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var isFlipped = false
    @State private var topChromeHeight: CGFloat = 0
    @State private var previewMeasuredChoiceZoneWidths: [UUID: CGFloat] = [:]

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var chromeButtonHeight: CGFloat { UIConstants.Size.capsuleHeight }
    private var leadingChromeWidth: CGFloat {
        showsLeadingAccessory ? (isCompact ? 160 : 188) : (isCompact ? 88 : 104)
    }
    private var locale: Locale { appPreferences.resolvedLocale }
    private var isSheetPresentation: Bool { fullScreenSheetDismiss != nil }
    private var isFlashcardSheetPresentation: Bool { isSheetPresentation && supportsFlip }
    private var isQuizPreview: Bool {
        if case .quiz = content {
            return true
        }
        return false
    }
    private var quizPreviewTextScale: CGFloat { CGFloat(textSize.playModeScale) }
    private var quizContentHorizontalPadding: CGFloat { 8 }
    private var quizContentTopPadding: CGFloat {
        UIConstants.Layout.deckNavigationTopPadding
            + UIConstants.Size.actionButton
            + UIConstants.Spacing.standard
    }
    private var quizContentBottomPadding: CGFloat { 12 }
    private var playChromeButtonSize: CGFloat { isCompact ? 54 : UIConstants.Size.actionButton }
    private var playSurfaceHorizontalPadding: CGFloat {
        isCompact
            ? FlashcardPlayLayoutTuning.screenToCardHorizontalPaddingCompact
            : FlashcardPlayLayoutTuning.screenToCardHorizontalPaddingRegular
    }
    private var playFlipPerspectiveBottomClearance: CGFloat { isCompact ? 14 : 22 }
    private var playScoreZoneHeight: CGFloat { isCompact ? 44 : 52 }
    private var playScoreZoneBottomPadding: CGFloat { isCompact ? 10 : 16 }
    private var playCardBottomReserve: CGFloat { playFlipPerspectiveBottomClearance }
    private var playBottomChromeHeight: CGFloat { playScoreZoneHeight + playScoreZoneBottomPadding + 6 }
    private var playHeaderBottomPadding: CGFloat { isCompact ? 16 : 18 }
    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private func localizedFormat(_ value: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = AppLocalization.string(value, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }
    private var supportsFlip: Bool {
        if case .flashcard = content {
            return true
        }
        return false
    }

    init(
        content: DraftCardContent,
        safeAreaInsets: UIEdgeInsets = .zero,
        showsLeadingAccessory: Bool = false,
        leadingAccessory: AnyView = AnyView(EmptyView()),
        contentAlignment: FlashcardContentAlignment = .center,
        textSize: FlashcardTextSize = .large,
        showsQuizCloseButton: Bool = true,
    ) {
        self.content = content
        self.safeAreaInsets = safeAreaInsets
        self.showsLeadingAccessory = showsLeadingAccessory
        self.leadingAccessory = leadingAccessory
        self.contentAlignment = contentAlignment
        self.textSize = textSize
        self.showsQuizCloseButton = showsQuizCloseButton
    }

    init(
        front: ZoneCardContent,
        back: ZoneCardContent,
        safeAreaInsets: UIEdgeInsets = .zero,
        contentAlignment: FlashcardContentAlignment = .center,
        textSize: FlashcardTextSize = .large
    ) {
        self.init(
            content: .flashcard(
                FlashcardCardContent(
                    frontZone: front.rootZone,
                    backZone: back.rootZone,
                    frontType: .text,
                    backType: .text
                )
            ),
            safeAreaInsets: safeAreaInsets,
            contentAlignment: contentAlignment,
            textSize: textSize
        )
    }

    var body: some View {
        GeometryReader { geo in
            let resolvedSafeTopInset = max(safeAreaInsets.top, geo.safeAreaInsets.top)
            let headerHorizontalInset = isCompact
                ? UIConstants.Layout.compactScreenEdgeInset
                : UIConstants.Layout.screenEdgeInset
            ZStack(alignment: .top) {
                if fullScreenSheetDismiss == nil {
                    CardPreviewModeBackground().ignoresSafeArea()
                }

                if isFlashcardSheetPresentation {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleDone()
                        }
                }

                previewSurface

                if !isFlashcardSheetPresentation && !isQuizPreview {
                    topChrome(
                        safeTopInset: resolvedSafeTopInset,
                        horizontalInset: headerHorizontalInset
                    )
                }

                if isQuizPreview && showsQuizCloseButton {
                    quizPreviewCloseButton
                        .padding(.top, resolvedSafeTopInset + UIConstants.Layout.deckNavigationTopPadding)
                        .padding(.trailing, headerHorizontalInset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            if isFlashcardSheetPresentation {
                ZoneFocusManager.shared.forceReleaseKeyboard()
                ZoneController.shared.forceReleaseKeyboard()
                ZoneController.shared.updateFocusedZone(nil)
            }
        }
    }

    @ViewBuilder
    private var previewSurface: some View {
        switch content {
        case .flashcard(let flashcardContent):
            if isSheetPresentation {
                sheetFlashcardPreviewSurface(flashcardContent)
            } else {
                playMatchedFlashcardPreviewSurface(flashcardContent)
            }
        case .quiz(let quizContent):
            quizPlaybackPreviewSurface(quizContent)
        }
    }

    private func quizPlaybackPreviewSurface(_ quizContent: QuizCardContent) -> some View {
        GeometryReader { proxy in
            let safeTopInset = max(safeAreaInsets.top, proxy.safeAreaInsets.top)
            let safeBottomInset = max(safeAreaInsets.bottom, proxy.safeAreaInsets.bottom)
            let screenWidth = max(proxy.size.width, 1)
            let screenHeight = max(proxy.size.height, 1)
            let topPadding = safeTopInset + quizContentTopPadding
            let bottomPadding = max(safeBottomInset, quizContentBottomPadding)
            let contentWidth = max(screenWidth - (quizContentHorizontalPadding * 2), 1)
            let contentHeight = max(screenHeight - topPadding - bottomPadding, 1)
            let questionViewportHeight = max(screenHeight * 0.30, 1)
            let answerGroupWidth = quizChoiceGroupWidth(availableWidth: contentWidth)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                    QuizQuestionScrollViewport(maxHeight: questionViewportHeight) {
                        QuizPlaybackZoneContent(
                            zone: quizContent.questionZone,
                            fontScale: quizPreviewTextScale,
                            availableWidth: contentWidth,
                            centersLeafBlocks: true,
                            alignLeafBlocksToGroupLeading: false,
                            showsZoneSurfaces: false,
                            textVerticalPadding: 0,
                            textHorizontalPaddingOverride: 0,
                            showsLayoutDebug: false
                        )
                    }

                    quizPlaybackQuestionSeparator
                }

                QuizAnswerList(
                    choices: quizContent.choices,
                    selectedChoiceIDs: [],
                    incorrectChoiceIDs: [],
                    revealedMissedCorrectChoiceIDs: [],
                    wrongFeedbackChoiceIDs: [],
                    wrongFeedbackTrigger: 0,
                    isEvaluated: false,
                    allowsSelection: false,
                    fontScale: quizPreviewTextScale,
                    groupWidth: answerGroupWidth,
                    layoutWidth: contentWidth,
                    topContentInset: UIConstants.Spacing.large,
                    bottomOverlayInset: 0,
                    showsLayoutDebug: false,
                    selectChoice: { _ in },
                    onMeasuredWidthChange: { choiceID, width in
                        updatePreviewMeasuredChoiceWidth(width, for: choiceID)
                    },
                    onLeafDebugSnapshotsChange: { _, _ in },
                    onBlockBoundsChange: { _, _ in }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
            .padding(.horizontal, quizContentHorizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .frame(width: screenWidth, height: screenHeight, alignment: .topLeading)
            .onAppear {
                prunePreviewMeasuredChoiceWidths(for: quizContent)
            }
            .onChange(of: quizContent.choices.map(\.id)) { _, _ in
                prunePreviewMeasuredChoiceWidths(for: quizContent)
            }
        }
    }

    private var quizPlaybackQuestionSeparator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(height: 1)
    }

    private func quizChoiceGroupWidth(availableWidth: CGFloat) -> CGFloat {
        let clampedWidth = max(availableWidth, 1)
        let measuredWidth = previewMeasuredChoiceZoneWidths.values.max() ?? 0
        guard measuredWidth > 0 else { return clampedWidth }
        return min(max(ceil(measuredWidth), 1), clampedWidth)
    }

    private func updatePreviewMeasuredChoiceWidth(_ width: CGFloat, for choiceID: UUID) {
        guard width > 0 else { return }
        let roundedWidth = ceil(width)
        if abs((previewMeasuredChoiceZoneWidths[choiceID] ?? 0) - roundedWidth) > 0.5 {
            previewMeasuredChoiceZoneWidths[choiceID] = roundedWidth
        }
    }

    private func prunePreviewMeasuredChoiceWidths(for quizContent: QuizCardContent) {
        let currentChoiceIDs = Set(quizContent.choices.map(\.id))
        previewMeasuredChoiceZoneWidths = previewMeasuredChoiceZoneWidths.filter { currentChoiceIDs.contains($0.key) }
    }

    @ViewBuilder
    private func playMatchedFlashcardPreviewSurface(_ flashcardContent: FlashcardCardContent) -> some View {
        GeometryReader { geo in
            let safeTopInset = resolvedPlayTopSafeInset(
                geometrySafeTop: geo.safeAreaInsets.top,
                containerHeight: geo.size.height
            )
            let safeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)
            let bottomControlInset = max(safeBottomInset - 6, 10)
            let cardBottomPadding = playBottomChromeHeight + bottomControlInset
            let headerHeight = resolvedPlayHeaderHeight(safeTopInset: safeTopInset)
            let cardSize = resolvedPlayFlashcardSize(
                containerSize: geo.size,
                headerHeight: headerHeight,
                cardBottomPadding: cardBottomPadding
            )

            flashcardPreviewCard(flashcardContent)
                .frame(width: cardSize.width, height: cardSize.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, headerHeight)
                .padding(.bottom, cardBottomPadding + playCardBottomReserve)
        }
    }

    @ViewBuilder
    private func sheetFlashcardPreviewSurface(_ flashcardContent: FlashcardCardContent) -> some View {
        GeometryReader { geo in
            let safeTopInset = resolvedPlayTopSafeInset(
                geometrySafeTop: geo.safeAreaInsets.top,
                containerHeight: geo.size.height
            )
            let safeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)
            let bottomControlInset = max(safeBottomInset - 6, 10)
            let cardBottomPadding = playBottomChromeHeight + bottomControlInset
            let headerHeight = resolvedPlayHeaderHeight(safeTopInset: safeTopInset)
            let cardSize = resolvedPlayFlashcardSize(
                containerSize: geo.size,
                headerHeight: headerHeight,
                cardBottomPadding: cardBottomPadding
            )

            flashcardPreviewCard(flashcardContent)
                .frame(width: cardSize.width, height: cardSize.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func flashcardPreviewCard(_ flashcardContent: FlashcardCardContent) -> some View {
        FlipCard(
            frontZone: flashcardContent.frontZone,
            backZone: flashcardContent.backZone,
            isFlipped: $isFlipped,
            tapAnimationStyle: .flip3D,
            contentAlignment: contentAlignment,
            textSize: textSize,
            onTap: togglePreviewFlip
        )
        .layoutPriority(1)
        .contentShape(Rectangle())
        .onTapGesture(perform: togglePreviewFlip)
    }

    private func resolvedPlayFlashcardSize(
        containerSize: CGSize,
        headerHeight: CGFloat,
        cardBottomPadding: CGFloat
    ) -> CGSize {
        let width = max(containerSize.width - (playSurfaceHorizontalPadding * 2), 1)
        let height = max(
            containerSize.height - headerHeight - cardBottomPadding - playCardBottomReserve,
            UIConstants.Size.cardMinHeight
        )

        return CGSize(width: width, height: height)
    }

    private func resolvedPlayHeaderHeight(safeTopInset: CGFloat) -> CGFloat {
        safeTopInset
            + UIConstants.Layout.deckNavigationTopPadding
            + playChromeButtonSize
            + playHeaderBottomPadding
    }

    private func resolvedPlayTopSafeInset(geometrySafeTop: CGFloat, containerHeight: CGFloat) -> CGFloat {
        let reportedInset = max(safeAreaInsets.top, geometrySafeTop)
        guard isSheetPresentation else { return reportedInset }

        let compactSheetFallback: CGFloat = containerHeight >= 800 ? 59 : 28
        let minimumSheetInset = isCompact ? compactSheetFallback : 24
        return max(reportedInset, minimumSheetInset)
    }

    private func togglePreviewFlip() {
        withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 0.85)) {
            isFlipped.toggle()
        }
    }

    private func topChrome(safeTopInset: CGFloat, horizontalInset: CGFloat) -> some View {
        VStack(spacing: UIConstants.Spacing.small) {
            Capsule()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.2 : 0.35))
                .frame(width: 56, height: 5)
                .accessibilityHidden(true)

            ZStack {
                VStack(spacing: 2) {
                    Text(localized("Preview Mode"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    faceLabel
                }

                HStack {
                    if showsLeadingAccessory {
                        leadingAccessory
                            .frame(width: leadingChromeWidth, alignment: .leading)
                    } else {
                        Color.clear.frame(width: leadingChromeWidth, height: 1)
                    }

                    Spacer(minLength: 0)

                    doneButton
                        .frame(width: chromeButtonHeight, alignment: .trailing)
                }
            }
            .frame(height: chromeButtonHeight)
        }
        .padding(.top, safeTopInset + UIConstants.Spacing.tiny)
        .padding(.horizontal, horizontalInset)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { newHeight in
            if abs(topChromeHeight - newHeight) > 0.5 {
                topChromeHeight = newHeight
            }
        }
    }

    private var faceLabel: some View {
        Text(statusLabel)
            .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var statusLabel: String {
        switch content {
        case .flashcard:
            return isFlipped ? localized("ANSWER") : localized("QUESTION")
        case .quiz(let content):
            let correctCount = content.choices.filter(\.isCorrect).count
            return correctCount == 1
                ? localized("1 CORRECT CHOICE")
                : localizedFormat("%d CORRECT CHOICES", correctCount)
        }
    }

    private var doneButton: some View {
        Button(action: { handleDone() }) {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: chromeButtonHeight, height: chromeButtonHeight)
        }
        .buttonStyle(.plain)
    }

    private var quizPreviewCloseButton: some View {
        ChromeSoftCircleSymbolButton(
            systemName: "xmark",
            accessibilityLabel: localized("Close"),
            action: { handleDone() },
            size: UIConstants.Size.actionButton,
        )
    }

    private func handleDone() {
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            dismiss()
        }
    }
}

// MARK: - Card Preview Mode Background

/// At rest: pure black (dark) / systemGray6 (light).
///
/// During drag a very dark charcoal gradient appears only at the top of the
/// surface, fading to transparent at roughly 25 percent of height.
struct StandardSheetTopStripBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.fullScreenSheetDragProgress) private var dragProgress

    private var overlayOpacity: Double {
        min(dragProgress / 0.10, 1.0)
    }

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color.black
            } else {
                Color(uiColor: .systemGray6)
            }

            LinearGradient(
                stops: [
                    .init(color: Color(white: colorScheme == .dark ? 0.08 : 0.70), location: 0.00),
                    .init(color: Color(white: colorScheme == .dark ? 0.08 : 0.70), location: 0.04),
                    .init(color: .clear, location: 0.25)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(overlayOpacity)
        }
    }
}

struct CardPreviewModeBackground: View {
    var body: some View {
        StandardSheetTopStripBackground()
    }
}

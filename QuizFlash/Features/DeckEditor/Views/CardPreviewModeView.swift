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

    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var isFlipped = false
    @State private var topChromeHeight: CGFloat = 0
    @State private var isDismissing = false

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var chromeButtonHeight: CGFloat { UIConstants.Size.capsuleHeight }
    private var leadingChromeWidth: CGFloat {
        showsLeadingAccessory ? (isCompact ? 160 : 188) : (isCompact ? 88 : 104)
    }
    private var locale: Locale { appPreferences.resolvedLocale }
    private var isSheetPresentation: Bool { fullScreenSheetDismiss != nil }
    private var isFlashcardSheetPresentation: Bool { isSheetPresentation && supportsFlip }
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
    private var dismissCardAnimation: Animation { .smooth(duration: 0.22, extraBounce: 0) }

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
    ) {
        self.content = content
        self.safeAreaInsets = safeAreaInsets
        self.showsLeadingAccessory = showsLeadingAccessory
        self.leadingAccessory = leadingAccessory
        self.contentAlignment = contentAlignment
        self.textSize = textSize
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
            let isLandscape = geo.size.width > geo.size.height
            let resolvedSafeTopInset = max(safeAreaInsets.top, geo.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)
            let headerHorizontalInset = isCompact
                ? UIConstants.Layout.compactScreenEdgeInset
                : UIConstants.Layout.screenEdgeInset
            let contentHorizontalInset = isCompact
                ? UIConstants.Spacing.standard
                : (isLandscape ? geo.size.width * 0.15 : 40)
            let contentTopInset = isFlashcardSheetPresentation ? 0 : topChromeHeight + UIConstants.Spacing.medium
            let contentBottomPadding = isFlashcardSheetPresentation ? 0 : max(resolvedSafeBottomInset, UIConstants.Spacing.standard)

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

                previewSurface(
                    contentTopInset: contentTopInset,
                    horizontalInset: contentHorizontalInset,
                    bottomPadding: contentBottomPadding
                )

                if !isFlashcardSheetPresentation {
                    topChrome(
                        safeTopInset: resolvedSafeTopInset,
                        horizontalInset: headerHorizontalInset
                    )
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
    private func previewSurface(
        contentTopInset: CGFloat,
        horizontalInset: CGFloat,
        bottomPadding: CGFloat
    ) -> some View {
        switch content {
        case .flashcard(let flashcardContent):
            if isSheetPresentation {
                sheetFlashcardPreviewSurface(flashcardContent)
            } else {
                playMatchedFlashcardPreviewSurface(flashcardContent)
            }
        default:
            ScrollView {
                VStack(spacing: UIConstants.Spacing.standard) {
                    staticPreviewSurface
                }
                .frame(maxWidth: 720)
                .padding(.top, contentTopInset)
                .padding(.horizontal, horizontalInset)
                .padding(.bottom, bottomPadding + UIConstants.Spacing.huge)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
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
                .opacity(isDismissing ? 0 : 1)
                .scaleEffect(isDismissing ? 0.965 : 1)
                .offset(y: isDismissing ? max(geo.size.height * 0.08, 64) : 0)
                .animation(dismissCardAnimation, value: isDismissing)
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
                .opacity(isDismissing ? 0 : 1)
                .scaleEffect(isDismissing ? 0.965 : 1)
                .offset(y: isDismissing ? max(geo.size.height * 0.08, 64) : 0)
                .animation(dismissCardAnimation, value: isDismissing)
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
                        .font(.system(size: 20, weight: .bold, design: .rounded))
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
            .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .bold, design: .rounded))
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
        Button(action: handleDone) {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: chromeButtonHeight, height: chromeButtonHeight)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var staticPreviewSurface: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            switch content {
            case .flashcard:
                EmptyView()
            case .quiz(let quizContent):
                quizPreview(quizContent)
            }
        }
    }

    private func quizPreview(_ content: QuizCardContent) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            previewSectionCard(title: localized("Question"), symbol: "questionmark.bubble.fill") {
                previewBodyText(
                    zonePreviewText(content.questionZone, fallback: localized("No question added")),
                    tint: .primary
                )
            }

            previewSectionCard(
                title: localized("Choices"),
                symbol: "checklist",
                subtitle: content.allowsMultipleCorrect
                    ? localized("Multiple correct answers enabled")
                    : localized("Single correct answer")
            ) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    ForEach(Array(content.choices.enumerated()), id: \.element.id) { index, choice in
                        HStack(alignment: .top, spacing: UIConstants.Spacing.small) {
                            Image(systemName: choice.isCorrect ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(choice.isCorrect ? .green : .secondary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(localizedFormat("Choice %d", index + 1))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)

                                previewBodyText(
                                    zonePreviewText(choice.contentZone, fallback: localized("Empty choice")),
                                    tint: choice.isCorrect ? .primary : .secondary
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if let explanationZone = content.explanationZone,
               zonePreviewText(explanationZone, fallback: "").isEmpty == false {
                previewSectionCard(title: localized("Explanation"), symbol: "text.bubble.fill") {
                    previewBodyText(
                        zonePreviewText(explanationZone, fallback: localized("No explanation added")),
                        tint: .primary
                    )
                }
            }
        }
    }

    private func previewSectionCard<SectionContent: View>(
        title: String,
        symbol: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> SectionContent
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.small) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            content()
        }
        .padding(UIConstants.Spacing.large)
        .background(sectionBackground, in: RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .stroke(sectionBorderColor, lineWidth: 1)
        }
    }

    private func previewBodyText(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 19, weight: .medium, design: .rounded))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func compactMetricChip(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(sectionBackground, in: Capsule())
        .overlay {
            Capsule()
                .stroke(sectionBorderColor, lineWidth: 1)
        }
    }

    private var sectionBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.045)
            : Color.white.opacity(0.82)
    }

    private var sectionBorderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }

    private func zonePreviewText(_ zone: ZoneModel, fallback: String, maxLength: Int = 500) -> String {
        let preview = zone.previewText(maxLength: maxLength)
        return preview == "Empty" ? fallback : preview
    }

    private func normalizedSingleLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleDone() {
        guard !isDismissing else { return }
        if let fullScreenSheetDismiss, supportsFlip {
            isDismissing = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                fullScreenSheetDismiss()
            }
        } else if let fullScreenSheetDismiss {
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

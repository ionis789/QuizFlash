//
//  CardPreviewModeView.swift
//  QuizFlash
//

import SwiftUI
import UIKit

// MARK: - Card Preview Mode View

/// Immersive preview surface for all persisted card kinds.
struct CardPreviewModeView: View {
    @Environment(AppPreferences.self) private var appPreferences
    let content: DraftCardContent
    let safeAreaInsets: UIEdgeInsets
    let showsLeadingAccessory: Bool
    let leadingAccessory: AnyView
    let contentAlignment: FlashcardContentAlignment
    let textSize: FlashcardTextSize
    let onOpenRecommendedConversion: ((CardKind) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var isFlipped = false
    @State private var topChromeHeight: CGFloat = 0

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var chromeButtonHeight: CGFloat { UIConstants.Size.capsuleHeight }
    private var leadingChromeWidth: CGFloat {
        showsLeadingAccessory ? (isCompact ? 160 : 188) : (isCompact ? 88 : 104)
    }
    private var readinessDiagnostics: [CardReadinessDiagnostic] {
        CardReadinessDiagnostics.diagnostics(for: content)
    }
    private var locale: Locale { appPreferences.resolvedLocale }

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
    private var swipeBackAttachment: SwipeBackAttachment {
        fullScreenSheetDismiss == nil ? .window : .localHost
    }

    init(
        content: DraftCardContent,
        safeAreaInsets: UIEdgeInsets = .zero,
        showsLeadingAccessory: Bool = false,
        leadingAccessory: AnyView = AnyView(EmptyView()),
        contentAlignment: FlashcardContentAlignment = .center,
        textSize: FlashcardTextSize = .large,
        onOpenRecommendedConversion: ((CardKind) -> Void)? = nil
    ) {
        self.content = content
        self.safeAreaInsets = safeAreaInsets
        self.showsLeadingAccessory = showsLeadingAccessory
        self.leadingAccessory = leadingAccessory
        self.contentAlignment = contentAlignment
        self.textSize = textSize
        self.onOpenRecommendedConversion = onOpenRecommendedConversion
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
            let contentTopInset = topChromeHeight + UIConstants.Spacing.medium
            let contentBottomPadding = max(resolvedSafeBottomInset, UIConstants.Spacing.standard)
            let availableCardHeight = max(
                UIConstants.Size.cardMinHeight,
                geo.size.height - contentTopInset - contentBottomPadding
            )

            ZStack(alignment: .top) {
                if fullScreenSheetDismiss == nil {
                    CardPreviewModeBackground().ignoresSafeArea()
                }

                previewSurface(
                    availableCardHeight: availableCardHeight,
                    contentTopInset: contentTopInset,
                    horizontalInset: contentHorizontalInset,
                    bottomPadding: contentBottomPadding
                )

                topChrome(
                    safeTopInset: resolvedSafeTopInset,
                    horizontalInset: headerHorizontalInset
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .swipeBack(attachment: swipeBackAttachment) {
            handleDone()
        }
    }

    @ViewBuilder
    private func previewSurface(
        availableCardHeight: CGFloat,
        contentTopInset: CGFloat,
        horizontalInset: CGFloat,
        bottomPadding: CGFloat
    ) -> some View {
        switch content {
        case .flashcard(let flashcardContent):
            ZStack(alignment: .bottom) {
                FlipCard(
                    frontZone: flashcardContent.frontZone,
                    backZone: flashcardContent.backZone,
                    isFlipped: $isFlipped,
                    tapAnimationStyle: .flip3D,
                    contentAlignment: contentAlignment,
                    textSize: textSize,
                    onTap: togglePreviewFlip
                )
                .frame(maxWidth: .infinity)
                .frame(height: availableCardHeight)
                .layoutPriority(1)
                .contentShape(Rectangle())
                .onTapGesture {
                    togglePreviewFlip()
                }
                .padding(.top, contentTopInset)
                .padding(.horizontal, horizontalInset)
                .padding(.bottom, bottomPadding)

                if !readinessDiagnostics.isEmpty {
                    CardPreviewReadinessPanel(
                        diagnostics: readinessDiagnostics,
                        onOpenRecommendedConversion: onOpenRecommendedConversion
                    )
                        .padding(.horizontal, horizontalInset + UIConstants.Spacing.small)
                        .padding(.bottom, bottomPadding + UIConstants.Spacing.standard)
                }
            }
        default:
            ScrollView {
                VStack(spacing: UIConstants.Spacing.standard) {
                    staticPreviewSurface

                    if !readinessDiagnostics.isEmpty {
                        CardPreviewReadinessPanel(
                            diagnostics: readinessDiagnostics,
                            onOpenRecommendedConversion: onOpenRecommendedConversion
                        )
                    }
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
        case .write:
            return localized("WRITE PREVIEW")
        case .match:
            return localized("MATCH PREVIEW")
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
            case .write(let writeContent):
                writePreview(writeContent)
            case .match(let matchContent):
                matchPreview(matchContent)
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

    private func writePreview(_ content: WriteCardContent) -> some View {
        let sourceText = WriteBlankTextHelper.normalizedSourceText(from: content.sourceZone)
        let validatedBlank = WriteBlankTextHelper.validatedBlankSelection(
            content.blankSelection,
            in: sourceText,
            fallbackZoneID: content.sourceZone.id
        )
        let inlineSegments = validatedBlank.flatMap {
            WriteBlankTextHelper.inlinePromptSegments(for: $0, in: sourceText)
        }
        let blankedPrompt = validatedBlank.flatMap {
            WriteBlankTextHelper.applyingBlank($0, to: sourceText)
        }
        let revealedAnswer = normalizedSingleLine(content.blankSelection.omittedText)

        return VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            previewSectionCard(title: localized("Prompt with Blank"), symbol: "rectangle.and.pencil.and.ellipsis") {
                if let inlineSegments {
                    inlineWritePrompt(
                        segments: inlineSegments,
                        revealsAnswer: false
                    )
                } else {
                    previewBodyText(
                        blankedPrompt ?? zonePreviewText(content.sourceZone, fallback: localized("No prompt added")),
                        tint: .primary
                    )
                }
            }

            previewSectionCard(title: localized("Answer Reveal"), symbol: "text.cursor") {
                if let inlineSegments {
                    inlineWritePrompt(
                        segments: inlineSegments,
                        revealsAnswer: true
                    )
                } else {
                    previewBodyText(
                        revealedAnswer.isEmpty ? localized("No answer selected") : revealedAnswer,
                        tint: revealedAnswer.isEmpty ? .secondary : .green
                    )
                }
            }
        }
    }

    private func matchPreview(_ content: MatchCardContent) -> some View {
        let prompt = normalizedSingleLine(content.prompt)
        let answer = normalizedSingleLine(content.answer)

        return VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: UIConstants.Spacing.small) {
                    compactMetricChip(title: localized("Prompt"), value: localizedFormat("%d chars", prompt.count))
                    compactMetricChip(title: localized("Answer"), value: localizedFormat("%d chars", answer.count))
                    compactMetricChip(
                        title: localized("Shape"),
                        value: prompt.count + answer.count <= 110
                            ? localized("Compact")
                            : localized("Verbose")
                    )
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            previewSectionCard(title: localized("Prompt"), symbol: "arrow.left.and.right.text.vertical") {
                previewBodyText(prompt.isEmpty ? localized("No prompt added") : prompt, tint: prompt.isEmpty ? .secondary : .primary)
            }

            previewSectionCard(title: localized("Answer"), symbol: "rectangle.2.swap") {
                previewBodyText(answer.isEmpty ? localized("No answer added") : answer, tint: answer.isEmpty ? .secondary : .primary)
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

    private func inlineWritePrompt(
        segments: WriteInlinePromptSegments,
        revealsAnswer: Bool
    ) -> some View {
        let blankText = revealsAnswer ? segments.omittedText : "____"
        let blankTint: Color = revealsAnswer ? .green : accent

        return (
            Text(segments.prefixText)
            + Text(blankText).fontWeight(.heavy).foregroundStyle(blankTint)
            + Text(segments.suffixText)
        )
        .font(.system(size: 19, weight: .medium, design: .rounded))
        .foregroundStyle(.primary)
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
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            dismiss()
        }
    }
}

// MARK: - CardPreviewReadinessPanel

/// Compact readiness callouts shown inside preview mode.
struct CardPreviewReadinessPanel: View {
    @Environment(AppPreferences.self) private var appPreferences
    let diagnostics: [CardReadinessDiagnostic]
    var onOpenRecommendedConversion: ((CardKind) -> Void)? = nil

    private var locale: Locale { appPreferences.resolvedLocale }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private func localizedFormat(_ value: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = AppLocalization.string(value, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    private var recommendedTargets: [CardKind] {
        Array(Set(diagnostics.compactMap(\.recommendedConversionTargetKind)))
            .sorted { $0.localizedTitle(locale: locale) < $1.localizedTitle(locale: locale) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            Text(localized("READINESS"))
                .font(.caption.weight(.heavy))
                .foregroundStyle(.tertiary)

            ForEach(diagnostics) { diagnostic in
                HStack(alignment: .top, spacing: UIConstants.Spacing.small) {
                    Image(systemName: diagnostic.kind.symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(diagnostic.kind.tint)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(diagnostic.kind.shortTitle)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)

                        Text(diagnostic.detail)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let onOpenRecommendedConversion,
               !recommendedTargets.isEmpty {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    Text(localized("Recommended conversion"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    ForEach(recommendedTargets, id: \.self) { targetKind in
                        Button {
                            onOpenRecommendedConversion(targetKind)
                        } label: {
                            HStack(spacing: UIConstants.Spacing.small) {
                                Image(systemName: targetKind.conversionSystemImage)
                                    .font(.caption.weight(.bold))

                                Text(localizedFormat("Convert this card to %@", targetKind.localizedTitle(locale: locale)))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)

                                Spacer(minLength: UIConstants.Spacing.small)

                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(targetKind == .match ? .orange : .teal)
                            }
                            .padding(.horizontal, UIConstants.Spacing.standard)
                            .padding(.vertical, UIConstants.Spacing.standard)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
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

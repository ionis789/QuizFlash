//
//  AIGenerationSheetView.swift
//  QuizFlash
//
//  Compact AI generation configuration sheet with source-aware coverage planning.
//

import SwiftUI

// MARK: - AI Generation Sheet

struct AIGenerationSheetBackground: View {
    var body: some View {
        Color.black
            .ignoresSafeArea()
    }
}

struct AIGenerationSheetView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Bindable var viewModel: DeckWorkspaceViewModel
    let safeAreaInsets: UIEdgeInsets
    var onPrimaryAction: (@escaping (Bool) -> Void) -> Void
    var onCancel: () -> Void

    @State private var selectedSourcePreview: AIGenerationSourcePreviewItem?
    @State private var selectedSourcePreviewImage: UIImage?
    @State private var sourcePreviewTask: Task<Void, Never>?
    @State private var headerHeight: CGFloat = 0
    @State private var isSubmittingGeneration = false

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    private var maxContentWidth: CGFloat {
        UIConstants.isPad ? 760 : .infinity
    }

    private var isPreparingSource: Bool {
        viewModel.isPreparingAISource && viewModel.preparedAISource == nil
    }

    private var canUseManualDistribution: Bool {
        (viewModel.preparedAISource?.itemCount ?? 0) > 1
    }

    var body: some View {
        GeometryReader { proxy in
            let resolvedSafeTopInset = max(safeAreaInsets.top, proxy.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, proxy.safeAreaInsets.bottom)

            ZStack(alignment: .top) {
                if isPreparingSource {
                    preparingLayout
                        .transition(.opacity)
                } else {
                    configurationLayout(bottomClearance: bottomActionClearance(safeBottomInset: resolvedSafeBottomInset))
                        .transition(.opacity)
                }

                TopProgressiveBlurOverlay(
                    topHeight: resolvedSafeTopInset + UIConstants.Size.actionButton + UIConstants.Spacing.small,
                    revealProgress: 1,
                    tintColor: .black,
                    configuration: ScreenTopProgressiveBlurConfiguration(
                        maxBlurRadius: 5,
                        fadeExtension: 24,
                        tintOpacityTop: 0.78,
                        tintOpacityMiddle: 0.18
                    ),
                    revealAnimation: nil
                )
                .zIndex(1)

                header(safeTopInset: resolvedSafeTopInset)
                    .zIndex(2)

                if selectedSourcePreview != nil {
                    SourcePreviewOverlay(
                        image: selectedSourcePreviewImage,
                        safeAreaInsets: safeAreaInsets,
                        onClose: closeSourcePreview
                    )
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: isPreparingSource) {
            guard isPreparingSource else { return }
            viewModel.startPendingAISourcePreparationIfNeeded()
        }
    }

    private func configurationLayout(bottomClearance: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
                section {
                    generationSettingsContent
                }

                section(
                    title: AppLocalization.string("Source Coverage", locale: appPreferences.resolvedLocale)
                ) {
                    sourceCoverageContent
                }
            }
            .frame(maxWidth: maxContentWidth)
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .padding(.top, headerHeight + UIConstants.Spacing.large)
            .padding(.bottom, bottomClearance)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var preparingLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: headerHeight + UIConstants.Spacing.large)

            SourcePreparationCenterStage(state: viewModel.aiSourcePreparationState)
                .frame(maxWidth: 420)
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)

            Spacer(minLength: UIConstants.Spacing.huge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func header(safeTopInset: CGFloat) -> some View {
        HStack {
            ChromeSoftCircleSymbolButton(
                systemName: "xmark",
                accessibilityLabel: AppLocalization.string("Close", locale: appPreferences.resolvedLocale),
                action: requestCancel
            )
            .frame(width: UIConstants.Size.actionButton, alignment: .leading)
            .disabled(isSubmittingGeneration)
            .opacity(isSubmittingGeneration ? 0.48 : 1)

            Spacer(minLength: 0)

            headerGenerateButton
        }
        .frame(height: UIConstants.Size.actionButton)
        .padding(.top, safeTopInset + UIConstants.Spacing.tiny)
        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            if abs(headerHeight - newHeight) > 0.5 {
                headerHeight = newHeight
            }
        }
    }

    private var cardsCountCard: some View {
        VStack(spacing: 0) {
            TickCardCountPicker(
                value: viewModel.requestedCardCount,
                range: 5 ... viewModel.maximumAICardsPerGeneration
            ) { newValue in
                viewModel.setRequestedCardCount(newValue)
            }
        }
        .padding(.horizontal, UIConstants.Spacing.standard)
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        PlainGenerationSection(
            title: title,
            content: content
        )
    }

    private var generationSettingsContent: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            compactOptionRow(title: "Type") {
                HStack(spacing: UIConstants.Spacing.small) {
                    ForEach(AICardGenerationType.allCases) { type in
                        compactSelectionButton(
                            title: type.localizedTitle(locale: appPreferences.resolvedLocale),
                            isSelected: viewModel.aiGenerationOptions.cardType == type
                        ) {
                            viewModel.aiGenerationOptions.cardType = type
                        }
                    }
                }
            }

            compactOptionRow(title: "Level") {
                HStack(spacing: UIConstants.Spacing.small) {
                    ForEach(AICardGenerationLevel.allCases) { level in
                        compactSelectionButton(
                            title: level.localizedTitle(locale: appPreferences.resolvedLocale),
                            isSelected: viewModel.aiGenerationOptions.cardLevel == level
                        ) {
                            viewModel.aiGenerationOptions.cardLevel = level
                        }
                    }
                }
            }

            compactOptionRow(title: "Language") {
                outputLanguageCompactPicker
            }
        }
    }

    private var sourceCoverageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardsCountCard
            sourcePreviewStrip
        }
        .onAppear {
            viewModel.setSourceDistributionMode(.auto)
        }
    }

    @ViewBuilder
    private var sourcePreviewStrip: some View {
        if let source = viewModel.preparedAISource {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: UIConstants.Spacing.small) {
                        ForEach(source.previewItems) { item in
                            SourcePreviewCard(item: item) {
                                openSourcePreview(item)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var outputLanguageCompactPicker: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack(spacing: UIConstants.Spacing.small) {
                compactSelectionButton(
                    title: "Auto",
                    isSelected: viewModel.aiGenerationOptions.outputLanguageMode == .auto
                ) {
                    viewModel.aiGenerationOptions.outputLanguageMode = .auto
                }

                compactSelectionButton(
                    title: "Manual",
                    isSelected: viewModel.aiGenerationOptions.outputLanguageMode == .manual
                ) {
                    viewModel.aiGenerationOptions.outputLanguageMode = .manual
                    if viewModel.aiGenerationOptions.manualOutputLanguage == nil {
                        viewModel.aiGenerationOptions.manualOutputLanguage = AIGenerationLanguageHint.supportedOutputLanguages.first
                    }
                }
            }

            if viewModel.aiGenerationOptions.outputLanguageMode == .manual {
                Menu {
                    ForEach(AIGenerationLanguageHint.supportedOutputLanguages, id: \.languageCode) { language in
                        Button {
                            viewModel.aiGenerationOptions.manualOutputLanguage = language
                        } label: {
                            if viewModel.aiGenerationOptions.manualOutputLanguage?.languageCode == language.languageCode {
                                Label(language.localizedDisplayName(locale: appPreferences.resolvedLocale), systemImage: "checkmark")
                            } else {
                                Text(language.localizedDisplayName(locale: appPreferences.resolvedLocale))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: UIConstants.Spacing.small) {
                        Text(
                            viewModel.aiGenerationOptions.manualOutputLanguage?.localizedDisplayName(locale: appPreferences.resolvedLocale)
                                ?? AppLocalization.string("Choose a language", locale: appPreferences.resolvedLocale)
                        )
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                        Spacer(minLength: UIConstants.Spacing.small)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, UIConstants.Spacing.standard)
                    .padding(.vertical, 12)
                    .duoControlSurface(cornerRadius: 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func compactOptionRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.tiny) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content()
        }
    }

    private func compactSelectionButton(
        title: String,
        isSelected: Bool,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .quizFlashLabelChrome(
                    isSelected ? .secondary : .surface,
                    shape: .capsule,
                    size: UIConstants.Size.actionButton,
                    horizontalPadding: UIConstants.Spacing.small
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var manualCoverageEditor: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            ForEach(viewModel.manualAISourceAllocations) { allocation in
                ManualAllocationCard(
                    allocation: allocation,
                    upperBound: max(viewModel.preparedAISource?.itemCount ?? 1, 1),
                    maximumEndIndex: viewModel.maximumManualEndIndex(for: allocation),
                    cardCountUpperBound: viewModel.maximumManualCardCount(for: allocation),
                    canRemove: viewModel.manualAISourceAllocations.count > 1,
                    onEndChange: { viewModel.updateManualAllocation(id: allocation.id, endIndex: $0) },
                    onCardCountChange: { viewModel.updateManualAllocation(id: allocation.id, cardCount: $0) },
                    onRemove: { viewModel.removeManualAllocation(id: allocation.id) }
                )
            }

            if viewModel.canAddManualAllocation {
                Button {
                    viewModel.addManualAllocation()
                } label: {
                    Label(AppLocalization.string("Add Range", locale: appPreferences.resolvedLocale), systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .duoControlSurface(cornerRadius: 16, tint: .blue)
                }
                .buttonStyle(.plain)
            }

            if let message = viewModel.manualAllocationValidationMessage(locale: appPreferences.resolvedLocale) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var headerGenerateButton: some View {
        Button(action: requestPrimaryAction) {
            HStack(spacing: UIConstants.Spacing.small) {
                Text(AppLocalization.string("Generate", locale: appPreferences.resolvedLocale))
                    .font(.system(size: 15, weight: .bold))

                if isSubmittingGeneration {
                    ProgressActivityDots(color: .white)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: UIConstants.Size.actionButton)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .shadow(color: Color.purple.opacity(0.24), radius: 14, y: 2)
            }
            .aiGenerationBorderBeam(
                accent: accent,
                cornerRadius: UIConstants.Size.actionButton / 2,
                beamBlur: 10,
                lineWidth: 2,
                isEnabled: viewModel.canConfirmAIGeneration
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(width: UIConstants.isPad ? 180 : 142)
        .disabled(isSubmittingGeneration || !viewModel.canConfirmAIGeneration)
        .opacity(isSubmittingGeneration || viewModel.canConfirmAIGeneration ? 1 : 0.48)
    }

    private func bottomActionClearance(safeBottomInset: CGFloat) -> CGFloat {
        max(safeBottomInset, UIConstants.Spacing.large)
            + UIConstants.Spacing.huge
    }

    private func requestCancel() {
        guard !isSubmittingGeneration else { return }
        viewModel.clearsPendingAISourceOnSheetDismiss = true
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            onCancel()
        }
    }

    private func requestPrimaryAction() {
        guard !isSubmittingGeneration else { return }
        isSubmittingGeneration = true

        Task { @MainActor in
            onPrimaryAction { didPrepareGeneration in
                Task { @MainActor in
                    guard didPrepareGeneration,
                          viewModel.stageAIGenerationDisplayForSheetDismiss() else {
                        isSubmittingGeneration = false
                        return
                    }

                    let startGeneration = {
                        viewModel.confirmAIGenerationFromSheet()
                    }

                    if let fullScreenSheetDismiss {
                        fullScreenSheetDismiss(completion: startGeneration)
                    } else {
                        startGeneration()
                    }
                }
            }
        }
    }

    private func openSourcePreview(_ item: AIGenerationSourcePreviewItem) {
        sourcePreviewTask?.cancel()
        selectedSourcePreview = item
        selectedSourcePreviewImage = nil

        sourcePreviewTask = Task {
            let image = await viewModel.fullQualityPreviewImage(for: item)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                selectedSourcePreviewImage = image
            }
        }
    }

    private func closeSourcePreview() {
        sourcePreviewTask?.cancel()
        sourcePreviewTask = nil
        withAnimation(.easeInOut(duration: UIConstants.Animation.standard)) {
            selectedSourcePreview = nil
            selectedSourcePreviewImage = nil
        }
    }
}

private struct PlainGenerationSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, UIConstants.Spacing.small)
            }

            content()
                .padding(.bottom, UIConstants.Spacing.standard)

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
        }
    }
}

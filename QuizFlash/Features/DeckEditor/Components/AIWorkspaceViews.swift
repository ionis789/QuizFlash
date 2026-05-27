//
//  AIWorkspaceViews.swift
//  QuizFlash
//
//  Shared UI surfaces for the global AI workspace.
//

import SwiftUI
import SwiftData

// MARK: - Floating Status

struct FloatingAIWorkspaceStatusMenu: View {
    let status: AIWorkspaceFloatingStatus
    var bottomPadding: CGFloat
    var onOpenWorkspace: (() -> Void)? = nil
    var onPauseResume: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    private var tint: Color {
        switch status.phase {
        case .failed:
            return .red
        case .completed:
            return .green
        case .paused:
            return .orange
        case .preparing, .running:
            return status.kind == .conversion ? .orange : accent
        }
    }

    var body: some View {
        workspaceButton
            .padding(.trailing, UIConstants.Layout.compactScreenEdgeInset)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .transition(.scale(scale: 0.92, anchor: .trailing).combined(with: .opacity))
    }

    private var workspaceButton: some View {
        FloatingAIWorkspaceCapsuleContainer {
            HStack(spacing: UIConstants.Spacing.small) {
                if let onOpenWorkspace {
                    Button(action: onOpenWorkspace) {
                        compactContent
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open AI workspace")
                } else {
                    compactContent
                }

                if let onPauseResume {
                    Button(action: onPauseResume) {
                        Image(systemName: pauseResumeSymbol)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                            .frame(width: 24, height: 24)
                            .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(status.phase == .paused ? "Resume AI workspace job" : "Pause AI workspace job")
                }

                if let onCancel {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel AI workspace job")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var compactContent: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            FloatingAIWorkspaceStatusIndicator(
                countText: compactCountText,
                tint: tint,
                fallbackSystemImage: status.systemImage
            )

            if compactCountText == nil {
                Text(compactTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
    }

    private var compactTitle: String {
        switch status.phase {
        case .completed:
            return "Done"
        case .failed:
            return "Error"
        case .preparing, .running, .paused:
            return status.kind == .conversion ? "Convert" : "Generate"
        }
    }

    private var compactCountText: String? {
        if status.phase == .preparing || status.phase == .running || status.phase == .paused,
           let progressLabel = status.progressLabel {
            return progressLabel
        }
        return nil
    }

    private var pauseResumeSymbol: String {
        status.phase == .paused ? "play.fill" : "pause.fill"
    }
}

private struct FloatingAIWorkspaceCapsuleContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, UIConstants.Spacing.standard)
            .frame(minWidth: UIConstants.Size.capsuleHeight)
            .frame(height: UIConstants.Size.capsuleHeight)
            .glassButton(shape: .capsule)
    }
}

private struct FloatingAIWorkspaceStatusIndicator: View {
    let countText: String?
    let tint: Color
    let fallbackSystemImage: String

    var body: some View {
        if let countText {
            VStack(spacing: 2) {
                Text(countText)
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .statusTextMotion(trigger: countText)

                AIGenerationActivityDots(color: tint)
                    .frame(minWidth: 22)
            }
            .fixedSize(horizontal: true, vertical: false)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: countText)
        } else {
            Image(systemName: fallbackSystemImage)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
        }
    }
}

// MARK: - Create Workspace

struct CreateWorkspaceRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(NavigationManager.self) private var router
    @Environment(AIWorkspaceCoordinator.self) private var coordinator
    @Environment(ThemeManager.self) private var themeManager

    @Query(sort: \DeckModel.editedAt, order: .reverse) private var sourceDecks: [DeckModel]

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    private var horizontalInset: CGFloat {
        horizontalSizeClass == .compact
            ? UIConstants.Layout.compactScreenEdgeInset
            : UIConstants.Layout.screenEdgeInset
    }

    private var actionColumns: [GridItem] {
        horizontalSizeClass == .compact
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                headerCard

                if let status = coordinator.generationStatus,
                   status.phase != .completed {
                    generationStatusCard(status)
                }

                if coordinator.conversionProgress != nil
                    || coordinator.conversionSummary != nil
                    || coordinator.conversionErrorMessage != nil {
                    AIWorkspaceRuntimeCard(coordinator: coordinator)
                }

                LazyVGrid(columns: actionColumns, spacing: UIConstants.Spacing.medium) {
                    CreateWorkspaceActionCard(
                        title: "New Deck",
                        detail: "Open the classic editor and build cards by hand.",
                        systemImage: "square.and.pencil",
                        tint: accent,
                        action: { router.append(AppRoute.createDeck) }
                    )

                    CreateWorkspaceActionCard(
                        title: "Generate",
                        detail: "Start the deck editor with AI generation ready.",
                        systemImage: "wand.and.stars",
                        tint: accent,
                        action: { router.append(AppRoute.generateDeck) }
                    )

                    CreateWorkspaceActionCard(
                        title: "Convert",
                        detail: sourceDecks.isEmpty
                            ? "Add at least one deck before converting cards."
                            : "Pick any saved deck and convert one card type at a time.",
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: .orange,
                        isDisabled: sourceDecks.isEmpty,
                        action: { router.createWorkspaceMode = .convert }
                    )
                }
            }
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, UIConstants.Spacing.large)
        }
        .background(themeManager.groupedScreenBackground.ignoresSafeArea())
        .navigationTitle("Create")
        .navigationBarTitleDisplayMode(.large)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text("Build, generate, or convert")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(.primary)

            Text("The Create tab is now the workspace hub. Open the editor for new decks, launch AI generation, or convert cards from any existing deck.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: UIConstants.Spacing.small) {
                conversionSummaryChip("\(sourceDecks.count) deck\(sourceDecks.count == 1 ? "" : "s")", systemImage: "rectangle.stack.fill")
                if coordinator.conversionProgress != nil || coordinator.conversionSummary != nil {
                    conversionSummaryChip("Conversion active", systemImage: "sparkles")
                }
                if coordinator.generationStatus != nil {
                    conversionSummaryChip("Generation active", systemImage: "wand.and.stars")
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetStyle(cornerRadius: 30)
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func generationStatusCard(_ status: AIWorkspaceGenerationStatus) -> some View {
        switch status.phase {
        case .paused:
            AIPausedResumeCard(
                foundCount: status.foundCount,
                targetCount: status.targetCount,
                remainingCount: max(status.targetCount - status.foundCount, 0),
                progress: status.progress,
                title: status.title,
                subtitle: status.message
            ) {
                router.append(AppRoute.generateDeck)
            }
        case .preparing, .running:
            AIStreamingProgressCard(
                foundCount: status.foundCount,
                targetCount: status.targetCount,
                progress: status.progress,
                title: status.title,
                subtitleOverride: status.message,
                accentColor: accent,
                footnote: "Open Generate to continue in the deck editor"
            )
        case .failed:
            AIWorkspaceFailureCard(
                title: status.title,
                message: status.message,
                tint: .red,
                onRetry: { router.append(AppRoute.generateDeck) },
                onDismiss: { coordinator.generationStatus = nil }
            )
        case .completed:
            EmptyView()
        }
    }
}

private struct CreateWorkspaceActionCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 52, height: 52)

                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(UIConstants.Spacing.large)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
            .widgetStyle(cornerRadius: UIConstants.Radius.large)
            .overlay {
                RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

// MARK: - Global Convert

struct CreateWorkspaceConvertView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(NavigationManager.self) private var router
    @Environment(AIWorkspaceCoordinator.self) private var coordinator
    @Environment(ThemeManager.self) private var themeManager

    private var horizontalInset: CGFloat {
        horizontalSizeClass == .compact
            ? UIConstants.Layout.compactScreenEdgeInset
            : UIConstants.Layout.screenEdgeInset
    }

    private var currentRequest: DeckCardConversionRequest? {
        coordinator.conversionSeed?.request
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            CreateWorkspaceConvertEditor(
                managesSeedFromDeckList: true,
                showsDeckPicker: true,
                showsRuntimeSummary: true
            )
            .padding(.horizontal, horizontalInset)
            .padding(.top, UIConstants.Spacing.large)
            .padding(.bottom, 120)
        }
        .background(themeManager.groupedScreenBackground.ignoresSafeArea())
        .navigationTitle("Convert")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let request = currentRequest {
                ConversionStartBar(
                    request: request,
                    tint: .orange,
                    horizontalInset: horizontalInset,
                    action: startConversion
                )
            }
        }
    }

    private func startConversion() {
        coordinator.startConversion(context: context)
        router.createPath = NavigationPath()
    }
}

// MARK: - Local Convert Sheet

struct DeckConversionSheetView: View {
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ThemeManager.self) private var themeManager

    @Bindable var coordinator: AIWorkspaceCoordinator
    let safeAreaInsets: UIEdgeInsets
    let onStart: () -> Void

    @State private var headerHeight: CGFloat = 0

    private var horizontalInset: CGFloat {
        horizontalSizeClass == .compact
            ? UIConstants.Layout.compactScreenEdgeInset
            : UIConstants.Layout.screenEdgeInset
    }

    private var currentRequest: DeckCardConversionRequest? {
        coordinator.conversionSeed?.request
    }

    var body: some View {
        GeometryReader { geo in
            let resolvedSafeTopInset = max(safeAreaInsets.top, geo.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)

            ZStack(alignment: .top) {
                if fullScreenSheetDismiss == nil {
                    themeManager.groupedScreenBackground
                        .ignoresSafeArea()
                }

                ScrollView(.vertical, showsIndicators: false) {
                    if currentRequest != nil {
                        CreateWorkspaceConvertEditor(
                            managesSeedFromDeckList: false,
                            showsDeckPicker: false,
                            showsRuntimeSummary: false
                        )
                        .padding(.horizontal, horizontalInset)
                        .padding(.top, headerHeight + UIConstants.Spacing.large)
                        .padding(.bottom, resolvedSafeBottomInset + 120)
                    } else {
                        ConversionUnavailableCard(
                            title: "Conversion unavailable",
                            message: "Reopen the sheet and try again."
                        )
                        .padding(.horizontal, horizontalInset)
                        .padding(.top, headerHeight + UIConstants.Spacing.large)
                    }
                }

                header(safeTopInset: resolvedSafeTopInset)
            }
            .safeAreaInset(edge: .bottom) {
                if let request = currentRequest {
                    ConversionStartBar(
                        request: request,
                        tint: .orange,
                        horizontalInset: horizontalInset,
                        action: onStart
                    )
                    .padding(.bottom, max(resolvedSafeBottomInset, UIConstants.Spacing.large) - UIConstants.Spacing.small)
                }
            }
            .fullScreenSheetDragActivationHeight(headerHeight)
        }
    }

    private func header(safeTopInset: CGFloat) -> some View {
        VStack(spacing: UIConstants.Spacing.small) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 56, height: 5)
                .accessibilityHidden(true)

            ZStack {
                Text("Convert Cards")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack {
                    Spacer(minLength: 0)
                    dismissButton
                        .frame(width: UIConstants.Size.actionButton, alignment: .trailing)
                }
            }
            .frame(height: UIConstants.Size.capsuleHeight)
        }
        .padding(.top, safeTopInset + UIConstants.Spacing.tiny)
        .padding(.horizontal, horizontalInset)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            if abs(headerHeight - newHeight) > 0.5 {
                headerHeight = newHeight
            }
        }
    }

    private var dismissButton: some View {
        Button(action: dismissSheet) {
            Image(systemName: "xmark")
                .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
                .glassButton(shape: .circle)
        }
        .buttonStyle(.plain)
    }

    private func dismissSheet() {
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            coordinator.dismissConversionConfiguration()
        }
    }
}

// MARK: - Shared Convert Editor

struct CreateWorkspaceConvertEditor: View {
    @Environment(AIWorkspaceCoordinator.self) private var coordinator

    @Query(sort: \DeckModel.editedAt, order: .reverse) private var sourceDecks: [DeckModel]

    let managesSeedFromDeckList: Bool
    let showsDeckPicker: Bool
    let showsRuntimeSummary: Bool

    private var currentRequest: DeckCardConversionRequest? {
        coordinator.conversionSeed?.request
    }

    private var selectedSourceDeck: DeckModel? {
        guard let sourceDeckID = coordinator.conversionSeed?.sourceDeckID else { return nil }
        return sourceDecks.first(where: { $0.persistentModelID == sourceDeckID })
    }

    private var sourceDeckFingerprint: [Int] {
        sourceDecks.map { $0.persistentModelID.hashValue }
    }

    var body: some View {
        Group {
            if managesSeedFromDeckList && sourceDecks.isEmpty {
                ConversionUnavailableCard(
                    title: "No decks available",
                    message: "Create at least one deck before converting cards."
                )
            } else if let request = currentRequest {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                    if showsRuntimeSummary,
                       coordinator.conversionProgress != nil
                        || coordinator.conversionSummary != nil
                        || coordinator.conversionErrorMessage != nil {
                        AIWorkspaceRuntimeCard(coordinator: coordinator)
                    }

                    if showsDeckPicker {
                        sourceDeckPicker
                    }

                    ConversionSourceSection(
                        request: request,
                        tint: .orange,
                        onSelect: updateSourceKind
                    )
                    ConversionTargetSection(
                        request: request,
                        tint: .orange,
                        onSelect: updateTargetKind
                    )
                    ConversionDestinationSection(
                        request: request,
                        tint: .orange,
                        onSelect: updateDestination,
                        onUpdateTitle: updateNewDeckTitle
                    )
                }
            } else {
                ConversionUnavailableCard(
                    title: "Conversion unavailable",
                    message: managesSeedFromDeckList
                        ? "Pick a source deck to continue."
                        : "Reopen the sheet and try again."
                )
            }
        }
        .onAppear {
            seedInitialDeckIfNeeded()
        }
        .onChange(of: sourceDeckFingerprint) { _, _ in
            seedInitialDeckIfNeeded()
        }
    }

    @ViewBuilder
    private var sourceDeckPicker: some View {
        ConversionSectionCard(title: "Deck") {
            if let seed = coordinator.conversionSeed {
                if sourceDecks.count > 1 {
                    Menu {
                        ForEach(sourceDecks) { deck in
                            Button {
                                seedConversion(for: deck)
                            } label: {
                                if deck.persistentModelID == seed.sourceDeckID {
                                    Label(deck.title, systemImage: "checkmark")
                                } else {
                                    Text(deck.title)
                                }
                            }
                        }
                    } label: {
                        ConversionDeckRow(
                            title: seed.sourceDeckTitle,
                            subtitle: "\(selectedSourceDeck?.cardCount ?? 0) cards",
                            showsDisclosure: true
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    ConversionDeckRow(
                        title: seed.sourceDeckTitle,
                        subtitle: "\(selectedSourceDeck?.cardCount ?? 0) cards",
                        showsDisclosure: false
                    )
                }
            }
        }
    }

    private func seedInitialDeckIfNeeded() {
        guard managesSeedFromDeckList else { return }
        guard !sourceDecks.isEmpty else {
            coordinator.dismissConversionConfiguration()
            return
        }

        if let selectedSourceDeck {
            if currentRequest == nil {
                seedConversion(for: selectedSourceDeck)
            }
            return
        }

        if let firstDeck = sourceDecks.first {
            seedConversion(for: firstDeck)
        }
    }

    private func seedConversion(for deck: DeckModel) {
        let orderedCards = deck.cards.sorted {
            if $0.cardNumber == $1.cardNumber {
                return $0.createdAt < $1.createdAt
            }
            return $0.cardNumber < $1.cardNumber
        }
        let sources = orderedCards.map {
            DeckCardConversionSourceDescriptor(id: $0.persistentModelID, kind: $0.kind)
        }
        guard let request = DeckCardConversionRequest.makeWholeDeckRequest(
            sources: sources,
            deckTitle: deck.title,
            preferredSourceKind: currentRequest?.sourceKind,
            preferredTargetKind: currentRequest?.targetKind,
            existingRequest: currentRequest
        ) else {
            return
        }

        _ = coordinator.seedConversion(
            request: request,
            sourceDeck: deck,
            showsConfiguration: false,
            activatesWorkspaceContext: false
        )
    }

    private func updateSourceKind(_ kind: CardKind) {
        coordinator.updateConversionDraft { draft in
            draft.selectSourceKind(kind)
        }
    }

    private func updateTargetKind(_ kind: CardKind) {
        coordinator.updateConversionDraft { draft in
            draft.updateTargetKind(kind)
        }
    }

    private func updateDestination(_ destination: DeckCardConversionDestinationOption) {
        coordinator.updateConversionDraft { draft in
            draft.destination = destination
        }
    }

    private func updateNewDeckTitle(_ title: String) {
        coordinator.updateConversionDraft { draft in
            draft.newDeckTitle = title
        }
    }
}

// MARK: - Shared Conversion UI

private struct ConversionSourceSection: View {
    let request: DeckCardConversionRequest
    let tint: Color
    let onSelect: (CardKind) -> Void

    var body: some View {
        ConversionSectionCard(title: "Source") {
            if request.availableSourceKinds.count == 1,
               let sourceKind = request.selectedSourceKind {
                ConversionStaticSourceRow(
                    kind: sourceKind,
                    subtitle: "\(request.sourceCount(for: sourceKind)) card\(request.sourceCount(for: sourceKind) == 1 ? "" : "s")",
                    tint: tint
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(request.availableSourceKinds, id: \.self) { kind in
                        ConversionKindRow(
                            kind: kind,
                            subtitle: "\(request.sourceCount(for: kind)) card\(request.sourceCount(for: kind) == 1 ? "" : "s")",
                            isSelected: request.selectedSourceKind == kind,
                            tint: tint,
                            action: { onSelect(kind) }
                        )
                    }
                }
            }
        }
    }
}

private struct ConversionTargetSection: View {
    let request: DeckCardConversionRequest
    let tint: Color
    let onSelect: (CardKind) -> Void

    var body: some View {
        ConversionSectionCard(title: "Convert Into") {
            VStack(spacing: 10) {
                ForEach(CardKind.allCases, id: \.self) { kind in
                    let isAvailable = request.isTargetKindAvailable(kind)
                    ConversionKindRow(
                        kind: kind,
                        subtitle: conversionTargetSubtitle(kind),
                        isSelected: request.targetKind == kind,
                        isDisabled: !isAvailable,
                        tint: tint,
                        action: {
                            guard isAvailable else { return }
                            onSelect(kind)
                        }
                    )
                }
            }
        }
    }
}

private struct ConversionDestinationSection: View {
    let request: DeckCardConversionRequest
    let tint: Color
    let onSelect: (DeckCardConversionDestinationOption) -> Void
    let onUpdateTitle: (String) -> Void

    var body: some View {
        ConversionSectionCard(title: "Save Result") {
            VStack(spacing: UIConstants.Spacing.small) {
                ForEach(DeckCardConversionDestinationOption.allCases) { option in
                    ConversionOptionRow(
                        title: option.title,
                        subtitle: option.subtitle,
                        systemImage: option == .sameDeck
                            ? "square.stack.3d.up.fill"
                            : "square.stack.3d.up.badge.a.fill",
                        isSelected: request.destination == option,
                        tint: tint,
                        action: { onSelect(option) }
                    )
                }

                if request.destination == .newDeck {
                    TextField(
                        "New deck title",
                        text: Binding(
                            get: { request.newDeckTitle },
                            set: onUpdateTitle
                        )
                    )
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
                    }
                }
            }
        }
    }
}

struct ConversionStartBar: View {
    let request: DeckCardConversionRequest
    let tint: Color
    let horizontalInset: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: UIConstants.Spacing.small) {
                Text("Convert")
                    .font(.system(size: 17, weight: .bold, design: .rounded))

                Spacer(minLength: 0)

                Text("\(request.sourceCount) card\(request.sourceCount == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(request.canStart ? .white.opacity(0.88) : .secondary)
            }
            .foregroundStyle(request.canStart ? .white : .secondary)
            .padding(.horizontal, 18)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(buttonBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(buttonBorder, lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(!request.canStart)
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, UIConstants.Spacing.large)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.clear
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea()
        }
    }

    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                request.canStart
                    ? tint
                    : Color(uiColor: .tertiarySystemFill)
            )
    }

    private var buttonBorder: Color {
        request.canStart
            ? tint.opacity(0.35)
            : Color.white.opacity(0.06)
    }
}

private struct ConversionUnavailableCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionBackground)
    }
}

private struct ConversionSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.45)

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionBackground)
    }
}

private struct ConversionDeckRow: View {
    let title: String
    let subtitle: String
    let showsDisclosure: Bool

    var body: some View {
        HStack(spacing: 12) {
            conversionOptionIcon(systemImage: "rectangle.stack.fill", tint: ThemeManager.shared.accentColor.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if showsDisclosure {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
    }
}

private struct ConversionStaticSourceRow: View {
    let kind: CardKind
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            conversionOptionIcon(systemImage: kind.conversionSystemImage, tint: tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(kind.displayTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text("Auto")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
    }
}

private struct ConversionOptionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                conversionOptionIcon(systemImage: systemImage, tint: isSelected ? tint : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isSelected ? tint : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                rowBackground(
                    isSelected: isSelected,
                    tint: tint
                )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ConversionKindRow: View {
    let kind: CardKind
    let subtitle: String
    let isSelected: Bool
    var isDisabled: Bool = false
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                conversionOptionIcon(
                    systemImage: kind.conversionSystemImage,
                    tint: isDisabled ? .secondary.opacity(0.65) : (isSelected ? tint : .secondary)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.displayTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(isDisabled ? "Unavailable" : subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: indicatorSymbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(indicatorTint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                rowBackground(
                    isSelected: isSelected,
                    tint: tint
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.56 : 1)
    }

    private var indicatorSymbol: String {
        if isDisabled {
            return "slash.circle.fill"
        }
        return isSelected ? "checkmark.circle.fill" : "circle"
    }

    private var indicatorTint: Color {
        if isDisabled {
            return .secondary
        }
        return isSelected ? tint : .secondary
    }
}

private func conversionOptionIcon(systemImage: String, tint: Color) -> some View {
    ZStack {
        Circle()
            .fill(tint.opacity(0.14))
            .frame(width: 30, height: 30)

        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
    }
}

private func conversionSummaryChip(_ text: String, systemImage: String?) -> some View {
    HStack(spacing: 6) {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }

        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .lineLimit(1)
    }
    .foregroundStyle(.secondary)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color.white.opacity(0.05), in: Capsule())
}

private func conversionTargetSubtitle(_ kind: CardKind) -> String {
    switch kind {
    case .flashcard:
        return "Question and answer"
    case .match:
        return "Prompt and pair"
    case .quiz:
        return "Multiple choice"
    case .write:
        return "Typed answer"
    }
}

private var sectionBackground: some View {
    RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
        }
}

private var rowBackground: some View {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(uiColor: .tertiarySystemFill))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 0.6)
        }
}

private func rowBackground(isSelected: Bool, tint: Color) -> some View {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(isSelected ? tint.opacity(0.16) : Color(uiColor: .tertiarySystemFill))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected ? tint.opacity(0.28) : Color.white.opacity(0.04),
                    lineWidth: 0.8
                )
        }
}

struct AIWorkspaceFailureCard: View {
    let title: String
    let message: String
    let tint: Color
    var onRetry: (() -> Void)? = nil
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack(spacing: UIConstants.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: UIConstants.Spacing.small) {
                if let onRetry {
                    Button("Resume", action: onRetry)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(tint, in: Capsule())
                        .foregroundStyle(.white)
                }

                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                    .foregroundStyle(.primary)
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .padding(UIConstants.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
    }
}

// MARK: - Runtime Card

struct AIWorkspaceRuntimeCard: View {
    @Environment(\.modelContext) private var context

    @Bindable var coordinator: AIWorkspaceCoordinator
    var onOpenDestinationDeck: ((PersistentIdentifier) -> Void)? = nil

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    var body: some View {
        Group {
            if let errorMessage = coordinator.conversionErrorMessage {
                errorCard(errorMessage)
            } else if let progress = coordinator.conversionProgress {
                progressCard(progress)
            } else if let summary = coordinator.conversionSummary {
                summaryCard(summary)
            }
        }
    }

    private func progressCard(_ progress: DeckCardConversionProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversion")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.45)

            HStack(alignment: .firstTextBaseline, spacing: UIConstants.Spacing.small) {
                Text(coordinator.canResumeConversion ? "Conversion paused" : "Converting cards")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Text("\(progress.completedCount)/\(progress.totalCount)")
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(progress.statusMessage)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: progress.fractionCompleted)
                .tint(.orange)

            HStack(spacing: UIConstants.Spacing.small) {
                runtimeChip("\(progress.createdCount) created", tint: accent)
                runtimeChip("\(progress.skippedCount) skipped", tint: .secondary)
                if progress.failedCount > 0 {
                    runtimeChip("\(progress.failedCount) failed", tint: .red)
                }
            }

            if coordinator.canResumeConversion {
                HStack(spacing: UIConstants.Spacing.small) {
                    Button("Resume") {
                        coordinator.resumeConversion(context: context)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.06), in: Capsule())

                    Button("Dismiss") {
                        coordinator.dismissConversionOutcome()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.04), in: Capsule())
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
            }
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func summaryCard(_ summary: DeckCardConversionSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversion")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.45)

            Text(summary.createdCount == 1
                 ? "1 \(summary.targetKind.displayTitle) card created"
                 : "\(summary.createdCount) \(summary.targetKind.displayTitle) cards created")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(summary.destinationDeckTitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: UIConstants.Spacing.small) {
                runtimeChip("\(summary.skippedCount) skipped", tint: .secondary)
                if summary.failedCount > 0 {
                    runtimeChip("\(summary.failedCount) failed", tint: .red)
                }
            }

            HStack(spacing: UIConstants.Spacing.small) {
                if let destinationDeckID = summary.destinationDeckID,
                   summary.destination == .newDeck {
                    Button("Open Deck") {
                        onOpenDestinationDeck?(destinationDeckID)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }

                Button("Dismiss") {
                    coordinator.dismissConversionOutcome()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Color.white.opacity(0.04), in: Capsule())
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversion")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.45)

            Text("Conversion stopped")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: UIConstants.Spacing.small) {
                if coordinator.canResumeConversion {
                    Button("Resume") {
                        coordinator.resumeConversion(context: context)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }

                Button("Dismiss") {
                    coordinator.dismissConversionOutcome()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Color.white.opacity(0.04), in: Capsule())
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func runtimeChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.05), in: Capsule())
    }
}

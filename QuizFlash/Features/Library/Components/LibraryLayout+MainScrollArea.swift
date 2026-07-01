//
//  LibraryLayout+MainScrollArea.swift
//  QuizFlash
//
//  Scroll container, gesture wiring, and list/search content composition for LibraryLayout.
//

import SwiftUI
import OSLog
import UIKit

extension LibraryLayout {
    private static let stickyDebugLogger = QuizFlashLog.make("LibraryStickyLayout")

    var mainScrollArea: some View {
        ScrollView {
            VStack(spacing: 0) {
                ScrollPositionRestorer(
                    getOffset: { viewModel.savedScrollOffset },
                    onOffsetChange: { offset in
                        guard !viewModel.isSearching else { return }
                        viewModel.savedScrollOffset = offset
                        updateCollapsedTitleFallback(for: offset)
                    }
                )
                .frame(width: 0, height: 0)

                if viewModel.cachedDeckCount == 0 && viewModel.cachedGroupedDecks.isEmpty {
                    Spacer().frame(height: 40)
                }

                stackContent
                    .allowsHitTesting(!viewModel.isSearching)
            }
            .tabBarAutoHideOnScroll(enabled: !viewModel.isSearching && !viewModel.isSelecting)
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: 100)
                    .animation(.bottomChromeSpring, value: viewModel.isSelecting)
            }
        }
        .scrollDisabled(isSearchBrowseFrozen)
        .gesture(
            TapGesture().onEnded {
                guard viewModel.isSelecting && !isSearching else { return }
                withBottomChromeAnimation {
                    viewModel.exitSelectionMode()
                }
            }
        )
        .coordinateSpace(name: kLibraryScrollSpace)
        .overlay {
            ZStack(alignment: .top) {
                if viewModel.isSearching {
                    searchBackgroundBlurOverlay
                        .transition(.opacity)
                }

                if isSearchBrowseFrozen {
                    searchBrowseFreezeOverlay
                        .transition(.opacity)
                }

                if viewModel.isSearching {
                    searchResultsOverlay
                        .opacity(isSearchResultsPresented ? 1 : 0)
                        .allowsHitTesting(isSearchResultsPresented)
                }
            }
            .animation(searchBackdropAnimation, value: viewModel.isSearching)
            .animation(searchBackdropAnimation, value: isSearchBrowseFrozen)
            .animation(searchBackdropAnimation, value: isSearchResultsPresented)
        }
        .onPreferenceChange(LibrarySectionHeaderFramePreferenceKey.self) { frames in
            handleSectionHeaderDebugFrames(frames)
        }
        .onAppear {
            isCompactChromeRecoveryVisible = !viewModel.isSearching
            isCompactChromeSearchRecoveryAnimating = false
            compactChromeRecoverySectionHeaderID = nil
            viewModel.updateGroupedDecks(from: decks)
        }
        .onChange(of: decks) { _, newDecks in viewModel.updateGroupedDecks(from: newDecks) }
        .onChange(of: viewModel.sortOrder) { _, _ in viewModel.updateGroupedDecks(from: decks) }
        .onChange(of: appPreferences.languageRefreshKey) { _, _ in
            viewModel.updateGroupedDecks(from: decks)
        }
        .onChange(of: viewModel.isSearching) { _, isSearching in
            compactChromeAnimationResetTask?.cancel()

            if isSearching {
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    areCompactChromeVisibilityAnimationsEnabled = false
                    isCompactChromeSearchRecoveryAnimating = false
                    compactChromeRecoverySectionHeaderID = nil
                    hiddenSectionHeaderIDs = []
                }
                compactChromeAnimationResetTask = Task { @MainActor in
                    defer { compactChromeAnimationResetTask = nil }

                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled else { return }

                    areCompactChromeVisibilityAnimationsEnabled = true
                }
                return
            }

            compactChromeRecoverySectionHeaderID = visualPassedCompactTitleSectionID
            hiddenSectionHeaderIDs = browseStickyHiddenSectionHeaderIDs
            updateCollapsedTitleFallback(for: viewModel.savedScrollOffset)
            areCompactChromeVisibilityAnimationsEnabled = true
            isCompactChromeSearchRecoveryAnimating = true
            withAnimation(.circularProgressSpring) {
                isCompactChromeRecoveryVisible = true
            }

            compactChromeAnimationResetTask = Task { @MainActor in
                defer { compactChromeAnimationResetTask = nil }

                try? await Task.sleep(
                    for: .milliseconds(
                        Int(LibraryStickyBehavior.Handoff.compactChromeRecoverySettleDurationMs)
                    )
                )
                guard !Task.isCancelled else { return }

                isCompactChromeSearchRecoveryAnimating = false
            }
        }
        .onChange(of: isCollapsedTitleVisible) { _, isVisible in
            if !isVisible {
                Task { @MainActor in
                    collapsedTitleFrame = .zero
                }
            }
        }
        .onDisappear {
            compactChromeAnimationResetTask?.cancel()
            compactChromeAnimationResetTask = nil
            areCompactChromeVisibilityAnimationsEnabled = true
            isCompactChromeSearchRecoveryAnimating = false
        }
    }

    var searchBrowseFreezeOverlay: some View {
        LibrarySearchBrowseTouchShield {
            searchDismissRequestID += 1
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    var searchBackgroundBlurOverlay: some View {
        ZStack {
            BackgroundBlurView(radius: searchBrowseFreezeBlurRadius)
                .ignoresSafeArea()

            backgroundTheme
                .opacity(searchBrowseFreezeDimOpacity)
                .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    var stackContent: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            libraryHeroTitle
            browseListContent
        }
    }

    var libraryHeroTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            LargeScreenTitle(title: title)

            libraryDeckStatusLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, UIConstants.Layout.heroScreenEdgeInset)
        .padding(.top, libraryHeroTopPadding)
        .padding(.bottom, UIConstants.Spacing.extraLarge)
        .collapsibleTitleRevealAnchor(
            in: kLibraryChromeSpace,
            navigationBarBottomY: navigationBarBottomY,
            revealClearance: libraryCollapsedTitleRevealClearance,
            isVisible: $heroCollapsedTitleReady
        )
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .named(kLibraryChromeSpace)).maxY
                } action: { heroMaxY in
                    updateHeroCollapsedBaseline(with: heroMaxY)
                    updateCollapsedTitleFallback(for: viewModel.savedScrollOffset)
                }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: cloudSyncCoordinator.syncProgress)
    }

    @ViewBuilder
    private var libraryDeckStatusLine: some View {
        ZStack(alignment: .leading) {
            if let syncProgress = cloudSyncCoordinator.syncProgress {
                HStack(spacing: UIConstants.Spacing.small) {
                    Text(localized("Syncing…"))

                    ProgressActivityDots(color: themeManager.accentColor.color)
                        .frame(minWidth: 28)

                    Text(localizedFormat(
                        "%d/%d decks",
                        syncProgress.boundedCompletedItems,
                        syncProgress.totalItems
                    ))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: syncProgress.boundedCompletedItems)
                    .animation(.easeInOut(duration: 0.2), value: syncProgress.totalItems)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityLabel(
                    "\(localized("Syncing…")) \(localizedFormat("%d/%d decks", syncProgress.boundedCompletedItems, syncProgress.totalItems))"
                )
            } else {
                Text(libraryDeckCountText)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .accessibilityLabel(libraryDeckCountText)
            }
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(height: 20, alignment: .leading)
    }

    private var libraryDeckCountText: String {
        if viewModel.cachedDeckCount == 0 {
            return localized("No Decks")
        }
        if viewModel.cachedDeckCount == 1 {
            return localizedFormat("%d Deck", viewModel.cachedDeckCount)
        }
        return localizedFormat("%d Decks", viewModel.cachedDeckCount)
    }

    @ViewBuilder
    var searchDeckListContent: some View {
        if flatSearchDecks.isEmpty {
            LibraryEmptyStateView {
                router.activeTab = .create
            }
                .transition(.opacity)
        } else {
            LibraryFlatListView(
                decks: flatSearchDecks,
                showsContextMenus: false,
                isSelecting: viewModel.isSelecting,
                selectedDeckIDs: viewModel.selectedDecks,
                onNavigate: { deckID in
                    onDeckNavigate(deckID)
                },
                onToggleSelection: { deckID in
                    viewModel.toggleSelection(for: deckID)
                },
                onExport: { target in viewModel.exportSingleDeck(target, from: decks) },
                onMoveToFolder: { target in viewModel.deckToMove = target },
                onDelete: { target in viewModel.deckToDelete = target }
            )
            .padding(.top, UIConstants.Spacing.small)
            .transition(.opacity)
        }
    }

    var searchResultsContent: some View {
        SearchResultsView(
            results: viewModel.searchResults,
            query: viewModel.renderedSearchQuery,
            isSearchLoading: isSearchResultsLoadingPresentation,
            expandedDeckIDs: viewModel.expandedSearchDecks,
            onCardTap: onCardTap,
            onToggleDeckExpansion: { deckID in
                viewModel.toggleSearchDeckExpansion(for: deckID)
            }
        )
        .frame(maxWidth: searchContentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
    }

    @ViewBuilder
    var browseListContent: some View {
        if viewModel.cachedGroupedDecks.isEmpty {
            LibraryEmptyStateView {
                router.activeTab = .create
            }
                .transition(.opacity)
        } else {
            LibraryListView(
                groupedDecks: viewModel.cachedGroupedDecks,
                hiddenSectionHeaderIDs: activeLayoutPresentation == .browse
                    ? hiddenSectionHeaderIDs
                    : [],
                compactChromeRecoverySectionHeaderID: compactChromeRecoverySectionHeaderID,
                isCompactChromeRecoveryVisible: isCompactChromeRecoveryVisible,
                compactChromeVisibilityAnimation: compactChromeVisibilityAnimation,
                animateHiddenSectionHeaders: areCompactChromeVisibilityAnimationsEnabled && !viewModel.isSearching,
                showsContextMenus: !viewModel.isSearching,
                isSelecting: viewModel.isSelecting,
                selectedDeckIDs: viewModel.selectedDecks,
                onNavigate: { deckID in
                    onDeckNavigate(deckID)
                },
                onToggleSelection: { deckID in
                    viewModel.toggleSelection(for: deckID)
                },
                onExport: { target in viewModel.exportSingleDeck(target, from: decks) },
                onMoveToFolder: { target in viewModel.deckToMove = target },
                onDelete: { target in viewModel.deckToDelete = target }
            )
            .id("LibraryList-\(viewModel.cachedGroupedDecks.count)")
            .padding(.top, browseContentTopLift)
            .transition(.opacity)
        }
    }

    var flatSearchDecks: [LibraryDeckRowSnapshot] {
        viewModel.cachedGroupedDecks.flatMap(\.decks)
    }

    var searchResultsOverlay: some View {
        ZStack(alignment: .top) {
            backgroundTheme
                .ignoresSafeArea()
                .contentShape(Rectangle())

            ScrollView {
                searchResultsContent
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    func handleSectionHeaderDebugFrames(_ frames: [LibrarySectionHeaderFrame]) {
        guard !viewModel.isSearching else { return }
        // The real "push start" is when the native pinned section-header container
        // reaches the top of the scroll host and begins to be held in place by
        // LazyVStack(pinnedViews:). Measuring against the compact Library title was
        // fundamentally wrong because the compact chrome appears on a different path.
        let pushStartThresholdY = LibraryStickyBehavior.Debug.pinnedStartThresholdY
        let passedCompactTitleThresholdY = LibraryStickyBehavior.Debug.passedCompactTitleThresholdY
        let pushStartHeaderTopInset = LibraryStickyBehavior.Debug.pinnedStartHeaderTopInset
        let currentScrollOffset = viewModel.savedScrollOffset
        let scrollDelta = currentScrollOffset - (stickyDebugLastScrollOffset ?? currentScrollOffset)
        let isScrollingUp = scrollDelta < -0.25
        defer { stickyDebugLastScrollOffset = currentScrollOffset }

        let groupedFrames = Dictionary(grouping: frames, by: \.id)
        let flattenedCandidates = groupedFrames.values.compactMap { candidates in
            candidates.max(by: { $0.minY < $1.minY })
        }

        let topVisibleCandidate = flattenedCandidates
            .filter { $0.maxY > 0 }
            .min(by: { $0.minY < $1.minY })

        let pushStartCandidate: LibrarySectionHeaderFrame? =
            if let topVisibleCandidate {
                topVisibleCandidate.minY - pushStartHeaderTopInset <= pushStartThresholdY + 0.5
                    ? topVisibleCandidate
                    : nil
            } else {
                nil
            }

        let nextBelowCollapsedTitleCandidate: LibrarySectionHeaderFrame? =
            if let topVisibleCandidate {
                flattenedCandidates
                    .filter { $0.id != topVisibleCandidate.id }
                    .filter { $0.minY > topVisibleCandidate.minY }
                    .min(by: { $0.minY < $1.minY })
            } else {
                nil
            }

        let passedCompactTitleCandidate = flattenedCandidates
            .filter { $0.minY <= passedCompactTitleThresholdY + 0.5 }
            .max(by: { $0.minY < $1.minY })

        let visualPassedCompactTitleThresholdY =
            passedCompactTitleThresholdY
                + (isScrollingUp
                    ? LibraryStickyBehavior.Handoff.compactTitleRevealLagDistance
                    : LibraryStickyBehavior.Handoff.compactTitleHideLeadDistance)
        let visualPassedCompactTitleCandidate = flattenedCandidates
            .filter { $0.minY <= visualPassedCompactTitleThresholdY + 0.5 }
            .max(by: { $0.minY < $1.minY })

        let nextVisualPassedCompactTitleSectionID = viewModel.isSearching
            ? nil
            : visualPassedCompactTitleCandidate?.id

        if visualPassedCompactTitleSectionID != nextVisualPassedCompactTitleSectionID {
            visualPassedCompactTitleSectionID = nextVisualPassedCompactTitleSectionID
        }

        let targetHiddenSectionHeaderIDs: Set<String> = {
            guard let visualPassedCompactTitleSectionID else { return [] }
            return [visualPassedCompactTitleSectionID]
        }()

        if hiddenSectionHeaderIDs != targetHiddenSectionHeaderIDs {
            hiddenSectionHeaderIDs = targetHiddenSectionHeaderIDs
        }

        let previousPinnedSectionID = pinnedStartDebugSectionID
        if isScrollingUp,
           let previousPinnedSectionID,
           previousPinnedSectionID != pushStartCandidate?.id,
           let releasedCandidate = flattenedCandidates.first(where: { $0.id == previousPinnedSectionID }) {
            let labelMinY = String(format: "%.1f", releasedCandidate.minY)
            let labelMaxY = String(format: "%.1f", releasedCandidate.maxY)
            let containerMinY = String(
                format: "%.1f",
                releasedCandidate.minY - pushStartHeaderTopInset
            )
            let threshold = String(format: "%.1f", pushStartThresholdY)
            let candidateFrames = (groupedFrames[releasedCandidate.id] ?? [])
                .map { String(format: "%.1f", $0.minY) }
                .joined(separator: ",")

            Self.stickyDebugLogger.debug(
                "[LibraryStickyDebug] event=releasedFromPinned id=\"\(releasedCandidate.id)\" title=\"\(releasedCandidate.title)\" labelMinY=\(labelMinY) labelMaxY=\(labelMaxY) containerMinY=\(containerMinY) thresholdY=\(threshold) frames=[\(candidateFrames)]"
            )
        }

        if pinnedStartDebugSectionID != pushStartCandidate?.id {
            pinnedStartDebugSectionID = pushStartCandidate?.id

            if let pushStartCandidate {
                let labelMinY = String(format: "%.1f", pushStartCandidate.minY)
                let labelMaxY = String(format: "%.1f", pushStartCandidate.maxY)
                let containerMinY = String(
                    format: "%.1f",
                    pushStartCandidate.minY - pushStartHeaderTopInset
                )
                let threshold = String(format: "%.1f", pushStartThresholdY)
                let candidateFrames = (groupedFrames[pushStartCandidate.id] ?? [])
                    .map { String(format: "%.1f", $0.minY) }
                    .joined(separator: ",")
                let compactMinY = String(format: "%.1f", collapsedTitleFrame.minY)
                let compactMaxY = String(format: "%.1f", collapsedTitleFrame.maxY)
                let compactHeight = String(format: "%.1f", collapsedTitleFrame.height)
                let distanceToCompactBottom = String(
                    format: "%.1f",
                    (pushStartCandidate.minY - pushStartHeaderTopInset) - pushStartThresholdY
                )
                let nextTitle = nextBelowCollapsedTitleCandidate?.title ?? "nil"
                let nextMinY = String(
                    format: "%.1f",
                    nextBelowCollapsedTitleCandidate?.minY ?? .nan
                )
                let nextMaxY = String(
                    format: "%.1f",
                    nextBelowCollapsedTitleCandidate?.maxY ?? .nan
                )
                let distanceToNext = String(
                    format: "%.1f",
                    (nextBelowCollapsedTitleCandidate?.minY ?? .nan) - pushStartThresholdY
                )

                Self.stickyDebugLogger.debug(
                    "[LibraryStickyDebug] event=pinnedStart id=\"\(pushStartCandidate.id)\" title=\"\(pushStartCandidate.title)\" labelMinY=\(labelMinY) labelMaxY=\(labelMaxY) containerMinY=\(containerMinY) compactMinY=\(compactMinY) compactMaxY=\(compactMaxY) compactHeight=\(compactHeight) thresholdY=\(threshold) distanceToCompactBottom=\(distanceToCompactBottom) nextTitle=\"\(nextTitle)\" nextMinY=\(nextMinY) nextMaxY=\(nextMaxY) nextDistanceToCompactBottom=\(distanceToNext) frames=[\(candidateFrames)]"
                )
            }
        }

        let previousPassedCompactTitleID = passedCompactTitleDebugSectionID
        if isScrollingUp,
           let previousPassedCompactTitleID,
           previousPassedCompactTitleID != passedCompactTitleCandidate?.id,
           let returnedCandidate = flattenedCandidates.first(where: { $0.id == previousPassedCompactTitleID }) {
            let labelMinY = String(format: "%.1f", returnedCandidate.minY)
            let threshold = String(format: "%.1f", passedCompactTitleThresholdY)
            let candidateFrames = (groupedFrames[returnedCandidate.id] ?? [])
                .map { String(format: "%.1f", $0.minY) }
                .joined(separator: ",")

            Self.stickyDebugLogger.debug(
                "[LibraryStickyDebug] event=returnedBelowCompactTitle id=\"\(returnedCandidate.id)\" title=\"\(returnedCandidate.title)\" labelMinY=\(labelMinY) thresholdY=\(threshold) frames=[\(candidateFrames)]"
            )
        }

        guard passedCompactTitleDebugSectionID != passedCompactTitleCandidate?.id else { return }
        passedCompactTitleDebugSectionID = passedCompactTitleCandidate?.id

        guard let passedCompactTitleCandidate else { return }

        let labelMinY = String(format: "%.1f", passedCompactTitleCandidate.minY)
        let threshold = String(format: "%.1f", passedCompactTitleThresholdY)
        let candidateFrames = (groupedFrames[passedCompactTitleCandidate.id] ?? [])
            .map { String(format: "%.1f", $0.minY) }
            .joined(separator: ",")

        Self.stickyDebugLogger.debug(
            "[LibraryStickyDebug] event=passedCompactTitle id=\"\(passedCompactTitleCandidate.id)\" title=\"\(passedCompactTitleCandidate.title)\" labelMinY=\(labelMinY) thresholdY=\(threshold) frames=[\(candidateFrames)]"
        )
    }
}

// MARK: - Search Browse Touch Shield

private struct LibrarySearchBrowseTouchShield: UIViewRepresentable {
    let onTap: () -> Void

    func makeUIView(context: Context) -> ShieldView {
        let view = ShieldView()
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: ShieldView, context: Context) {
        uiView.onTap = onTap
    }

    final class ShieldView: UIView, UIGestureRecognizerDelegate {
        var onTap: (() -> Void)?

        private lazy var tapGesture: UITapGestureRecognizer = {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            gesture.delegate = self
            gesture.cancelsTouchesInView = true
            return gesture
        }()

        private lazy var panGesture: UIPanGestureRecognizer = {
            let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
            gesture.delegate = self
            gesture.cancelsTouchesInView = true
            gesture.maximumNumberOfTouches = 1
            return gesture
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isOpaque = false
            isUserInteractionEnabled = true
            addGestureRecognizer(tapGesture)
            addGestureRecognizer(panGesture)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc private func handleTap() {
            onTap?()
        }

        @objc private func handlePan() {
            // Consume search backdrop drags so iOS 17 does not forward them to
            // the frozen browse ScrollView behind the active search chrome.
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
}

//
//  LibraryLayout+MainScrollArea.swift
//  QuizFlash
//
//  Scroll container, gesture wiring, and list/search content composition for LibraryLayout.
//

import SwiftUI
import UIKit

extension LibraryLayout {
    var mainScrollArea: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(kLibraryTopAnchorID)

                    ScrollPositionRestorer(
                        getOffset: { viewModel.savedScrollOffset },
                        onOffsetChange: { offset in
                            guard !viewModel.isSearching && !showsSearchContent else { return }
                            viewModel.savedScrollOffset = offset
                            updateCollapsedTitleFallback(for: offset)
                        }
                    )
                    .frame(width: 0, height: 0)

                    if decks.isEmpty && viewModel.cachedGroupedDecks.isEmpty {
                        Spacer().frame(height: 40)
                    }

                    stackContent
                }
                .tabBarAutoHideOnScroll(enabled: !viewModel.isSearching && !viewModel.isSelecting)
                .safeAreaInset(edge: .bottom) {
                    Color.clear
                        .frame(height: 100)
                        .animation(.bottomChromeSpring, value: viewModel.isSelecting)
                }
            }
            .gesture(
                TapGesture().onEnded {
                    guard viewModel.isSelecting && !isSearching else { return }
                    withBottomChromeAnimation {
                        viewModel.exitSelectionMode()
                    }
                }
            )
            .coordinateSpace(name: kLibraryScrollSpace)
            .background {
                LibraryScrollViewResolver { scrollView in
                    resolvedLibraryScrollView = scrollView
                }
            }
            .overlay {
                if let searchTransitionSnapshot {
                    Image(uiImage: searchTransitionSnapshot)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .opacity(searchTransitionSnapshotOpacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onPreferenceChange(LibrarySectionHeaderFramePreferenceKey.self) { frames in
                handleSectionHeaderDebugFrames(frames)
            }
            .onAppear {
                showsSearchContent = viewModel.isSearching
                viewModel.updateGroupedDecks(from: decks)
            }
            .onChange(of: decks) { _, newDecks in viewModel.updateGroupedDecks(from: newDecks) }
            .onChange(of: viewModel.sortOrder) { _, _ in viewModel.updateGroupedDecks(from: decks) }
            .onChange(of: viewModel.isSearching) { _, isSearching in
                hiddenSectionHeaderIDs = []
                visualPassedCompactTitleSectionID = nil
                runSearchSurfaceTransition(using: scrollProxy, isSearching: isSearching)
            }
            .onChange(of: isCollapsedTitleVisible) { _, isVisible in
                if !isVisible {
                    Task { @MainActor in
                        collapsedTitleFrame = .zero
                    }
                }
            }
        }
    }

    @ViewBuilder
    var stackContent: some View {
        switch activeLayoutPresentation {
        case .browse:
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                libraryHeroTitle
                browseListContent
            }
        case .searchEmpty:
            LazyVStack(spacing: 0) {
                searchDeckListContent
            }
        case .searchResults:
            LazyVStack(spacing: 0) {
                searchResultsContent
            }
        }
    }

    var libraryHeroTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            LargeScreenTitle(title: title)

            Text(decks.count == 0 ? "No Decks" : "\(decks.count) Deck\(decks.count == 1 ? "" : "s")")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
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
    }

    @ViewBuilder
    var searchDeckListContent: some View {
        if flatSearchDecks.isEmpty {
            LibraryEmptyStateView()
                .transition(.opacity)
        } else {
            LibraryFlatListView(
                decks: flatSearchDecks,
                isSelecting: viewModel.isSelecting,
                selectedDeckIDs: viewModel.selectedDecks,
                activeActionMenuDeckID: viewModel.activeActionMenuDeckID,
                onNavigate: { deckID in
                    onDeckNavigate(deckID)
                },
                onToggleSelection: { deckID in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        viewModel.toggleSelection(for: deckID)
                    }
                },
                onToggleActionMenu: { id in
                    viewModel.activeActionMenuDeckID = id
                },
                onEditColor: { target in viewModel.deckToEditColor = target },
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
            isSearchLoading: viewModel.isSearchLoading,
            onCardTap: onCardTap
        )
        .frame(maxWidth: searchContentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
    }

    @ViewBuilder
    var browseListContent: some View {
        if viewModel.cachedGroupedDecks.isEmpty {
            LibraryEmptyStateView().transition(.opacity)
        } else {
            LibraryListView(
                groupedDecks: viewModel.cachedGroupedDecks,
                hiddenSectionHeaderIDs: activeLayoutPresentation == .browse
                    ? hiddenSectionHeaderIDs
                    : [],
                isSelecting: viewModel.isSelecting,
                selectedDeckIDs: viewModel.selectedDecks,
                activeActionMenuDeckID: viewModel.activeActionMenuDeckID,
                onNavigate: { deckID in
                    onDeckNavigate(deckID)
                },
                onToggleSelection: { deckID in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        viewModel.toggleSelection(for: deckID)
                    }
                },
                onToggleActionMenu: { id in
                    viewModel.activeActionMenuDeckID = id
                },
                onEditColor: { target in viewModel.deckToEditColor = target },
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

    func jumpToTop(using proxy: ScrollViewProxy) async {
        viewModel.savedScrollOffset = 0
        stickyDebugLastScrollOffset = 0
        let scrollToTop = {
            var transaction = Transaction()
            transaction.animation = nil

            withTransaction(transaction) {
                proxy.scrollTo(kLibraryTopAnchorID, anchor: .top)
            }
        }

        scrollToTop()
        await Task.yield()
        scrollToTop()
        try? await Task.sleep(for: .milliseconds(16))
        scrollToTop()
    }

    func captureSearchTransitionSnapshot() -> UIImage? {
        resolvedLibraryScrollView?.visibleSnapshotImage()
    }

    func runSearchSurfaceTransition(using proxy: ScrollViewProxy, isSearching: Bool) {
        Task { @MainActor in
            var instantTransaction = Transaction()
            instantTransaction.animation = nil
            let snapshot = captureSearchTransitionSnapshot()

            withTransaction(instantTransaction) {
                searchTransitionSnapshot = snapshot
                searchTransitionSnapshotOpacity = snapshot == nil ? 0 : 1
            }

            if isSearching {
                heroCollapsedTitleReady = false
                heroCollapsedTitleFallbackReady = false
            }

            await jumpToTop(using: proxy)
            guard viewModel.isSearching == isSearching else {
                withTransaction(instantTransaction) {
                    searchTransitionSnapshot = nil
                    searchTransitionSnapshotOpacity = 0
                }
                return
            }

            withTransaction(instantTransaction) {
                showsSearchContent = isSearching
            }

            await Task.yield()

            if !isSearching {
                updateCollapsedTitleFallback(for: viewModel.savedScrollOffset)
            }

            try? await Task.sleep(for: .milliseconds(16))
            guard viewModel.isSearching == isSearching else {
                withTransaction(instantTransaction) {
                    searchTransitionSnapshot = nil
                    searchTransitionSnapshotOpacity = 0
                }
                return
            }

            withAnimation(.easeOut(duration: 0.2)) {
                searchTransitionSnapshotOpacity = 0
            }

            try? await Task.sleep(for: .milliseconds(220))

            withTransaction(instantTransaction) {
                searchTransitionSnapshot = nil
            }
        }
    }

    func handleSectionHeaderDebugFrames(_ frames: [LibrarySectionHeaderFrame]) {
        guard !showsSearchContent else { return }
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

            print(
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

                print(
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

            print(
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

        print(
            "[LibraryStickyDebug] event=passedCompactTitle id=\"\(passedCompactTitleCandidate.id)\" title=\"\(passedCompactTitleCandidate.title)\" labelMinY=\(labelMinY) thresholdY=\(threshold) frames=[\(candidateFrames)]"
        )
    }
}

// MARK: - LibraryScrollViewResolver

private struct LibraryScrollViewResolver: UIViewRepresentable {
    let onResolve: @MainActor (UIScrollView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        Task { @MainActor in
            guard let scrollView = uiView.enclosingScrollView else { return }
            guard context.coordinator.resolvedScrollView !== scrollView else { return }

            context.coordinator.resolvedScrollView = scrollView
            onResolve(scrollView)
        }
    }

    final class Coordinator {
        weak var resolvedScrollView: UIScrollView?
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        sequence(first: superview, next: { $0?.superview })
            .first(where: { $0 is UIScrollView }) as? UIScrollView
    }
}

private extension UIScrollView {
    func visibleSnapshotImage() -> UIImage? {
        let renderSize = bounds.size
        guard renderSize.width > 0, renderSize.height > 0 else { return nil }

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.opaque = true

        let renderer = UIGraphicsImageRenderer(size: renderSize, format: rendererFormat)
        let renderBounds = CGRect(origin: .zero, size: renderSize)

        return renderer.image { context in
            if drawHierarchy(in: renderBounds, afterScreenUpdates: false) == false {
                layer.render(in: context.cgContext)
            }
        }
    }
}

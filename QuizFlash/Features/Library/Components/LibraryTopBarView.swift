//
//  LibraryTopBarView.swift
//  QuizFlash
//
//  Floating Library navigation chrome with a native-feeling search mode.
//

import SwiftUI

// MARK: - LibraryTopBarView

/// A floating top navigation bar tailored for the Library view and its derived contexts.
/// Preserves the app's existing chrome while presenting a quieter search state.
struct LibraryTopBarView: View {
    let title: String
    let deckCount: Int
    @Bindable var viewModel: LibraryViewModel
    let coordinateSpaceName: String
    let isCollapsedTitleVisible: Bool
    /// When non-nil, a back button is shown on the left instead of the deck-count pill.
    var onBack: (() -> Void)? = nil
    /// Text shown inside the back button pill. Only used when `onBack != nil`.
    var backLabel: String = "Library"
    var onBottomChange: (CGFloat) -> Void = { _ in }
    var onCollapsedTitleFrameChange: (CGRect) -> Void = { _ in }

    @Namespace var searchTransitionNamespace
    @State var searchIconBackgroundScale: CGFloat = 1
    @State var cancelOpacity: CGFloat = 0
    @State var ellipsisOpacity: CGFloat = 1
    @State var showsEllipsis = true
    @State var ellipsisHideTask: Task<Void, Never>?
    @State var searchDismissTask: Task<Void, Never>?
    @FocusState var isSearchFocused: Bool

    var accent: Color { ThemeManager.shared.accentColor.color }
    var retractionDuration: Double { 0.12 }
    var cancelFadeOutDuration: Double { 0.05 }
    var ellipsisFadeOutDuration: Double { 0.08 }
    var ellipsisFadeInDelay: Double { 0.04 }
    var ellipsisFadeInDuration: Double {
        retractionDuration - ellipsisFadeInDelay
    }
    var retractionTransition: Animation {
        .easeOut(duration: retractionDuration)
    }
    var expansionTransition: Animation {
        .snappy(duration: 0.2, extraBounce: 0.02)
    }
    var cancelFadeTransition: Animation {
        .linear(duration: cancelFadeOutDuration)
    }
    var ellipsisFadeOutTransition: Animation {
        .linear(duration: ellipsisFadeOutDuration)
    }
    var ellipsisFadeInTransition: Animation {
        .linear(duration: ellipsisFadeInDuration)
            .delay(ellipsisFadeInDelay)
    }

    var body: some View {
        ZStack(alignment: .top) {
            idleChromeRow
                .opacity(viewModel.isSearching ? 0 : 1)
                .allowsHitTesting(!viewModel.isSearching)
                .accessibilityHidden(viewModel.isSearching)

            searchBar
                .opacity(viewModel.isSearching ? 1 : 0)
                .allowsHitTesting(viewModel.isSearching)
                .accessibilityHidden(!viewModel.isSearching)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear {
            isSearchFocused = viewModel.isSearching
            cancelOpacity = viewModel.isSearching ? 1 : 0
            showsEllipsis = !viewModel.isSearching
            ellipsisOpacity = viewModel.isSearching ? 0 : 1
        }
        .onChange(of: viewModel.isSearching) { _, active in
            isSearchFocused = active
            if active {
                searchDismissTask?.cancel()
                searchDismissTask = nil
                cancelOpacity = 1
            } else {
                searchIconBackgroundScale = 1
                if searchDismissTask == nil {
                    withAnimation(cancelFadeTransition) {
                        cancelOpacity = 0
                    }
                    beginEllipsisFadeIn()
                }
            }
        }
        .onDisappear {
            ellipsisHideTask?.cancel()
            searchDismissTask?.cancel()
            isSearchFocused = false
        }
    }

    @MainActor
    func dismissSearch() {
        guard viewModel.isSearching else { return }

        searchDismissTask?.cancel()
        isSearchFocused = false

        withAnimation(cancelFadeTransition) {
            cancelOpacity = 0
        }
        beginEllipsisFadeIn()

        withAnimation(retractionTransition) {
            viewModel.isSearching = false
        }

        searchDismissTask = Task { @MainActor in
            defer { searchDismissTask = nil }

            try? await Task.sleep(
                for: .milliseconds(Int((retractionDuration * 1000).rounded(.up)) + 24)
            )
            guard !Task.isCancelled else { return }

            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                viewModel.clearSearch()
            }
        }
    }

    @MainActor
    func activateSearch() {
        guard !viewModel.isSearching else { return }

        cancelOpacity = 1
        beginEllipsisFadeOut()
        searchDismissTask?.cancel()

        withAnimation(expansionTransition) {
            searchIconBackgroundScale = 1
            viewModel.isSearching = true
        }

        Task { @MainActor in
            await Task.yield()
            guard viewModel.isSearching else { return }
            isSearchFocused = true
        }
    }

    @MainActor
    func beginEllipsisFadeOut() {
        ellipsisHideTask?.cancel()
        showsEllipsis = true

        withAnimation(ellipsisFadeOutTransition) {
            ellipsisOpacity = 0
        }

        ellipsisHideTask = Task { @MainActor in
            try? await Task.sleep(
                for: .milliseconds(Int((ellipsisFadeOutDuration * 1000).rounded(.up)))
            )
            guard !Task.isCancelled else { return }
            showsEllipsis = false
        }
    }

    @MainActor
    func beginEllipsisFadeIn() {
        ellipsisHideTask?.cancel()
        showsEllipsis = true
        ellipsisOpacity = 0

        withAnimation(ellipsisFadeInTransition) {
            ellipsisOpacity = 1
        }
    }
}

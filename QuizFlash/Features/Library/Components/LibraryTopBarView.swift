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

    @State var searchDismissTask: Task<Void, Never>?
    @State var searchFieldActivationTask: Task<Void, Never>?
    @State var searchFieldExpansionProgress: CGFloat = 0
    @State var isSearchFieldInteractive = false
    @State var leadingControlWidth: CGFloat = LibraryTopBarChromeMetrics.expandedHitTargetSize
    @State var trailingControlWidth: CGFloat = LibraryTopBarChromeMetrics.expandedHitTargetSize
    @FocusState var isSearchFocused: Bool

    var accent: Color { ThemeManager.shared.accentColor.color }
    var searchChromeTransitionDuration: Double { 0.2 }
    var searchFieldActivationDelay: Double { searchChromeTransitionDuration * 0.9 }
    var searchChromeTransition: Animation {
        .snappy(duration: searchChromeTransitionDuration, extraBounce: 0)
    }
    var chromeContainerHeight: CGFloat {
        UIConstants.Layout.deckNavigationTopPadding + UIConstants.Size.capsuleHeight
    }
    var searchProgress: CGFloat {
        min(max(searchFieldExpansionProgress, 0), 1)
    }

    var body: some View {
        chromeRow
            .topNavigationChrome(horizontalInset: UIConstants.Layout.compactScreenEdgeInset)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: chromeContainerHeight, alignment: .top)
            .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .named(coordinateSpaceName)).maxY
                } action: { newBottom in
                    onBottomChange(newBottom)
                }
            }
            .onAppear {
                searchFieldExpansionProgress = viewModel.isSearching ? 1 : 0
                isSearchFieldInteractive = viewModel.isSearching
                isSearchFocused = false
            }
            .onChange(of: viewModel.isSearching) { _, active in
                guard !active else {
                    scheduleSearchFieldActivation()
                    return
                }

                searchFieldActivationTask?.cancel()
                searchFieldActivationTask = nil
                searchFieldExpansionProgress = 0
                isSearchFieldInteractive = false
                isSearchFocused = false
            }
            .onDisappear {
                searchDismissTask?.cancel()
                searchFieldActivationTask?.cancel()
                isSearchFieldInteractive = false
                isSearchFocused = false
            }
    }

    @MainActor
    func dismissSearch() {
        guard viewModel.isSearching else { return }

        searchDismissTask?.cancel()
        searchFieldActivationTask?.cancel()
        isSearchFieldInteractive = false
        isSearchFocused = false

        withAnimation(searchChromeTransition) {
            searchFieldExpansionProgress = 0
        }

        searchDismissTask = Task { @MainActor in
            defer { searchDismissTask = nil }

            try? await Task.sleep(
                for: .milliseconds(Int((searchChromeTransitionDuration * 1000).rounded(.up)) + 24)
            )
            guard !Task.isCancelled else { return }

            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                searchFieldExpansionProgress = 0
                isSearchFieldInteractive = false
                viewModel.isSearching = false
                viewModel.clearSearch()
            }
        }
    }

    @MainActor
    func activateSearch() {
        guard !viewModel.isSearching else { return }

        searchDismissTask?.cancel()
        searchFieldActivationTask?.cancel()
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            viewModel.isSearching = true
        }
        searchFieldExpansionProgress = 0

        withAnimation(searchChromeTransition) {
            searchFieldExpansionProgress = 1
        }
        scheduleSearchFieldActivation()
    }

    @MainActor
    func scheduleSearchFieldActivation() {
        searchFieldActivationTask?.cancel()
        isSearchFieldInteractive = false

        searchFieldActivationTask = Task { @MainActor in
            defer { searchFieldActivationTask = nil }

            try? await Task.sleep(
                for: .milliseconds(Int((searchFieldActivationDelay * 1000).rounded(.up)))
            )
            guard !Task.isCancelled, viewModel.isSearching else { return }

            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                isSearchFieldInteractive = true
            }
            isSearchFocused = true
        }
    }
}

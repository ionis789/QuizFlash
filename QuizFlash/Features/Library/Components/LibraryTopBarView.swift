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

    @Namespace private var searchTransitionNamespace
    @State private var searchIconBackgroundScale: CGFloat = 1
    @State private var cancelOpacity: CGFloat = 0
    @State private var ellipsisOpacity: CGFloat = 1
    @State private var showsEllipsis = true
    @State private var ellipsisHideTask: Task<Void, Never>?
    @State private var searchDismissTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var retractionDuration: Double { 0.12 }
    private var cancelFadeOutDuration: Double { 0.05 }
    private var ellipsisFadeOutDuration: Double { 0.08 }
    private var ellipsisFadeInDelay: Double { 0.04 }
    private var ellipsisFadeInDuration: Double {
        retractionDuration - ellipsisFadeInDelay
    }
    private var retractionTransition: Animation {
        .easeOut(duration: retractionDuration)
    }
    private var expansionTransition: Animation {
        .snappy(duration: 0.2, extraBounce: 0.02)
    }
    private var cancelFadeTransition: Animation {
        .linear(duration: cancelFadeOutDuration)
    }
    private var ellipsisFadeOutTransition: Animation {
        .linear(duration: ellipsisFadeOutDuration)
    }
    private var ellipsisFadeInTransition: Animation {
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

    private var idleChromeRow: some View {
        CollapsibleTitleNavigationBar(
            coordinateSpaceName: coordinateSpaceName,
            onBottomChange: onBottomChange
        ) {
            leadingControl
                .fixedSize()
        } center: { maxTitleWidth in
            CollapsibleTitlePill(
                title: title,
                maxWidth: maxTitleWidth,
                isVisible: isCollapsedTitleVisible,
                fallbackTitle: "Library"
            )
        } trailing: {
            ZStack {
                ChromeCirclePlaceholder()

                if showsEllipsis {
                    moreSettingsButton
                        .opacity(ellipsisOpacity)
                        .allowsHitTesting(!viewModel.isSearching && ellipsisOpacity > 0.01)
                        .accessibilityHidden(viewModel.isSearching)
                        .transition(.identity)
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                }
            }
        }
    }

    // MARK: - Leading Control

    @ViewBuilder
    private var leadingControl: some View {
        if let onBackAction = onBack {
            LibraryTopBarBackButton(
                accent: accent,
                label: backLabel,
                action: onBackAction
            )
                .id("topbar.leading.back")
        } else {
            LibraryTopBarSearchIconButton(
                accent: accent,
                namespace: searchTransitionNamespace,
                isSearching: viewModel.isSearching,
                backgroundScale: searchIconBackgroundScale,
                action: activateSearch
            )
                .id("topbar.leading.search")
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: UIConstants.Spacing.small + 2) {
            searchField
            cancelButton
        }
        .frame(maxWidth: .infinity)
        .topNavigationChrome()
        .sensoryFeedback(.selection, trigger: isSearchFocused)
    }

    private var searchField: some View {
        HStack(spacing: UIConstants.Spacing.small + 2) {
            LibraryTopBarSearchGlyph(
                color: isSearchFocused ? accent : Color.secondary,
                namespace: searchTransitionNamespace,
                isSource: viewModel.isSearching
            )

            searchFieldContent

            trailingAccessory
        }
        .padding(.horizontal, UIConstants.Spacing.standard)
        .frame(height: UIConstants.Size.capsuleHeight)
        .contentShape(Capsule())
        .background {
            LibraryTopBarSearchFieldBackground(
                namespace: searchTransitionNamespace,
                isSource: viewModel.isSearching
            )
        }
        .clipShape(Capsule())
        .compositingGroup()
    }

    @ViewBuilder
    private var searchFieldContent: some View {
        if viewModel.isSearching {
            TextField("Search decks, cards, answers", text: $viewModel.searchText)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .tint(accent)
        } else {
            Text(viewModel.searchText.isEmpty ? "Search decks, cards, answers" : viewModel.searchText)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(viewModel.searchText.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .allowsHitTesting(false)
        }
    }

    private var cancelButton: some View {
        Button {
            dismissSearch()
        } label: {
            Text("Cancel")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(accent)
                .padding(.horizontal, UIConstants.Spacing.standard)
                .frame(minWidth: 84, minHeight: UIConstants.Size.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .opacity(cancelOpacity)
        .allowsHitTesting(cancelOpacity > 0.01)
        .transition(.opacity)
        .accessibilityLabel("Cancel search")
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        LibraryTopBarTrailingAccessory(
            searchText: viewModel.searchText,
            isSearchFocused: isSearchFocused,
            clearAction: {
                withAnimation(.easeInOut(duration: UIConstants.Animation.instant)) {
                    viewModel.searchText = ""
                }
            }
        )
    }

    @MainActor
    private func dismissSearch() {
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
    private func activateSearch() {
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
    private func beginEllipsisFadeOut() {
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
    private func beginEllipsisFadeIn() {
        ellipsisHideTask?.cancel()
        showsEllipsis = true
        ellipsisOpacity = 0

        withAnimation(ellipsisFadeInTransition) {
            ellipsisOpacity = 1
        }
    }

    private var moreSettingsButton: some View {
        LibraryTopBarMoreSettingsButton(accent: accent) {
            LibraryTopBarMenuContent(viewModel: viewModel) {
                withBottomChromeAnimation {
                    viewModel.enterSelectionMode()
                }
            }
        }
    }
}

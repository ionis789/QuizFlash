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

    var isScrolled: Bool = false
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
    private var searchGlyphSize: CGFloat { UIConstants.Size.actionIcon }
    private var searchGlyphFrame: CGFloat { UIConstants.Size.actionIcon }
    private var trailingControlReservation: CGFloat {
        UIConstants.Size.buttonHeight
            + UIConstants.Layout.compactScreenEdgeInset
            + UIConstants.Spacing.small
    }
    private var searchButtonHitSize: CGFloat {
        UIConstants.Size.actionButton
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
            backButton(action: onBackAction)
                .id("topbar.leading.back")
        } else {
            searchIcon
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
            searchGlyph(
                color: isSearchFocused ? accent : Color.secondary,
                isSource: viewModel.isSearching
            )

            searchFieldContent

            trailingAccessory
        }
        .padding(.horizontal, UIConstants.Spacing.standard)
        .frame(height: UIConstants.Size.capsuleHeight)
        .contentShape(Capsule())
        .background {
            searchFieldBackground(isSource: viewModel.isSearching)
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
        if viewModel.searchText.isEmpty {
            VoiceCommandGlyph(isActive: isSearchFocused)
                .accessibilityHidden(true)
        } else {
            Button {
                withAnimation(.easeInOut(duration: UIConstants.Animation.instant)) {
                    viewModel.searchText = ""
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background {
                        Circle()
                            .fill(Color(uiColor: .tertiarySystemFill))
                    }
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Clear search text")
        }
    }

    private func searchGlyph(color: Color, isSource: Bool) -> some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: searchGlyphSize, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: searchGlyphFrame, height: searchGlyphFrame)
            .matchedGeometryEffect(
                id: "library.topbar.searchGlyph",
                in: searchTransitionNamespace,
                isSource: isSource
            )
    }
    private var searchIcon: some View {
        Button {
            activateSearch()
        } label: {
            ZStack {
                Circle()
                    .fill(.clear)
                searchIconBackground
                    .frame(
                        width: UIConstants.Size.actionButton,
                        height: UIConstants.Size.actionButton
                    )
                    .scaleEffect(searchIconBackgroundScale)
                searchGlyph(color: accent, isSource: !viewModel.isSearching)
            }
            .frame(
                width: searchButtonHitSize,
                height: searchButtonHitSize
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("Search")
    }

    private var moreSettingsButton: some View {
        Menu { menuContent } label: {
            ZStack {
                Circle()
                    .fill(.clear)
                floatingCircleBackground
                    .frame(
                        width: UIConstants.Size.actionButton,
                        height: UIConstants.Size.actionButton
                    )
                Image(systemName: "ellipsis")
                    .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(
                width: searchButtonHitSize,
                height: searchButtonHitSize
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.75)
            }
            .clipShape(Circle())
            .compositingGroup()
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
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

    private var floatingCircleBackground: some View {
        Circle()
            .fill(.clear)
            .glassButton(shape: .circle)
    }

    private var searchIconBackground: some View {
        Circle()
            .fill(.clear)
            .glassButton(shape: .circle)
            .matchedGeometryEffect(
                id: "library.topbar.searchBackground",
                in: searchTransitionNamespace,
                isSource: !viewModel.isSearching
            )
    }

    private func searchFieldBackground(isSource: Bool) -> some View {
        Capsule()
            .fill(.clear)
            .glassButton(shape: .capsule)
            .matchedGeometryEffect(
                id: "library.topbar.searchBackground",
                in: searchTransitionNamespace,
                isSource: isSource
            )
    }

    // MARK: - Menu Content

    @ViewBuilder
    private var menuContent: some View {
        Button { viewModel.showFileImporter = true } label: {
            Label("Import Deck", systemImage: "square.and.arrow.down")
        }

        Button {
            withBottomChromeAnimation {
                viewModel.enterSelectionMode()
            }
        } label: {
            Label("Select", systemImage: "checkmark.circle")
        }
        .disabled(viewModel.isSelecting || viewModel.isSearching)

        Divider()

        Menu {
            ForEach(SortOrder.allCases, id: \.self) { order in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        viewModel.sortOrder = order
                    }
                } label: {
                    if viewModel.sortOrder == order {
                        Label(order.rawValue, systemImage: "checkmark")
                    } else {
                        Label(order.rawValue, systemImage: order.icon)
                    }
                }
            }
        } label: {
            Label("Sort By", systemImage: "arrow.up.arrow.down")
        }

        Menu {

        } label: {
            Label("Group By", systemImage: "arrow.up.arrow.down")
        }
    }

    // MARK: - Back Button

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.compact.left")
                    .font(.system(size: UIConstants.Size.navigationChromeIcon, weight: .bold))
                    .fontDesign(.rounded)
                Text(backLabel)
                    .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .bold))
                    .fontDesign(.rounded)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(height: UIConstants.Size.capsuleHeight)
            .foregroundStyle(accent)
            .glassButton(shape: .capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - VoiceCommandGlyph

private struct VoiceCommandGlyph: View {
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            Capsule().frame(width: 3, height: 9)
            Capsule().frame(width: 3, height: 14)
            Capsule().frame(width: 3, height: 11)
        }
        .foregroundStyle(isActive ? .primary : .secondary)
        .frame(width: 28, height: 28)
        .background {
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
        }
        .scaleEffect(isActive ? 1.02 : 1)
        .animation(.easeInOut(duration: UIConstants.Animation.instant), value: isActive)
    }
}

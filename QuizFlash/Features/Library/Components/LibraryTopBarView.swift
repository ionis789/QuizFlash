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

    var isScrolled: Bool = false
    /// When non-nil, a back button is shown on the left instead of the deck-count pill.
    var onBack: (() -> Void)? = nil
    /// Text shown inside the back button pill. Only used when `onBack != nil`.
    var backLabel: String = "Library"

    @Namespace private var searchTransitionNamespace
    @State private var searchIconBackgroundScale: CGFloat = 1
    @State private var cancelOpacity: CGFloat = 0
    @State private var ellipsisOpacity: CGFloat = 1
    @State private var showsEllipsis = true
    @State private var ellipsisHideTask: Task<Void, Never>?
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
        .linear(duration: retractionDuration)
    }
    private var expansionTransition: Animation {
        .interactiveSpring(response: 0.18, dampingFraction: 0.86, blendDuration: 0.04)
    }
    private var iconPressTransition: Animation {
        .easeOut(duration: 0.06)
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
            titleRow
                .opacity(viewModel.isSearching ? 0 : 1)
                .accessibilityHidden(viewModel.isSearching)

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
                cancelOpacity = 1
            } else {
                searchIconBackgroundScale = 1
                withAnimation(cancelFadeTransition) {
                    cancelOpacity = 0
                }
                beginEllipsisFadeIn()
            }
        }
        .onDisappear {
            ellipsisHideTask?.cancel()
        }
    }

    // MARK: - Title Row

    private var titleRow: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            deckCountPill
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, trailingControlReservation)
        .padding(.top, UIConstants.Layout.deckNavigationTopPadding)
        .padding(.bottom, UIConstants.Spacing.small + 2)
    }

    private var idleChromeRow: some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
            leadingControl
                .fixedSize()

            Spacer(minLength: 0)

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .topNavigationChrome()
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

            TextField("Search decks, cards, answers", text: $viewModel.searchText)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .tint(accent)

            trailingAccessory
        }
        .padding(.horizontal, UIConstants.Spacing.standard)
        .frame(height: UIConstants.Size.capsuleHeight)
        .contentShape(Capsule())
        .background {
            searchFieldBackground(isSource: viewModel.isSearching)
        }
    }

    private var cancelButton: some View {
        Button {
            withAnimation(retractionTransition) {
                viewModel.clearSearch()
                isSearchFocused = false
            }
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

    // MARK: - Subviews

    private var deckCountPill: some View {
        Text(deckCount == 0 ? "No Decks" : "\(deckCount) Deck\(deckCount == 1 ? "" : "s")")
            .font(.system(size: 13, weight: .bold))
            .fontDesign(.rounded)
            .foregroundStyle(.secondary)
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
                floatingCircleBackground
                Image(systemName: "ellipsis")
                    .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
            .contentShape(Circle())
        }
    }

    @MainActor
    private func activateSearch() {
        guard !viewModel.isSearching else { return }

        cancelOpacity = 1
        beginEllipsisFadeOut()
        withAnimation(iconPressTransition) {
            searchIconBackgroundScale = 0.96
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(18))
            withAnimation(expansionTransition) {
                searchIconBackgroundScale = 1
                viewModel.isSearching = true
                isSearchFocused = true
            }
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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                viewModel.isSelecting = true
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

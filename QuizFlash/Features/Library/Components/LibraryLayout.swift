//
//  LibraryLayout.swift
//  QuizFlash

import SwiftUI
import SwiftData

// MARK: - LibraryLayout

let kLibraryChromeSpace = "libraryChrome"

/// Shared layout engine for `LibraryView` and `FolderView`.
/// Handles coordinate spaces, structural overlays, safe area computation,
/// and delegates all business logic to `LibraryViewModel`.
struct LibraryLayout: View {
    @Environment(AppPreferences.self) var appPreferences
    @Environment(ThemeManager.self) var themeManager

    let decks: [DeckModel]
    let folders: [FolderModel]
    @Bindable var viewModel: LibraryViewModel
    let router: NavigationManager

    // The screen title displayed in LibraryTopBarView.
    // App-owned titles should arrive localized, while user-authored folder names
    // should arrive as verbatim runtime text.
    let title: AppTextValue
    let titleFallback: String

    let onCardTap: (PersistentIdentifier) -> Void
    let onDeckNavigate: (PersistentIdentifier) -> Void
    let onDeleteSelected: () -> Void
    /// Non-nil when the layout is hosted inside a pushed screen (e.g. FolderView).
    /// Wired to the host's dismiss action so LibraryTopBarView can render a back button.
    var onBack: (() -> Void)? = nil
    /// Label shown in the back button pill. Ignored when onBack is nil.
    var backLabel: String = "Library"

    @Binding var isSearching: Bool
    @Binding var searchText: String

    // ── State ──

    /// Height of LibraryTopBarView measured live.
    @State var navigationBarBottomY: CGFloat = 0
    @State var collapsedTitleFrame: CGRect = .zero
    @State var heroCollapsedTitleReady = false
    @State var heroCollapsedTitleFallbackReady = false
    @State var heroCollapsedBaselineMaxY: CGFloat = 0
    @State var stickyDebugLastScrollOffset: CGFloat?
    @State var hiddenSectionHeaderIDs: Set<String> = []
    @State var compactChromeAnimationResetTask: Task<Void, Never>?
    @State var areCompactChromeVisibilityAnimationsEnabled = true
    @State var isCompactChromeRecoveryVisible = true
    @State var isCompactChromeSearchRecoveryAnimating = false
    @State var compactChromeRecoverySectionHeaderID: String?
    @State var visualPassedCompactTitleSectionID: String?
    @State var pinnedStartDebugSectionID: String?
    @State var passedCompactTitleDebugSectionID: String?
    @State var searchDismissRequestID = 0
    /// safeAreaInsets.top captured from the root body context (non-zero here).
    @State var safeTop: CGFloat = 0

    /// Safe-area bottom reported by SwiftUI at the ZStack level.
    /// Inside TabView this includes the UITabBar height (~49 pt) on top of the
    /// physical home-indicator inset, regardless of whether UITabBar is hidden.
    @State var viewSafeBottom: CGFloat = 0

    /// Physical screen safe-area bottom (home indicator only, ~34 pt).
    /// Read directly from UIWindow so it is never inflated by TabView's layout.
    @State var physicalSafeBottom: CGFloat = 0
    var backgroundTheme: Color { themeManager.screenBackground }
    var locale: Locale { appPreferences.resolvedLocale }
    var searchContentMaxWidth: CGFloat { UIConstants.Layout.librarySearchContentMaxWidth }
    var trimmedSearchText: String {
        viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var isSearchResultsPresented: Bool {
        viewModel.isSearching && !trimmedSearchText.isEmpty
    }
    var isSearchBrowseFrozen: Bool {
        viewModel.isSearching && trimmedSearchText.isEmpty
    }
    var isSearchResultsLoadingPresentation: Bool {
        viewModel.isSearchLoading
            || viewModel.renderedSearchQuery != trimmedSearchText
            || (viewModel.searchResults.isEmpty && !viewModel.isNoMatchReady)
    }
    var searchBackdropAnimation: Animation {
        .easeInOut(duration: 0.16)
    }
    var searchBrowseFreezeBlurRadius: CGFloat {
        18
    }
    var searchBrowseFreezeDimOpacity: CGFloat {
        0.12
    }
    var browseStickyHiddenSectionHeaderIDs: Set<String> {
        Set([visualPassedCompactTitleSectionID].compactMap { $0 })
    }
    var activeLayoutPresentation: LibrarySearchPresentation {
        isSearchResultsPresented ? .searchResults : .browse
    }
    var structuralTopEdgeShadowHeight: CGFloat {
        if navigationBarBottomY > 0 {
            return navigationBarBottomY
        }
        return safeTop + UIConstants.Layout.topEdgeShadowHeight
    }
    var activeTopEdgeShadowHeight: CGFloat {
        structuralTopEdgeShadowHeight
    }
    var topChromeInsetSpacing: CGFloat {
        switch activeLayoutPresentation {
        case .browse:
            return libraryCompactDateContentSpacing
        case .searchEmpty, .searchResults:
            return 0
        }
    }
    var libraryHeroTopPadding: CGFloat {
        UIConstants.Spacing.extraLarge
            + LibraryStickyBehavior.Chrome.heroTopPaddingBase
            + abs(min(0, libraryCompactDateContentSpacing))
    }
    var browseContentTopLift: CGFloat {
        0
    }
    var libraryCompactDateContentSpacing: CGFloat {
        LibraryStickyBehavior.Chrome.compactDateSpacing
    }
    var libraryCollapsedTitleRevealClearance: CGFloat {
        UIConstants.Layout.deckHeroPillRevealClearance
            + LibraryStickyBehavior.Chrome.collapsedTitleRevealExtraClearance
    }
    var compactChromeVisibilityAnimation: Animation? {
        guard areCompactChromeVisibilityAnimationsEnabled else { return nil }
        return isCompactChromeSearchRecoveryAnimating ? .circularProgressSpring : nil
    }

    var isCollapsedTitleVisible: Bool {
        return heroCollapsedTitleReady || heroCollapsedTitleFallbackReady
    }

    var collapsedTitleFallbackShowThreshold: CGFloat {
        guard heroCollapsedBaselineMaxY > 0 else { return .greatestFiniteMagnitude }
        let revealLine = navigationBarBottomY - libraryCollapsedTitleRevealClearance
        return max(
            0,
            heroCollapsedBaselineMaxY
                - revealLine
                + LibraryStickyBehavior.Chrome.collapsedTitleFallbackShowOffset
        )
    }

    var collapsedTitleFallbackHideThreshold: CGFloat {
        max(
            0,
            collapsedTitleFallbackShowThreshold
                - LibraryStickyBehavior.Chrome.collapsedTitleFallbackHideHysteresis
        )
    }

    func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    func localizedFormat(_ value: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = AppLocalization.string(value, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                // Full-bleed background. Empty-space tap-to-dismiss is handled
                // via a pure SwiftUI background gesture on the scroll content VStack.
                // Child view gestures (deck row Buttons) take priority — no UIKit needed.
                backgroundTheme
                    .ignoresSafeArea()
                    .zIndex(-1)

                mainScrollArea
            }
            .screenTopEdgeShadow(
                topHeight: activeTopEdgeShadowHeight,
                topRevealProgress: isCollapsedTitleVisible ? 1 : 0,
                debugScreenID: "library.root",
                fullScreenFillProgress: 0,
                fullScreenDimOpacity: 0,
                fullScreenBlurRadius: 0,
                style: .progressiveBlur()
            )
            .animation(searchBackdropAnimation, value: viewModel.isSearching)
            .animation(searchBackdropAnimation, value: isSearchBrowseFrozen)

            if viewModel.isSelecting && !isSearching {
                BottomChromeContainer(
                    kind: .selection,
                    bottomPadding: BottomChromeInsets.persistent
                ) {
                    LibrarySelectionBarView(
                        viewModel: viewModel,
                        decks: decks,
                        onDeleteTap: { viewModel.showDeleteConfirmation = true },
                        onMoveTap: { viewModel.showMoveConfirmation = true }
                    )
                }
                .transition(.bottomChrome)
                .zIndex(10)
            }

            if viewModel.isImporting || viewModel.isExporting {
                LibraryLoadingOverlay()
                    .zIndex(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .coordinateSpace(name: kLibraryChromeSpace)
            .animation(.bottomChromeSpring, value: viewModel.isSelecting)
            .safeAreaInset(edge: .top, spacing: topChromeInsetSpacing) {
            LibraryTopBarView(
                title: title,
                titleFallback: titleFallback,
                deckCount: viewModel.cachedDeckCount,
                viewModel: viewModel,
                coordinateSpaceName: kLibraryChromeSpace,
                isCollapsedTitleVisible: isCollapsedTitleVisible,
                isCompactChromeRecoveryVisible: isCompactChromeRecoveryVisible,
                compactChromeVisibilityAnimation: compactChromeVisibilityAnimation,
                animateCollapsedTitleVisibility: areCompactChromeVisibilityAnimationsEnabled,
                dismissSearchRequestID: searchDismissRequestID,
                onBack: onBack,
                backLabel: backLabel,
                onBottomChange: { newBottom in
                    if abs(navigationBarBottomY - newBottom) > 0.5 {
                        navigationBarBottomY = newBottom
                    }
                },
                onCollapsedTitleFrameChange: { newFrame in
                    if collapsedTitleFrame.integral != newFrame.integral {
                        collapsedTitleFrame = newFrame
                    }
                }
            )
            .zIndex(6)
        }
            .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                    safeTop = geo.safeAreaInsets.top
                    viewSafeBottom = geo.safeAreaInsets.bottom
                    physicalSafeBottom = UIApplication.shared
                        .connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?.windows
                        .first(where: { $0.isKeyWindow })?
                        .safeAreaInsets.bottom ?? 0
                }
                    .onChange(of: geo.safeAreaInsets.top) { _, v in safeTop = v }
                    .onChange(of: geo.safeAreaInsets.bottom) { _, v in
                    viewSafeBottom = v
                    physicalSafeBottom = UIApplication.shared
                        .connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?.windows
                        .first(where: { $0.isKeyWindow })?
                        .safeAreaInsets.bottom ?? 0
                }
            }
        }
    }

}

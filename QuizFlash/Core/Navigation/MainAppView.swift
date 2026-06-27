//
//  MainAppView.swift
//  QuizFlash
//
//  Abstract:
//  The application's root coordinator. Manages a single NavigationStack wrapping
//  a TabView, with a decoupled floating tab bar rendered in a ZStack overlay.
//
//  Navigation contract:
//  - Each tab owns its own NavigationPath stored in `pathPerTab`. Switching tabs
//    suspends the current tab's path and restores the destination tab's path,
//    preserving deep navigation state (e.g. an open folder on the Home tab)
//    across tab switches.
//  - Tab bar visibility is driven exclusively by TabBarVisibilityKey preferences
//    propagated from child views. `.implicit` resolves to visible; views that
//    need to suppress the bar (e.g. DeckView) must opt out via
//    `.customTabBarVisibility(.hidden)`.
//  - The tab bar appearance animation is symmetric: both hide and show are
//    spring-animated via property mutation (opacity + offset) on a view that
//    always lives in the hierarchy. This avoids the visual race condition caused
//    by inserting/removing the bar view mid-transition.
//  - Tapping the currently active tab pops to root (mirrors UITabBarController).
//    Cross-tab capsule motion now starts in UIKit and commits the actual
//    `TabView` switch shortly afterwards, reducing animation contention with
//    heavy destination screens such as `DeckView`.
//  - The activation handler is gated on `isTabBarVisible` so that phantom UIKit
//    tab events fired by the hidden native UITabBar cannot trigger `popToRoot()`.
//

import SwiftUI
import SwiftData

struct MainAppView: View {
    // MARK: - State

    @Environment(\.modelContext) private var modelContext
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(DevelopmentPreferences.self) private var developmentPreferences
    @Environment(AppMigrationStore.self) private var appMigrationStore
    @Environment(ThemeManager.self) private var themeManager

    @State private var router = NavigationManager()
    @State private var aiWorkspaceCoordinator = AIWorkspaceCoordinator()
    @State private var keyboardMonitor = KeyboardMonitor.shared
    @State private var customContextMenuCoordinator = CustomContextMenuCoordinator()
    @State private var customContextMenuSourceRegistry = CustomContextMenuSourceRegistry()

    /// The long-lived view model for the Library tab.
    /// Instantiated at the root level and injected into the environment so that
    /// expensive operations (search cache, grouping) persist across navigation
    /// and tab-switching without redundant recomputation.
    @State private var libraryViewModel = LibraryViewModel()
    @State private var showMigrationError = false
    @State private var migrationErrorMessage = ""

    /// The visibility rule currently reported by the frontmost child view.
    @State private var tabBarRule: TabBarVisibilityRule = .implicit
    /// Active custom-sheet requests that temporarily hide the floating tab bar.
    @State private var sheetHiddenTabBarRequestIDs: Set<UUID> = []
    /// User-driven compact state sourced from the active scroll surface.
    @State private var isTabBarCompactedByScroll = false
    /// Short scale pulse used to acknowledge repeated overscroll at a content edge.
    @State private var tabBarEdgeBounceScale: CGFloat = 1
    @State private var tabBarEdgeBounceTask: Task<Void, Never>?

    private static let tabBarBlurDebugScreenID = EdgeShadowDebugScreenID.tabBarBlur

    // MARK: - Init

    init() {
        // Suppress the native UIKit tab bar via the appearance proxy.
        // This hides new instances visually, but does NOT disable hit-testing
        // or recalculate safe area on the live instance already in the hierarchy.
        // NativeTabBarConfigurator handles both of those concerns directly.
        UITabBar.appearance().isHidden = true

        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil
        appearance.shadowColor = .clear

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    // MARK: - Computed Properties

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var isCustomContextMenuVisible: Bool {
        customContextMenuCoordinator.presentation != nil
    }

    /// Resolves the active tab bar visibility rule to a Bool.
    ///
    /// Decision table:
    ///   `.visible`  → always show  (e.g. FolderView, which is always pushed)
    ///   `.hidden`   → always hide  (e.g. DeckView, full-screen flows)
    ///   `.implicit` → show by default
    private var isTabBarLayoutVisible: Bool {
        guard !keyboardMonitor.isVisible else { return false }
        guard sheetHiddenTabBarRequestIDs.isEmpty else { return false }
        switch tabBarRule {
        case .visible: return true
        case .hidden: return false
        case .implicit: return true
        }
    }

    /// Visual visibility for the floating custom tab bar.
    /// During a context menu we hide only the overlay chrome, not the structural
    /// UITabBar safe-area contribution, so source rows do not reflow mid-press.
    private var isFloatingTabBarVisible: Bool {
        isTabBarLayoutVisible && !isCustomContextMenuVisible
    }

    private var isAIWorkspaceVisible: Bool {
        router.activeTab == .create
    }

    private var appFeatures: AppFeatures {
        .current
    }

    /// The raw `TabView` selection binding. Tab semantics such as reselect and
    /// delayed cross-tab commits are handled by `CustomTabBar` instead.
    private var tabViewSelection: Binding<AppTabBar> {
        Binding(
            get: { router.activeTab },
            set: { router.activeTab = $0 }
        )
    }

    /// Handles a tab activation after the UIKit interaction layer decides the
    /// switch should commit into SwiftUI.
    private func handleTabActivation(_ tappedTab: AppTabBar) {
        // Block all native UITabBar events when the custom bar is not visible.
        // The hidden UITabBar still receives taps and would otherwise fire
        // popToRoot() or switch tabs unexpectedly.
        guard isFloatingTabBarVisible else { return }

        if tappedTab == router.activeTab {
            // Re-tap: pop to root without leaving the tab.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                router.popToRoot()
            }
        } else {
            router.activeTab = tappedTab
        }
    }

    private func handleTabBarAutoHideAction(_ action: TabBarAutoHideAction) {
        switch action {
        case .show:
            guard isTabBarCompactedByScroll else { return }
            Task { @MainActor in
                withAnimation(.bottomChromeSpring) {
                    isTabBarCompactedByScroll = false
                }
            }
        case .hide:
            guard !isTabBarCompactedByScroll else { return }
            guard !keyboardMonitor.isVisible else { return }
            guard tabBarRule != .hidden else { return }
            Task { @MainActor in
                withAnimation(.bottomChromeSpring) {
                    isTabBarCompactedByScroll = true
                }
            }
        case .bounceAtEdge:
            handleTabBarEdgeBounce()
        }
    }

    private func handleTabBarEdgeBounce() {
        guard isTabBarLayoutVisible else { return }

        tabBarEdgeBounceTask?.cancel()
        let wasCompacted = isTabBarCompactedByScroll

        if wasCompacted {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isTabBarCompactedByScroll = false
                tabBarEdgeBounceScale = UIConstants.Layout.bottomChromeCompactScale
            }
        } else {
            withAnimation(.bottomChromeSpring) {
                tabBarEdgeBounceScale = UIConstants.Layout.bottomChromeCompactScale
            }
        }

        tabBarEdgeBounceTask = Task { @MainActor in
            if !wasCompacted {
                try? await Task.sleep(for: .milliseconds(110))
                guard !Task.isCancelled else { return }
            }

            withAnimation(.bottomChromeSpring) {
                tabBarEdgeBounceScale = 1
            }
        }
    }

    private func handleSheetTabBarVisibilityRequest(id: UUID, isHidden: Bool) {
        let alreadyHidden = sheetHiddenTabBarRequestIDs.contains(id)
        guard alreadyHidden != isHidden else { return }

        withAnimation(.bottomChromeSpring) {
            if isHidden {
                sheetHiddenTabBarRequestIDs.insert(id)
            } else {
                sheetHiddenTabBarRequestIDs.remove(id)
            }
        }
    }

    private func resetTabBarCompactIfNeeded() {
        tabBarEdgeBounceTask?.cancel()
        guard isTabBarCompactedByScroll || tabBarEdgeBounceScale != 1 else { return }
        Task { @MainActor in
            withAnimation(.bottomChromeSpring) {
                isTabBarCompactedByScroll = false
                tabBarEdgeBounceScale = 1
            }
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            // The GeometryReader gives the floating bar access to the real root
            // container width. Without that, the bar can inherit the TabView host's
            // safe-area-adjusted width in landscape and look subtly off-center on iPhone.

            ZStack(alignment: isPad ? .bottomTrailing : .bottom) {
                themeManager.screenBackground
                    .ignoresSafeArea()

                // ── Navigation Layer ─────────────────────────────────────────────
                rootTabView
                    .environment(\.tabBarScrollAutoHideAction, handleTabBarAutoHideAction)
                    .environment(
                        \.tabBarSheetVisibilityAction,
                        TabBarSheetVisibilityAction(update: handleSheetTabBarVisibilityRequest)
                    )
                    .environment(\.bottomChromeIsVisible, isTabBarLayoutVisible)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .dismissKeyboardOnBackgroundTap(enabled: keyboardMonitor.isVisible)
                    // Propagate tab bar visibility changes with an explicit spring so the
                    // animation context is preserved regardless of where the preference
                    // change fires. Without withAnimation here, mutations placed inside
                    // DispatchQueue.main.async run in a new SwiftUI transaction that is
                    // decoupled from the .animation modifier on the ZStack — the tab bar
                    // would snap instead of spring.
                    .onPreferenceChange(TabBarVisibilityKey.self) { rule in
                        Task { @MainActor in
                            withAnimation(.bottomChromeSpring) {
                                self.tabBarRule = rule
                            }
                        }
                    }
                    // Directly controls the live UITabBar instance created by UIKit for
                    // SwiftUI's TabView. The appearance proxy only affects new instances;
                    // this configurator applies isHidden and isUserInteractionEnabled on
                    // the existing object so that safe area recalculates immediately and
                    // hit-testing is disabled, preventing phantom _tabBarItemClicked: events.
                    .configureNativeTabBar(visible: isTabBarLayoutVisible)
                    .onChange(of: router.activeTab) { _, _ in
                        resetTabBarCompactIfNeeded()
                    }
                    .onChange(of: keyboardMonitor.isVisible) { _, isVisible in
                        if isVisible {
                            resetTabBarCompactIfNeeded()
                        }
                    }
                    .onChange(of: tabBarRule) { _, rule in
                        if rule == .hidden {
                            resetTabBarCompactIfNeeded()
                        }
                    }

                // ── Custom Tab Bar Layer ─────────────────────────────────────────
                // The bar is always present in the view hierarchy. Visibility is
                // expressed through property animation (opacity + vertical offset)
                // rather than conditional insertion.
                //
                // Rationale: inserting the bar view mid-transition (e.g. while the
                // selection bar is still animating out) causes a race condition where
                // the bar slides in beneath the selection overlay, invisible, and then
                // snaps to its final position — producing an asymmetric animation.
                // Keeping the view alive and animating its properties avoids that
                // race entirely.
                tabBarChrome(in: proxy)
                    .zIndex(1)

                tabBarBlurDebugControls(in: proxy)
                    .zIndex(3)

                if let status = aiWorkspaceCoordinator.floatingStatus,
                   !keyboardMonitor.isVisible,
                   aiWorkspaceCoordinator.shouldShowFloatingStatus(isWorkspaceVisible: isAIWorkspaceVisible) {
                    FloatingAIWorkspaceStatusMenu(
                        status: status,
                        bottomPadding: isTabBarLayoutVisible
                            ? UIConstants.Layout.bottomChromeBottomPadding
                            + UIConstants.Size.bottomChromeBarHeight
                            + UIConstants.Spacing.medium
                            : proxy.safeAreaInsets.bottom + UIConstants.Spacing.large,
                        onOpenWorkspace: {
                            aiWorkspaceCoordinator.openWorkspace(router: router)
                        },
                        onPauseResume: nil,
                        onCancel: nil
                    )
                    .zIndex(2)
                }

                CustomContextMenuHost()
                    .zIndex(10)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .environment(customContextMenuCoordinator)
        .environment(customContextMenuSourceRegistry)
        .environment(keyboardMonitor)
        .environment(router)
        .environment(aiWorkspaceCoordinator)
        .environment(libraryViewModel)
        .task {
            router.sanitizeForFeatures(appFeatures)
            await aiWorkspaceCoordinator.restorePersistedJobIfNeeded(context: modelContext)

            do {
                // One-time migration: removed logic based on cardCount and deckCount.
                try appMigrationStore.runLegacyCardCountCleanupIfNeeded {
                    try modelContext.save()
                }

                try await appMigrationStore.runHomeAnalyticsBackfillIfNeeded {
                    let repository = HomeAnalyticsRepository(container: modelContext.container)
                    try await repository.rebuildAnalyticsFromReviewHistory()
                    await repository.tearDown()
                }
            } catch {
                let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                migrationErrorMessage = description.isEmpty
                    ? "A one-time data cleanup couldn't be completed right now."
                    : description
                showMigrationError = true
            }
        }
        .alert("Migration Error", isPresented: $showMigrationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(migrationErrorMessage)
        }
    }

    @ViewBuilder
    private func featureLabDestination(for route: FeatureLabRoute) -> some View {
        if route.isAvailable(in: appFeatures) {
            switch route {
            case .developmentSettings:
                DevelopmentSettingsView()
            case .flashCardsPlayModeSimulation:
                FlashCardsPlayModeSimulationView()
            case .animatedObjectsLab:
                AnimatedObjectsLabView()
            case .sharedUICatalog:
                SharedUICatalogView()
            case .contextMenu:
                ContextMenuLabView()
            case .progressiveBlurHeaderLab:
                ProgressiveBlurHeaderLabView()
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func tabBarChrome(in proxy: GeometryProxy) -> some View {
        let bottomScreenAnchorOffset = proxy.safeAreaInsets.bottom

        ZStack(alignment: .bottom) {
            tabBarBottomBlur(in: proxy)
                .opacity(isFloatingTabBarVisible ? 1 : 0)
                .offset(y: bottomScreenAnchorOffset + (isFloatingTabBarVisible ? 0 : 80))
                .animation(.bottomChromeSpring, value: isFloatingTabBarVisible)
                .allowsHitTesting(false)
            tabBarView(in: proxy)
                .bottomChromeVisibility(isFloatingTabBarVisible)
                .accessibilityHidden(!isFloatingTabBarVisible)
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
    }

    @ViewBuilder
    private func tabBarBottomBlur(in proxy: GeometryProxy) -> some View {
        let height = tabBarBottomBlurHeight(safeBottomInset: proxy.safeAreaInsets.bottom)
        let revealProgress = tabBarBottomBlurRevealProgress

        if height > 0, revealProgress > 0.001 {
            TabBarBottomTintOverlay(
                height: height,
                revealProgress: revealProgress,
                tintColor: tabBarBottomBlurColor,
                configuration: tabBarBottomBlurConfiguration
            )
            .ignoresSafeArea(.all, edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    private func tabBarBottomBlurHeight(safeBottomInset: CGFloat) -> CGFloat {
        tabBarBlurDebugSettings.resolvedBottomHeight(
            from: tabBarBottomBlurBaseHeight(safeBottomInset: safeBottomInset)
        )
    }

    private func tabBarBottomBlurBaseHeight(safeBottomInset: CGFloat) -> CGFloat {
        safeBottomInset + UIConstants.Size.bottomChromeBarHeight
    }

    private var tabBarBottomBlurRevealProgress: CGFloat {
        tabBarBlurDebugSettings.bottomEnabled ? 1 : 0
    }

    private var tabBarBottomBlurConfiguration: ScreenTopProgressiveBlurConfiguration {
        tabBarBlurDebugSettings.bottomProgressiveBlurConfiguration
    }

    private var tabBarBottomBlurColor: Color {
        tabBarBlurDebugSettings.resolvedBottomColor
    }

    private var tabBarBlurDebugSettings: EdgeShadowDebugSettings {
        developmentPreferences.edgeShadowSettings(for: Self.tabBarBlurDebugScreenID)
    }

    @ViewBuilder
    private func tabBarBlurDebugControls(in proxy: GeometryProxy) -> some View {
        #if DEBUG
            if developmentPreferences.edgeShadowTuningEnabled, !keyboardMonitor.isVisible {
                EdgeShadowDebugFloatingPanel(
                    mode: .progressiveBlur,
                    supportsTopEdge: false,
                    supportsBottomEdge: true,
                    initialSelectedEdge: .bottom,
                    bottomHeightBase: tabBarBottomBlurBaseHeight(safeBottomInset: proxy.safeAreaInsets.bottom),
                    heightRange: 0 ... 260,
                    showsProgressiveBlurRadius: false,
                    showsProgressiveFade: false,
                    showsProgressiveTintEdgeHeight: false,
                    showsProgressiveStart: false,
                    panelTitleOverride: "Tab Bar Blur",
                    showButtonTitleOverride: "Tune Tab Blur",
                    hideButtonTitleOverride: "Hide Tab Blur",
                    settings: Binding(
                        get: {
                            developmentPreferences.edgeShadowSettings(for: Self.tabBarBlurDebugScreenID)
                        },
                        set: {
                            developmentPreferences.setEdgeShadowSettings(
                                $0,
                                for: Self.tabBarBlurDebugScreenID
                            )
                        }
                    ),
                    onReset: {
                        developmentPreferences.resetEdgeShadowSettings(for: Self.tabBarBlurDebugScreenID)
                    }
                )
                .padding(.trailing, UIConstants.Spacing.medium)
                .padding(.bottom, UIConstants.Size.bottomChromeBarHeight + 104)
                .opacity(isFloatingTabBarVisible ? 1 : 0)
                .allowsHitTesting(isFloatingTabBarVisible)
            }
        #else
            EmptyView()
        #endif
    }

    @ViewBuilder
    private func tabBarView(in proxy: GeometryProxy) -> some View {
        let availableWidth = max(
            proxy.size.width - (UIConstants.Layout.bottomChromeSideInset * 2),
            0
        )
        let usesDetachedPadTabBar = isPad && availableWidth >= 760
        let barWidth = usesDetachedPadTabBar
            ? min(max(availableWidth * 0.56, 560), 700)
            : availableWidth
        let sideAnchorTrim = isPad ? (UIConstants.Layout.bottomChromeSideInset / 2) : 0

        let bar = CustomTabBar(activeTab: router.activeTab, onTabSelection: handleTabActivation)
            .frame(width: barWidth)
            .scaleEffect(
                (isTabBarCompactedByScroll ? UIConstants.Layout.bottomChromeCompactScale : 1)
                    * tabBarEdgeBounceScale,
                anchor: .bottom
            )
            .animation(.bottomChromeSpring, value: isTabBarCompactedByScroll)
            .animation(.bottomChromeSpring, value: tabBarEdgeBounceScale)
            .offset(y: UIConstants.Layout.bottomChromeVisualBottomOffset)
            .ignoresSafeArea(.container, edges: isPad ? .bottom : [.horizontal, .bottom])

        if usesDetachedPadTabBar {
            HStack(spacing: 0) {
                switch appPreferences.padTabBarPosition {
                case .left:
                    bar
                        .offset(x: -sideAnchorTrim)
                    Spacer(minLength: 0)
                case .center:
                    Spacer(minLength: 0)
                    bar
                    Spacer(minLength: 0)
                case .right:
                    Spacer(minLength: 0)
                    bar
                        .offset(x: sideAnchorTrim)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        } else {
            bar
        }
    }

    // MARK: - Route Destinations

    @ViewBuilder
    private var rootTabView: some View {
        TabView(selection: tabViewSelection) {
            // HOME TAB
            NavigationStack(path: $router.homePath) {
                HomeView()
                    .toolbar(.hidden, for: .tabBar)
                    .navigationDestination(for: DeckNavigationValue.self) { value in
                        if let deck = modelContext.safeModel(for: value.deckID, as: DeckModel.self) {
                            DeckView(deck: deck, backLabel: value.backLabel, ownerTab: .home)
                                .toolbar(.hidden, for: .navigationBar)
                        }
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        appRouteDestination(for: route)
                    }
            }
            .tag(AppTabBar.home)

            // LIBRARY TAB
            NavigationStack(path: $router.libraryPath) {
                LibraryView()
                    .toolbar(.hidden, for: .tabBar)
                    .navigationDestination(for: DeckNavigationValue.self) { value in
                        if let deck = modelContext.safeModel(for: value.deckID, as: DeckModel.self) {
                            DeckView(deck: deck, backLabel: value.backLabel, ownerTab: .library)
                                .toolbar(.hidden, for: .navigationBar)
                        }
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        appRouteDestination(for: route)
                    }
            }
            .tag(AppTabBar.library)

            // CREATE TAB
            NavigationStack(path: $router.createPath) {
                createWorkspaceRootView
                    .toolbar(.hidden, for: .tabBar)
                    .navigationDestination(for: DeckNavigationValue.self) { value in
                        if let deck = modelContext.safeModel(for: value.deckID, as: DeckModel.self) {
                            DeckView(deck: deck, backLabel: value.backLabel, ownerTab: .create)
                                .toolbar(.hidden, for: .navigationBar)
                        }
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        appRouteDestination(for: route)
                    }
            }
            .tag(AppTabBar.create)

            // SETTINGS TAB
            NavigationStack(path: $router.settingsPath) {
                SettingsView(allowsSwipeBack: false)
                    .toolbar(.hidden, for: .tabBar)
                    .navigationDestination(for: AppRoute.self) { route in
                        appRouteDestination(for: route)
                    }
                    .navigationDestination(for: FeatureLabRoute.self) { route in
                        featureLabDestination(for: route)
                    }
            }
            .tag(AppTabBar.settings)
        }
    }

    @ViewBuilder
    private func appRouteDestination(for route: AppRoute) -> some View {
        switch route {
        case .createDeck:
            DeckWorkspaceView()
        case .generateDeck:
            DeckWorkspaceView(launchAction: .showAIGenerationOptions)
        case .settings:
            SettingsView(allowsSwipeBack: true)
        case .folder(let folder, let backLabel):
            // backLabel was frozen at push time by the call site (e.g. HomeDashboardView).
            // FolderView stores it as a constant — never reads router.activeTab reactively.
            FolderView(folder: folder, backLabel: backLabel)
        }
    }

    @ViewBuilder
    private var createWorkspaceRootView: some View {
        ZStack {
            if let deckID = router.createWorkspaceEditingDeckID,
               let deck = modelContext.safeModel(for: deckID, as: DeckModel.self) {
                DeckWorkspaceView(deckToEdit: deck)
                    .id(router.createWorkspaceRootIdentity)
                    .transition(createWorkspaceRootTransition)
            } else {
                DeckWorkspaceView()
                    .id(router.createWorkspaceRootIdentity)
                    .transition(createWorkspaceRootTransition)
            }
        }
        .animation(.circularProgressSpring, value: router.createWorkspaceRootIdentity)
    }

    private var createWorkspaceRootTransition: AnyTransition {
        .opacity
            .combined(with: .scale(scale: 0.985, anchor: .top))
    }
}

private struct TabBarBottomTintOverlay: View {
    let height: CGFloat
    let revealProgress: CGFloat
    let tintColor: Color
    let configuration: ScreenTopProgressiveBlurConfiguration

    private var clampedRevealProgress: CGFloat {
        min(max(revealProgress, 0), 1)
    }

    var body: some View {
        if height > 0, clampedRevealProgress > 0.001 {
            let totalHeight = max(height, 1)
            let overlayHeight = totalHeight + max(configuration.fadeExtension, 0)
            let middleLocation = min(max(totalHeight / max(overlayHeight, 1), 0), 1)

            LinearGradient(
                stops: [
                    .init(color: tintColor.opacity(configuration.tintOpacityTop), location: 0),
                    .init(color: tintColor.opacity(configuration.tintOpacityMiddle), location: middleLocation),
                    .init(color: tintColor.opacity(0), location: 1),
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(maxWidth: .infinity)
            .frame(height: overlayHeight, alignment: .bottom)
            .opacity(clampedRevealProgress)
            .allowsHitTesting(false)
        }
    }
}

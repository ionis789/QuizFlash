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

    @State private var router = NavigationManager()

    /// The long-lived view model for the Library tab.
    /// Instantiated at the root level and injected into the environment so that
    /// expensive operations (search cache, grouping) persist across navigation
    /// and tab-switching without redundant recomputation.
    @State private var libraryViewModel = LibraryViewModel()

    /// The visibility rule currently reported by the frontmost child view.
    @State private var tabBarRule: TabBarVisibilityRule = .implicit

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

        UITabBar.appearance().standardAppearance   = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    // MARK: - Computed Properties

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Resolves the active tab bar visibility rule to a Bool.
    ///
    /// Decision table:
    ///   `.visible`  → always show  (e.g. FolderView, which is always pushed)
    ///   `.hidden`   → always hide  (e.g. DeckView, full-screen flows)
    ///   `.implicit` → show by default
    private var isTabBarVisible: Bool {
        switch tabBarRule {
        case .visible:  return true
        case .hidden:   return false
        case .implicit: return true
        }
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
        guard isTabBarVisible else { return }

        if tappedTab == router.activeTab {
            // Re-tap: pop to root without leaving the tab.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                router.popToRoot()
            }
        } else {
            router.activeTab = tappedTab
        }
    }

    // MARK: - Body

    var body: some View {
        // The ZStack keeps the custom tab bar rendered as a true overlay, independent
        // of NavigationStack's internal view hierarchy. This allows pushed destinations
        // (e.g. FolderView) to opt in to bar visibility without
        // the bar being clipped or re-laid out by navigation transitions.
        ZStack(alignment: isPad ? .bottomTrailing : .bottom) {

            // ── Navigation Layer ─────────────────────────────────────────────
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
                    CreateDeckView()
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
                    SettingsView()
                        .toolbar(.hidden, for: .tabBar)
                        .navigationDestination(for: AppRoute.self) { route in
                            appRouteDestination(for: route)
                        }
                }
                .tag(AppTabBar.settings)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            // Propagate tab bar visibility changes with an explicit spring so the
            // animation context is preserved regardless of where the preference
            // change fires. Without withAnimation here, mutations placed inside
            // DispatchQueue.main.async run in a new SwiftUI transaction that is
            // decoupled from the .animation modifier on the ZStack — the tab bar
            // would snap instead of spring.
            .onPreferenceChange(TabBarVisibilityKey.self) { rule in
                DispatchQueue.main.async {
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
            .configureNativeTabBar(visible: isTabBarVisible)

            EdgeShadowOverlay(topHeight: 60, bottomHeight: 60)

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
            CustomTabBar(activeTab: router.activeTab, onTabSelection: handleTabActivation)
                .bottomChromeVisibility(isTabBarVisible)
                .zIndex(1)
        }
        .environment(router)
        .environment(libraryViewModel)
        .task {
            // One-time migration: removed logic based on cardCount and deckCount.
            let key = "didMigrateCardCount_v1"
            guard !UserDefaults.standard.bool(forKey: key) else { return }
            try? modelContext.save()
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    // MARK: - Route Destinations

    @ViewBuilder
    private func appRouteDestination(for route: AppRoute) -> some View {
        switch route {
        case .createDeck:
            CreateDeckView()
        case .settings:
            SettingsView()
        case .folder(let folder, let backLabel):
            // backLabel was frozen at push time by the call site (e.g. HomeDashboardView).
            // FolderView stores it as a constant — never reads router.activeTab reactively.
            FolderView(folder: folder, backLabel: backLabel)
        }
    }
}

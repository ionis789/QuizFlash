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
//  - The tab bar appearance animation is intentionally asymmetric:
//    hiding is spring-animated (synced with the push transition curve),
//    while showing is instant so the bar snaps back without a perceived delay
//    when the user pops back from a destination that had hidden it.
//  - Tapping the currently active tab pops to root (mirrors UITabBarController).
//

import SwiftUI
import SwiftData

struct MainAppView: View {

    // MARK: - State

    @Environment(\.modelContext) private var modelContext

    @State private var router = NavigationManager()
    @State private var activeTab: AppTab = .home

    /// The long-lived view model for the Library tab.
    /// It is instantiated here at the root level and injected into the environment
    /// so that expensive operations (like building the search cache) persist
    /// across navigation and tab-switching events without redundant computation.
    @State private var libraryViewModel = LibraryViewModel()

    /// Per-tab navigation paths. Each tab's scroll position in the navigation
    /// hierarchy is preserved independently so switching tabs never loses state.
    @State private var pathPerTab: [AppTab: NavigationPath] = [:]

    /// The visibility rule currently reported by the frontmost child view.
    /// Defaults to `.implicit` (tab bar visible) until a preference arrives.
    @State private var tabBarRule: TabBarVisibilityRule = .implicit

    // MARK: - Init

    init() {
        // Suppress the native UIKit tab bar entirely. The custom bar is an
        // independent ZStack layer not subject to UIKit layout constraints.
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

    /// Resolves tab bar visibility from the active child preference.
    ///
    /// Decision table:
    ///   `.visible`  → always show  (e.g. LibraryView with folderContext)
    ///   `.hidden`   → always hide  (e.g. DeckView, full-screen flows)
    ///   `.implicit` → show by default
    private var isTabBarVisible: Bool {
        switch tabBarRule {
        case .visible:  return true
        case .hidden:   return false
        case .implicit: return true
        }
    }

    /// A `Binding<AppTab>` that intercepts every tab selection event and
    /// implements standard iOS tab bar controller semantics:
    ///
    /// - **Same tab tapped:** pop to root for the active tab.
    /// - **Different tab tapped:** suspend the current tab's path into
    ///   `pathPerTab`, restore the destination tab's previously saved path
    ///   into `router.path`, then switch `activeTab`.
    private var tabSelectionBinding: Binding<AppTab> {
        Binding(
            get: { activeTab },
            set: { tappedTab in
                if tappedTab == activeTab {
                    // Re-tap: pop to root without leaving the tab.
                    guard !router.path.isEmpty else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        router.path = NavigationPath()
                        pathPerTab[activeTab] = NavigationPath()
                    }
                } else {
                    // Tab switch: snapshot the departing tab's path…
                    pathPerTab[activeTab] = router.path

                    // Flush the image cache on tab switch to prevent stale
                    // downsampled bitmaps from accumulating across sessions.
                    ImageCache.shared.clearCache()

                    // …then restore the arriving tab's saved path without animation.
                    // Restoring via a plain assignment causes SwiftUI to animate the
                    // path diff as a push transition, making the destination appear to
                    // "open" again. Disabling animations makes the state reappear
                    // instantly, matching the native UITabBarController behavior where
                    // switching tabs never triggers a navigation transition.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        router.path = pathPerTab[tappedTab] ?? NavigationPath()
                    }
                    activeTab = tappedTab
                }
            }
        )
    }

    // MARK: - Body

    var body: some View {
        // The ZStack keeps the custom tab bar rendered as a true overlay, independent
        // of NavigationStack's internal view hierarchy. This allows pushed destinations
        // (e.g. LibraryView with folderContext) to opt in to bar visibility without
        // the bar being clipped or re-laid out by navigation transitions.
        ZStack(alignment: isPad ? .bottomTrailing : .bottom) {

            // ── Navigation Layer ─────────────────────────────────────────────
            NavigationStack(path: $router.path) {
                TabView(selection: tabSelectionBinding) {
                    HomeView()
                        .tag(AppTab.home)
                        .toolbar(.hidden, for: .tabBar)

                    LibraryView()
                        .tag(AppTab.library)
                        .toolbar(.hidden, for: .tabBar)

                    CreateDeckView()
                        .tag(AppTab.create)
                        .toolbar(.hidden, for: .tabBar)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                // ── Navigation Destinations ──────────────────────────────────
                .navigationDestination(for: PersistentIdentifier.self) { deckID in
                    if let deck = modelContext.model(for: deckID) as? DeckModel {
                        DeckView(deck: deck)
                            .toolbar(.hidden, for: .navigationBar)
                    }
                }
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .createDeck:
                        CreateDeckView()
                    case .settings:
                        SettingsView()
                    case .folder(let folder):
                        // LibraryView sends `.visible` when folderContext != nil,
                        // so the tab bar persists through the push transition.
                        LibraryView(folderContext: folder)
                    }
                }
            }
            // ── Path Observer ────────────────────────────────────────────────
            // Serves two purposes:
            //
            // 1. Snapshot sync — keeps `pathPerTab` up to date when the user
            //    pops via swipe-back or the system back button, both of which
            //    mutate `router.path` directly without going through
            //    `tabSelectionBinding`.
            //
            // 2. Instant tab bar restoration on pop — the critical fix for the
            //    perceived delay after swipe-back.
            //
            //    The normal restoration path is:
            //      DeckView leaves hierarchy
            //        → SwiftUI re-evaluates the full preference tree
            //          → onPreferenceChange fires → tabBarRule updates
            //
            //    If any view in the tree does heavy work on appear (cache
            //    rebuild, SwiftData fetch, search index build), preference
            //    re-evaluation is deferred, adding visible latency.
            //
            //    `onChange(of: router.path)` fires in the same run-loop pass
            //    as the path mutation — before preference propagation — so the
            //    tab bar is restored immediately when a pop is detected.
            //    The subsequent onPreferenceChange call still arrives but is
            //    a no-op because the rule already matches.
            .onChange(of: router.path) { oldPath, newPath in
                pathPerTab[activeTab] = newPath

                let didPop = newPath.count < oldPath.count
                if didPop && tabBarRule == .hidden {
                    tabBarRule = .implicit
                }
            }
            // ── Tab Bar Visibility ───────────────────────────────────────────
            // Asymmetric animation:
            //   • Hiding  → spring, synced with the NavigationStack push curve.
            //   • Showing → no animation; pop events are already handled above
            //               via the path observer. This branch only runs for
            //               non-pop show events (e.g. LibraryView sending .visible
            //               for a folder that should keep the bar visible).
            .onPreferenceChange(TabBarVisibilityKey.self) { rule in
                let isAppearing = !isTabBarVisible && (rule == .visible || rule == .implicit)
                if isAppearing {
                    tabBarRule = rule
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        tabBarRule = rule
                    }
                }
            }

            // ── Tab Bar Layer ────────────────────────────────────────────────
            if isTabBarVisible {
                CustomTabBar(activeTab: tabSelectionBinding)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .environment(router)
        .environment(libraryViewModel)
        .task {
            // One-time migration removed logic based on cardCount and deckCount
            let key = "didMigrateCardCount_v1"
            guard !UserDefaults.standard.bool(forKey: key) else { return }



            try? modelContext.save()
            UserDefaults.standard.set(true, forKey: key)
        }
    }
}

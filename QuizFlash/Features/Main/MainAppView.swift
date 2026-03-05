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

    /// The long-lived view model for the Library tab.
    /// It is instantiated here at the root level and injected into the environment
    /// so that expensive operations (like building the search cache) persist
    /// across navigation and tab-switching events without redundant computation.
    @State private var libraryViewModel = LibraryViewModel()

    /// The visibility rule currently reported by the frontmost child view.
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
        case .visible: return true
        case .hidden: return false
        case .implicit: return true
        }
    }

    /// A `Binding<AppTab>` that intercepts every tab selection event and
    /// implements standard iOS tab bar controller semantics:
    ///
    /// - **Same tab tapped:** pop to root for the active tab.
    /// - **Different tab tapped:** switch `activeTab` visually, pushing the native stack
    private var tabSelectionBinding: Binding<AppTab> {
        Binding(
            get: { router.activeTab },
            set: { tappedTab in
                // The native UITabBar remains in the UIKit hierarchy even when
                // hidden via appearance proxy and can still fire tab-switch events
                // independently of this binding. Reject all sets while the custom
                // bar is not visible (selection mode, search mode, pushed deck view).
                guard isTabBarVisible else { return }

                if tappedTab == router.activeTab {
                    // Re-tap: pop to root without leaving the tab.
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        router.popToRoot()
                    }
                } else {
                    // Flush the image cache on tab switch to prevent stale
                    // downsampled bitmaps from accumulating across sessions.
                    ImageCache.shared.clearCache()

                    router.activeTab = tappedTab
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
            TabView(selection: tabSelectionBinding) {
                // HOME TAB
                NavigationStack(path: $router.homePath) {
                    HomeView()
                        .toolbar(.hidden, for: .tabBar)
                        .navigationDestination(for: PersistentIdentifier.self) { deckID in
                            if let deck = modelContext.model(for: deckID) as? DeckModel {
                                DeckView(deck: deck)
                                    .toolbar(.hidden, for: .navigationBar)
                            }
                        }
                        .navigationDestination(for: AppRoute.self) { route in
                            appRouteDestination(for: route)
                        }
                }
                .tag(AppTab.home)

                // LIBRARY TAB
                NavigationStack(path: $router.libraryPath) {
                    LibraryView()
                        .toolbar(.hidden, for: .tabBar)
                        .navigationDestination(for: PersistentIdentifier.self) { deckID in
                            if let deck = modelContext.model(for: deckID) as? DeckModel {
                                DeckView(deck: deck)
                                    .toolbar(.hidden, for: .navigationBar)
                            }
                        }
                        .navigationDestination(for: AppRoute.self) { route in
                            appRouteDestination(for: route)
                        }
                }
                .tag(AppTab.library)

                // CREATE TAB
                NavigationStack(path: $router.createPath) {
                    CreateDeckView()
                        .toolbar(.hidden, for: .tabBar)
                        .navigationDestination(for: PersistentIdentifier.self) { deckID in
                            if let deck = modelContext.model(for: deckID) as? DeckModel {
                                DeckView(deck: deck)
                                    .toolbar(.hidden, for: .navigationBar)
                            }
                        }
                        .navigationDestination(for: AppRoute.self) { route in
                            appRouteDestination(for: route)
                        }
                }
                .tag(AppTab.create)
            }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            // ── Path Observers for TabBar Visibility ──────────────────────────
            // Instant tab bar restoration on pop — the critical fix for the
            // perceived delay after swipe-back on iOS 17.
            // When the path count decreases, we know a view was popped. If the bar
            // was hidden, we immediately restore it.
            // ── Path Observers for TabBar Visibility ──────────────────────────

            // ── Tab Bar Layer ────────────────────────────────────────────────
            // Asymmetric animation:
            //   • Hiding  → spring, synced with the NavigationStack push curve.
            //   • Showing → no animation; pop events are already handled above
            //               via the path observer. This branch only runs for
            //               non-pop show events (e.g. LibraryView sending .visible
            //               for a folder that should keep the bar visible).
            // ── Tab Bar Layer ────────────────────────────────────────────────
            // ── Tab Bar Layer ────────────────────────────────────────────────
            // ── Tab Bar Layer ────────────────────────────────────────────────
            .onPreferenceChange(TabBarVisibilityKey.self) { rule in
                // Explicit animation context so CustomTabBar's .transition() is
                // driven by the same spring as LibrarySelectionBarView — symmetric
                // enter/exit. Without withAnimation the DispatchQueue hop creates a
                // new transaction outside SwiftUI's current animation, causing the
                // tab bar to snap in without its move+opacity transition.
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        self.tabBarRule = rule
                    }
                }
            }
            // ── Tab Bar Layer ────────────────────────────────────────────────
            EdgeShadowOverlay(topHeight: 60, bottomHeight: 60)

            // CustomTabBar is always in the hierarchy — never conditionally inserted
            // or removed. Insertion/removal causes SwiftUI to start the enter
            // transition at the same moment the selection bar begins its exit
            // transition; visually the selection bar covers the tab bar sliding up,
            // so when the selection bar disappears the tab bar looks like it snaps in.
            //
            // Pure property animation (opacity + offset) avoids this entirely:
            // both directions are smooth, continuous, and fully symmetric because
            // SwiftUI interpolates existing properties rather than scheduling
            // an insertion event at the end of another transition.
            CustomTabBar(activeTab: tabSelectionBinding)
                .padding(.bottom, 10)
                .zIndex(1)
                .opacity(isTabBarVisible ? 1 : 0)
                .offset(y: isTabBarVisible ? 0 : 80)
                // Disable hit-testing when invisible so taps pass through to
                // the content below — equivalent to the view not being there.
                .allowsHitTesting(isTabBarVisible)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isTabBarVisible)
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



    // MARK: - Global Dynamic Router Helper
    @ViewBuilder
    private func appRouteDestination(for route: AppRoute) -> some View {
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

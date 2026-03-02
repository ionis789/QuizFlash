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
            // 🔥 Arhitectura corecta pe iOS 17 pentru a evita distrugerea instanțelor de fundal:
            // TabView la rădăcină, iar fiecare structură de Navigare are propriul tab și state propriu.
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
                // Fără animație aici, pentru că animația e pusă direct pe TabBar!
                DispatchQueue.main.async {
                    self.tabBarRule = rule
                }
            }
            // ── Tab Bar Layer ────────────────────────────────────────────────
            // ── Tab Bar Layer ────────────────────────────────────────────────
            // Am eliminat `if isTabBarVisible` pentru a păstra view-ul în memorie.
            // Animația de ascundere/afișare este controlată pur prin offset (mutație pe axa Y).

            // ── Tab Bar Layer ────────────────────────────────────────────────
            // FĂRĂ `if isTabBarVisible {` aici!
            CustomTabBar(activeTab: tabSelectionBinding)
                .padding(.bottom, 10)
            // Mută bara în jos 130 de puncte când e ascunsă, sau la 0 când e vizibilă
            .offset(y: isTabBarVisible ? 0 : 130)
                .opacity(isTabBarVisible ? 1 : 0)
                .zIndex(1)
            // Acest singur rând preia modificarea de stare și creează o tranziție perfectă
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

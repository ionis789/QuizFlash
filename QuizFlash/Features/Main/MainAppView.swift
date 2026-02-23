import SwiftUI

struct MainAppView: View {
    @State private var router = NavigationManager()

    // Tab State
    @State private var activeTab: AppTab = .library

    // Global Search State
    @State private var searchText: String = ""
    @State private var isSearchExpanded: Bool = false
    
    // Track when to hide the tab bar
    @State private var isTabBarHidden: Bool = false

    init() {
        // 1. Hide the tab bar icons/structure
        UITabBar.appearance().isHidden = true

        // 2. Completely nuke the background materials and blur effects
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil
        appearance.shadowColor = .clear

        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        NavigationStack(path: $router.path) {
            ZStack(alignment: isPad ? .bottomTrailing : .bottom) {
                TabView(selection: $activeTab) {
                    LibraryView(
                        externalSearchText: $searchText,
                        isSearchExpanded: $isSearchExpanded,
                        isTabBarHidden: $isTabBarHidden // 👈 Pass the binding here
                    )
                    .tag(AppTab.library)
                    .toolbar(.hidden, for: .tabBar) // Hides the native iOS tab bar

                    CreateDeckView()
                        .tag(AppTab.create)
                        .toolbar(.hidden, for: .tabBar)

                    SettingsView()
                        .tag(AppTab.settings)
                        .toolbar(.hidden, for: .tabBar)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)

                // 👇 NEW: Conditionally show the Tab Bar with a transition
                if !isTabBarHidden {
                    CustomTabBar(
                        activeTab: $activeTab,
                        searchText: $searchText,
                        onSearchBarExpanded: { expanded in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSearchExpanded = expanded
                                if !expanded { searchText = "" }
                            }
                        },
                        onSearchTextFieldActive: { _ in }
                    )
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    // Ensure the tab bar sits above other elements before it's hidden
                    .zIndex(1)
                }
            }
            // 3. Navigation Destinations
            .navigationDestination(for: DeckModel.self) { deck in
                DeckView(deck: deck)
            }
            .navigationDestination(for: DeckSearchRoute.self) { route in
                DeckView(deck: route.deck, searchQuery: route.query)
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .createDeck:
                    CreateDeckView()
                case .settings:
                    SettingsView()
                }
            }
        }
        .environment(router)
    }
}

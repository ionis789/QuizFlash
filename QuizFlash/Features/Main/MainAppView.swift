//
//  MainAppView.swift
//  QuizFlash
//

import SwiftUI

struct MainAppView: View {
    @State private var router = NavigationManager()

    var body: some View {
        NavigationStack(path: $router.path) {
            LibraryView()
                .navigationDestination(for: DeckModel.self) { deck in
                    DeckView(deck: deck)
                }
                // MARK: - Filtered Deck Destination
                .navigationDestination(for: DeckSearchRoute.self) { route in
                    DeckView(deck: route.deck, searchQuery: route.query)
                }
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .createDeck:
                        CreateView()
                    case .settings:
                        SettingsView()
                    }
                }
        }
        .environment(router)
    }
}

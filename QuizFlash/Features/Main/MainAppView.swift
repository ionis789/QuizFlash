import SwiftUI

struct MainAppView: View {
    @StateObject private var router = NavigationManager()

    var body: some View {
        NavigationStack(path: $router.path) {
            LibraryView()
                .navigationDestination(for: DeckModel.self) { deck in
                    DeckView(deck: deck)
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
        .environmentObject(router)
    }
}

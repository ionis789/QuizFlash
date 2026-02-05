import SwiftUI

struct MainAppView: View {
    @State private var curentTab: AppTab = .library
    @StateObject private var router = NavigationManager()

    init() {
        let appearance = UITabBarAppearance()

        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil

        appearance.shadowColor = .clear
        appearance.shadowImage = UIImage()

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        ZStack(alignment: .bottom) {


            TabView(selection: $curentTab) {
                LibraryView()
                    .environmentObject(router)
                    .tag(AppTab.library)
                    .toolbar(.hidden, for: .tabBar)


                CreateView()
                    .tag(AppTab.create)
                    .toolbar(.hidden, for: .tabBar)


                SettingsView()
                    .tag(AppTab.settings)
                    .toolbar(.hidden, for: .tabBar)

            }

            FloatingTabBar(selectedTab: $curentTab, router: router)
        }
            .ignoresSafeArea(.keyboard)
    }
}

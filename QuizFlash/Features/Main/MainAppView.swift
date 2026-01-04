import SwiftUI

struct MainAppView: View {

    @State private var curentTab: AppTab = .library




    init() {
        if #unavailable(iOS 26.0) {

            let appearance = UITabBarAppearance()

            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.backgroundEffect = nil

            appearance.shadowColor = .clear
            appearance.shadowImage = UIImage()

            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance

        }

    }


    var body: some View {


        if #available(iOS 26.0, *) {
            TabView(selection: $curentTab) {
                tabs
            }
        }

        else {

            ZStack(alignment: .bottom) {

                TabView(selection: $curentTab) {
                    LibraryView()
                        .tag(AppTab.library)

                    CreateView()
                        .tag(AppTab.create)

                    SettingsView()
                        .tag(AppTab.settings)
                }
                    .ignoresSafeArea()

                FloatingTabBar(selectedTab: $curentTab)
                    .ignoresSafeArea()
            }
        }
    }
}

@ViewBuilder
var tabs: some View {
    LibraryView()
        .tag(AppTab.library)
        .tabItem {
        Label(AppTab.library.title, systemImage: AppTab.library.icon)
    }

    CreateView()
        .tag(AppTab.create)
        .tabItem {
        Label(AppTab.create.title, systemImage: AppTab.create.icon)
    }

    SettingsView()
        .tag(AppTab.settings)
        .tabItem {
        Label(AppTab.settings.title, systemImage: AppTab.settings.icon)
    }
}








import SwiftUI

struct RootView: View {

    @Environment(AuthManager.self) var authManager
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ZStack {
            themeManager.screenBackground
                .ignoresSafeArea()

            Group {
                if authManager.isAuthenticated {
                    MainAppView()
                        .transition(.opacity)
                } else {
                    LoginView()
                        .transition(.opacity)
                }
            }
        }
    }
}



#Preview {
    RootView()
        .environment(AuthManager.shared)
        .environment(ThemeManager.shared)
}

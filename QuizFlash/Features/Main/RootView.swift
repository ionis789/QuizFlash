import SwiftUI

struct RootView: View {

    @Environment(AuthManager.self) var authManager

    var body: some View {
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



#Preview {
    RootView()
}

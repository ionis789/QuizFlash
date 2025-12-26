import SwiftUI

struct RootView: View {
    
    @EnvironmentObject var authManager: AuthManager
    
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

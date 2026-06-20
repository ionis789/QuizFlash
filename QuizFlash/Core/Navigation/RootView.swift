import SwiftUI

// MARK: - Root View

struct RootView: View {

    @Environment(AuthManager.self) var authManager
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ZStack {
            themeManager.screenBackground
                .ignoresSafeArea()

            Group {
                switch authManager.sessionState {
                case .checking:
                    ProgressActivityDots(color: themeManager.accentColor.color)
                        .transition(.opacity)
                case .signedIn:
                    MainAppView()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                case .signedOut, .emailVerificationRequired, .emailVerificationSucceeded:
                    LoginView()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.easeInOut(duration: 0.35), value: authManager.sessionState)
        }
    }
}



#Preview {
    RootView()
        .environment(AuthManager.shared)
        .environment(ThemeManager.shared)
}

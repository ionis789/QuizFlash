import SwiftUI

// MARK: - Root View

struct RootView: View {

    @Environment(AuthManager.self) var authManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(OnboardingStateStore.self) private var onboardingStateStore
    @Environment(ThemeManager.self) private var themeManager

    @State private var hasStartedLaunchAnimation = false
    @State private var hasCompletedLaunchAnimation = false
    @State private var isLaunchAnimationVisible = true
    @State private var isLaunchSymbolPresented = false

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
                        .transition(.opacity)
                case .signedOut,
                     .emailVerificationRequired,
                     .emailVerificationSucceeded,
                     .signInSucceeded:
                    LoginView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.45), value: authManager.sessionState)

            if isLaunchAnimationVisible {
                QuizFlashLaunchAnimationView(
                    isPresented: isLaunchSymbolPresented
                )
                .transition(.opacity)
                .zIndex(4)
            }

            if let presentation = onboardingStateStore.presentation {
                QuizFlashOnboardingView(
                    presentation: presentation,
                    onComplete: { completedPresentation in
                        completeOnboarding(completedPresentation)
                    },
                    onClose: { closedPresentation in
                        onboardingStateStore.closePreview(closedPresentation)
                    }
                )
                .id(presentation.id)
                .transition(onboardingTransition(for: presentation))
                .zIndex(3)
            }
        }
        .animation(onboardingPresentationAnimation, value: onboardingStateStore.presentation?.id)
        .task {
            await playLaunchAnimationIfNeeded()
            presentOnboardingIfNeeded()
        }
        .onChange(of: authManager.sessionState) { _, _ in
            presentOnboardingIfNeeded()
        }
    }

    private func presentOnboardingIfNeeded() {
        guard hasCompletedLaunchAnimation else { return }

        if case .signedIn(let user) = authManager.sessionState {
            onboardingStateStore.presentRequiredIfNeeded(for: user)
        } else if case .required = onboardingStateStore.presentation {
            onboardingStateStore.presentRequiredIfNeeded(for: nil)
        }
    }

    private var onboardingPresentationAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.22) : .easeInOut(duration: 0.42)
    }

    private func onboardingTransition(for presentation: OnboardingPresentation) -> AnyTransition {
        return .opacity.combined(with: .scale(scale: 0.985))
    }

    private func completeOnboarding(_ completedPresentation: OnboardingPresentation) {
        onboardingStateStore.complete(completedPresentation)
    }

    @MainActor
    private func playLaunchAnimationIfNeeded() async {
        guard !hasStartedLaunchAnimation else { return }
        hasStartedLaunchAnimation = true

        let revealAnimation: Animation = reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.46, dampingFraction: 0.86)
        let exitAnimation: Animation = reduceMotion
            ? .easeInOut(duration: 0.18)
            : .easeInOut(duration: 0.28)
        let exitDelay: Duration = reduceMotion ? .milliseconds(180) : .milliseconds(280)

        withAnimation(revealAnimation) {
            isLaunchSymbolPresented = true
        }

        try? await Task.sleep(nanoseconds: reduceMotion ? 420_000_000 : 760_000_000)

        hasCompletedLaunchAnimation = true
        presentOnboardingIfNeeded()
        await Task.yield()

        withAnimation(exitAnimation) {
            isLaunchAnimationVisible = false
        }

        try? await Task.sleep(for: exitDelay)
    }
}

// MARK: - Launch Animation

private struct QuizFlashLaunchAnimationView: View {

    @Environment(ThemeManager.self) private var themeManager

    let isPresented: Bool

    var body: some View {
        ZStack {
            themeManager.screenBackground
                .ignoresSafeArea()

            ambientGlow
                .scaleEffect(isPresented ? 1.0 : 0.82)
                .opacity(isPresented ? 1.0 : 0.0)

            boltSymbol
                .scaleEffect(isPresented ? 1.0 : 0.88)
                .opacity(isPresented ? 1.0 : 0.0)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var ambientGlow: some View {
        RadialGradient(
            colors: [
                launchPurple.opacity(0.26),
                launchPurple.opacity(0.12),
                .clear
            ],
            center: .center,
            startRadius: 8,
            endRadius: 190
        )
        .ignoresSafeArea()
    }

    private var boltSymbol: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 58, weight: .black, design: .rounded))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        .white,
                        Color(red: 0.86, green: 0.82, blue: 1.0),
                        launchPurple
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(
                color: launchPurple.opacity(0.48),
                radius: 26
            )
    }

    private var launchPurple: Color {
        Color(red: 0.62, green: 0.52, blue: 1.0)
    }
}



#Preview {
    RootView()
        .environment(AuthManager.shared)
        .environment(OnboardingStateStore.shared)
        .environment(ThemeManager.shared)
}

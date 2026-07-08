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
    @State private var isLaunchSymbolHandedOff = false

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
                    LoginView(allowsAuthWalkthroughAnimation: !isLaunchAnimationVisible)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.45), value: authManager.sessionState)

            if isLaunchAnimationVisible {
                QuizFlashLaunchAnimationView(
                    isPresented: isLaunchSymbolPresented,
                    isHandedOff: isLaunchSymbolHandedOff
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
            : .easeInOut(duration: 0.22)
        let handoffAnimation: Animation = reduceMotion
            ? .easeInOut(duration: 0.18)
            : .smooth(duration: 0.64, extraBounce: 0)
        let handoffDelay: Duration = reduceMotion ? .milliseconds(180) : .milliseconds(640)
        let exitDelay: Duration = reduceMotion ? .milliseconds(160) : .milliseconds(220)

        withAnimation(revealAnimation) {
            isLaunchSymbolPresented = true
        }

        try? await Task.sleep(nanoseconds: reduceMotion ? 420_000_000 : 760_000_000)

        hasCompletedLaunchAnimation = true
        presentOnboardingIfNeeded()
        await Task.yield()

        withAnimation(handoffAnimation) {
            isLaunchSymbolHandedOff = true
        }

        try? await Task.sleep(for: handoffDelay)

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
    let isHandedOff: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let symbolSize: CGFloat = isHandedOff ? 38 : 58
            let symbolPosition = CGPoint(
                x: size.width / 2,
                y: isHandedOff ? authWalkthroughSymbolCenterY(in: size.height) : size.height / 2
            )

            ZStack(alignment: .topLeading) {
                themeManager.screenBackground
                    .opacity(backgroundOpacity)
                    .ignoresSafeArea()

                ambientGlow(in: size)
                    .scaleEffect(isPresented ? 1.0 : 0.82)
                    .opacity(ambientGlowOpacity)

                boltSymbol(size: symbolSize)
                    .position(symbolPosition)
                    .opacity(isPresented ? 1.0 : 0.0)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var backgroundOpacity: Double {
        guard isPresented else { return 0 }
        return isHandedOff ? 0 : 1
    }

    private var ambientGlowOpacity: Double {
        guard isPresented else { return 0 }
        return isHandedOff ? 0.18 : 1
    }

    private func ambientGlow(in size: CGSize) -> some View {
        RadialGradient(
            colors: [
                launchPurple.opacity(isHandedOff ? 0.14 : 0.26),
                launchPurple.opacity(isHandedOff ? 0.06 : 0.12),
                .clear
            ],
            center: .center,
            startRadius: 8,
            endRadius: isHandedOff ? 96 : 190
        )
        .frame(width: size.width, height: size.height)
        .position(
            x: size.width / 2,
            y: isHandedOff ? authWalkthroughSymbolCenterY(in: size.height) : size.height / 2
        )
        .ignoresSafeArea()
    }

    private func boltSymbol(size: CGFloat) -> some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: size, weight: .black, design: .rounded))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(boltForegroundStyle)
            .shadow(
                color: launchPurple.opacity(isHandedOff ? 0.34 : 0.48),
                radius: isHandedOff ? 18 : 26
            )
    }

    private var boltForegroundStyle: AnyShapeStyle {
        if isHandedOff {
            return AnyShapeStyle(themeManager.accentColor.color)
        }

        return AnyShapeStyle(
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
    }

    private func authWalkthroughSymbolCenterY(in height: CGFloat) -> CGFloat {
        height * 0.46
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

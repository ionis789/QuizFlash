import SwiftUI

#if DEBUG
func authLaunchDebugLog(_ message: String) {
    print("AUTH_LAUNCH_HANDOFF \(String(format: "%.3f", Date().timeIntervalSince1970)) \(message)")
}
#endif

enum AuthLaunchLayout {
    static let walkthroughCenterYRatio: CGFloat = 0.46
    static let boltID = "auth-launch-bolt"
}

struct AuthLaunchBoltGeometryModifier: ViewModifier {
    let namespace: Namespace.ID?
    let isSource: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(
                id: AuthLaunchLayout.boltID,
                in: namespace,
                properties: [.position, .size],
                anchor: .center,
                isSource: isSource
            )
        } else {
            content
        }
    }
}

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
    @State private var launchStrikeProgress: CGFloat = 0
    @State private var isLaunchStrikeVisible = false
    @State private var launchStrikePulse: CGFloat = 0
    @State private var isLaunchSymbolHandedOff = false
    @State private var isAuthWalkthroughPrepared = false
    @State private var isLaunchBoltReadyForTransfer = false
    @State private var hasStartedAuthBoltTransfer = false
    @State private var isAuthWalkthroughBoltVisible = false
    @State private var isAuthWalkthroughTextVisible = false
    @State private var isAuthSheetPresentationReleased = false
    @Namespace private var authLaunchBoltNamespace

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
                    LoginView(
                        showsAuthWalkthrough: true,
                        showsAuthWalkthroughBolt: isAuthWalkthroughBoltVisible,
                        showsAuthWalkthroughText: isAuthWalkthroughTextVisible,
                        allowsAuthWalkthroughAnimation: isAuthWalkthroughTextVisible,
                        allowsAuthSheetPresentation: isAuthSheetPresentationReleased,
                        launchBoltNamespace: authLaunchBoltNamespace,
                        onAuthWalkthroughPrepared: {
                            isAuthWalkthroughPrepared = true
                        }
                    )
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.45), value: authManager.sessionState)

            if isLaunchAnimationVisible {
                QuizFlashLaunchAnimationView(
                    isPresented: isLaunchSymbolPresented,
                    strikeProgress: launchStrikeProgress,
                    isStrikeVisible: isLaunchStrikeVisible,
                    strikePulse: launchStrikePulse,
                    isHandedOff: isLaunchSymbolHandedOff,
                    boltNamespace: authLaunchBoltNamespace
                )
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
        .onChange(of: isAuthWalkthroughPrepared) { _, isPrepared in
            guard isPrepared else { return }

            Task { @MainActor in
                await Task.yield()
                startAuthBoltTransferIfReady()
            }
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
        let handoffAnimation: Animation = reduceMotion
            ? .easeInOut(duration: 0.18)
            : .smooth(duration: 0.64, extraBounce: 0)
        let handoffDelay: Duration = reduceMotion ? .milliseconds(180) : .milliseconds(640)

        withAnimation(revealAnimation) {
            isLaunchSymbolPresented = true
        }

        if reduceMotion {
            try? await Task.sleep(for: .milliseconds(420))
        } else {
            await playLaunchLightningStrike()
        }

        hasCompletedLaunchAnimation = true
        presentOnboardingIfNeeded()
        await Task.yield()

        withAnimation(handoffAnimation) {
            isLaunchSymbolHandedOff = true
        }

        try? await Task.sleep(for: handoffDelay)

#if DEBUG
        authLaunchDebugLog("launch bolt reached auth anchor")
#endif
        isLaunchBoltReadyForTransfer = true
        startAuthBoltTransferIfReady()
    }

    @MainActor
    private func playLaunchLightningStrike() async {
        try? await Task.sleep(for: .milliseconds(100))

#if DEBUG
        authLaunchDebugLog("bolt charge started")
#endif
        isLaunchStrikeVisible = true
        withAnimation(.smooth(duration: 0.66, extraBounce: 0)) {
            launchStrikeProgress = 1
        }

        try? await Task.sleep(for: .milliseconds(200))

#if DEBUG
        authLaunchDebugLog("bolt energy crest")
#endif
        withAnimation(.easeInOut(duration: 0.22)) {
            launchStrikePulse = 1
        }

        try? await Task.sleep(for: .milliseconds(220))
        withAnimation(.easeInOut(duration: 0.24)) {
            launchStrikePulse = 0
        }

        try? await Task.sleep(for: .milliseconds(160))
        withAnimation(.easeOut(duration: 0.12)) {
            isLaunchStrikeVisible = false
        }

        try? await Task.sleep(for: .milliseconds(80))
    }

    @MainActor
    private func startAuthBoltTransferIfReady() {
        guard isLaunchBoltReadyForTransfer,
              isAuthWalkthroughPrepared,
              !hasStartedAuthBoltTransfer else {
            return
        }

        hasStartedAuthBoltTransfer = true

        let transferAnimation: Animation = reduceMotion
            ? .easeInOut(duration: 0.12)
            : .smooth(duration: 0.18, extraBounce: 0)
        let transferDelay: Duration = reduceMotion ? .milliseconds(120) : .milliseconds(180)
        let textRevealDelay: Duration = reduceMotion ? .milliseconds(120) : .milliseconds(260)

#if DEBUG
        authLaunchDebugLog("transfer source=true destinationReady=true")
#endif
        withAnimation(transferAnimation) {
            isLaunchAnimationVisible = false
            isAuthWalkthroughBoltVisible = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: transferDelay)
            guard !Task.isCancelled else { return }

#if DEBUG
            authLaunchDebugLog("sheet released boltVisible=true textVisible=false")
#endif
            isAuthSheetPresentationReleased = true

            try? await Task.sleep(for: textRevealDelay)
            guard !Task.isCancelled else { return }

#if DEBUG
            authLaunchDebugLog("walkthrough text released")
#endif
            isAuthWalkthroughTextVisible = true
        }
    }
}

// MARK: - Launch Animation

private struct QuizFlashLaunchAnimationView: View {

    @Environment(ThemeManager.self) private var themeManager

    let isPresented: Bool
    let strikeProgress: CGFloat
    let isStrikeVisible: Bool
    let strikePulse: CGFloat
    let isHandedOff: Bool
    let boltNamespace: Namespace.ID

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let symbolScale: CGFloat = isHandedOff ? 1 : 58 / 38
            let symbolPosition = CGPoint(
                x: size.width / 2,
                y: isHandedOff ? authWalkthroughSymbolCenterY(in: size.height) : size.height / 2
            )

            boltSymbol
                .frame(width: 38, height: 38)
                .modifier(
                    AuthLaunchBoltGeometryModifier(
                        namespace: boltNamespace,
                        isSource: true
                    )
                )
                .scaleEffect(symbolScale)
                .position(symbolPosition)
                .opacity(isPresented ? 1.0 : 0.0)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var boltSymbol: some View {
        ZStack {
            boltImage
                .foregroundStyle(themeManager.accentColor.color)
                .blur(radius: 2.2)
                .scaleEffect(1.02)
                .opacity(Double(0.20 * strikePulse))

            boltImage
                .foregroundStyle(boltForegroundStyle)

            movingStrikeHighlight
        }
        .scaleEffect(1 + (0.025 * strikePulse))
        .offset(y: -0.8 * strikePulse)
    }

    private var boltForegroundStyle: AnyShapeStyle {
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    .white,
                    Color(red: 0.86, green: 0.82, blue: 1.0),
                    themeManager.accentColor.color
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var boltImage: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 38, weight: .heavy, design: .default))
            .symbolRenderingMode(.hierarchical)
    }

    private var movingStrikeHighlight: some View {
        ZStack {
            maskedStrikeBand(
                color: themeManager.accentColor.color,
                height: 22,
                offset: -34 + (72 * strikeProgress)
            )
            .opacity(0.42)

            maskedStrikeBand(
                color: .white,
                height: 8,
                offset: -29 + (72 * strikeProgress)
            )
            .opacity(0.90)
        }
        .opacity(isStrikeVisible ? 1 : 0)
    }

    private func maskedStrikeBand(
        color: Color,
        height: CGFloat,
        offset: CGFloat
    ) -> some View {
        boltImage
            .foregroundStyle(color)
            .mask {
                LinearGradient(
                    colors: [.clear, .white, .white, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 38, height: height)
                .offset(y: offset)
            }
    }

    private func authWalkthroughSymbolCenterY(in height: CGFloat) -> CGFloat {
        height * AuthLaunchLayout.walkthroughCenterYRatio
    }
}

#Preview {
    RootView()
        .environment(AuthManager.shared)
        .environment(OnboardingStateStore.shared)
        .environment(ThemeManager.shared)
}

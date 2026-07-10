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
    @State private var authenticatedHandoffAttemptID: UUID?
    @Namespace private var authLaunchBoltNamespace

    var body: some View {
        ZStack {
            themeManager.screenBackground
                .ignoresSafeArea()

            Group {
                if case .checking = authManager.sessionState {
                    ProgressActivityDots(color: themeManager.accentColor.color)
                } else if showsAuthenticationRoot {
                    authView
                } else {
                    mainAppView
                }
            }
            .id(rootContentIdentity)

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
        .onAppear {
            AuthFlowDebugTrace.recordWindowCheckpoint(
                "root.appear",
                layer: "root-view",
                state: authManager.sessionState
            )
        }
        .task {
            await playLaunchAnimationIfNeeded()
            presentOnboardingIfNeeded()
        }
        .onChange(of: authManager.sessionState) { oldState, newState in
            AuthFlowDebugTrace.recordWindowCheckpoint(
                "state.changed.\(oldState.debugName)-to-\(newState.debugName)",
                layer: "root-view",
                state: newState
            )
            scheduleAuthTraceCheckpoints(expectedState: newState)
#if DEBUG
            authLaunchDebugLog("root state \(stateName(oldState)) -> \(stateName(newState))")
#endif
            presentOnboardingIfNeeded()
        }
        .onChange(of: isAuthWalkthroughPrepared) { _, isPrepared in
            guard isPrepared else { return }

            Task { @MainActor in
                await Task.yield()
                startAuthBoltTransferIfReady()
            }
        }
        .onChange(of: authenticatedHandoffAttemptID) { _, attemptID in
            guard attemptID == nil else { return }
            presentOnboardingIfNeeded()
        }
    }

    private var mainAppView: some View {
        MainAppView()
            .onAppear {
                AuthFlowDebugTrace.recordWindowCheckpoint(
                    "main-app.appear",
                    layer: "root-view",
                    state: authManager.sessionState
                )
            }
    }

    private var authView: some View {
        LoginView(
            showsAuthWalkthrough: true,
            showsAuthWalkthroughBolt: isAuthWalkthroughBoltVisible || releasesAuthUIAfterLaunch,
            showsAuthWalkthroughText: isAuthWalkthroughTextVisible || releasesAuthUIAfterLaunch,
            allowsAuthWalkthroughAnimation: isAuthWalkthroughTextVisible || releasesAuthUIAfterLaunch,
            allowsAuthSheetPresentation: isAuthSheetPresentationReleased || releasesAuthUIAfterLaunch,
            launchBoltNamespace: authLaunchBoltNamespace,
            onAuthWalkthroughPrepared: {
                isAuthWalkthroughPrepared = true
            },
            onAuthenticationAttemptStarted: beginAuthenticatedHandoff,
            onAuthenticationAttemptCancelled: cancelAuthenticatedHandoff,
            onAuthenticationSheetDismissed: finishAuthenticatedHandoff
        )
    }

    private func beginAuthenticatedHandoff(attemptID: UUID) {
        guard authenticatedHandoffAttemptID == nil else {
            AuthFlowDebugTrace.record(
                "handoff.hold.start-ignored",
                layer: "root-view",
                details: [
                    "attempt": attemptID.uuidString,
                    "owner": authenticatedHandoffAttemptID?.uuidString ?? "none"
                ]
            )
            return
        }
        authenticatedHandoffAttemptID = attemptID
        AuthFlowDebugTrace.record(
            "handoff.hold.begin",
            layer: "root-view",
            details: [
                "attempt": attemptID.uuidString,
                "state": authManager.sessionState.debugName
            ]
        )
    }

    private func cancelAuthenticatedHandoff(attemptID: UUID) {
        guard authenticatedHandoffAttemptID == attemptID else {
            AuthFlowDebugTrace.record(
                "handoff.hold.cancel-ignored",
                layer: "root-view",
                details: [
                    "attempt": attemptID.uuidString,
                    "owner": authenticatedHandoffAttemptID?.uuidString ?? "none",
                    "reason": "stale-attempt"
                ]
            )
            return
        }
        guard case .signedIn = authManager.sessionState else {
            authenticatedHandoffAttemptID = nil
            AuthFlowDebugTrace.record(
                "handoff.hold.cancel",
                layer: "root-view",
                details: [
                    "attempt": attemptID.uuidString,
                    "state": authManager.sessionState.debugName
                ]
            )
            return
        }
        AuthFlowDebugTrace.record(
            "handoff.hold.cancel-ignored",
            layer: "root-view",
            details: [
                "attempt": attemptID.uuidString,
                "state": authManager.sessionState.debugName,
                "reason": "already-signed-in"
            ]
        )
    }

    private func finishAuthenticatedHandoff(attemptID: UUID) {
        guard authenticatedHandoffAttemptID == attemptID else {
            AuthFlowDebugTrace.record(
                "handoff.sheet-disappeared-ignored",
                layer: "root-view",
                details: [
                    "attempt": attemptID.uuidString,
                    "owner": authenticatedHandoffAttemptID?.uuidString ?? "none"
                ]
            )
            return
        }
        AuthFlowDebugTrace.record(
            "handoff.sheet-disappeared",
            layer: "root-view",
            details: [
                "attempt": attemptID.uuidString,
                "state": authManager.sessionState.debugName
            ]
        )

        Task { @MainActor in
            await Task.yield()
            guard authenticatedHandoffAttemptID == attemptID else { return }
            authenticatedHandoffAttemptID = nil
            AuthFlowDebugTrace.record(
                "handoff.root-release",
                layer: "root-view",
                details: [
                    "attempt": attemptID.uuidString,
                    "state": authManager.sessionState.debugName
                ]
            )
        }
    }

    private func scheduleAuthTraceCheckpoints(expectedState: AuthSessionState) {
        for delay in [100, 1_000] {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(delay))
                AuthFlowDebugTrace.recordWindowCheckpoint(
                    "state.checkpoint.\(delay)ms.expected-\(expectedState.debugName)",
                    layer: "root-view",
                    state: authManager.sessionState
                )
            }
        }
    }

    private func presentOnboardingIfNeeded() {
        guard hasCompletedLaunchAnimation else { return }
        guard authenticatedHandoffAttemptID == nil else { return }

        if case .signedIn(let user) = authManager.sessionState {
            onboardingStateStore.presentRequiredIfNeeded(for: user)
        } else if case .required = onboardingStateStore.presentation {
            onboardingStateStore.presentRequiredIfNeeded(for: nil)
        }
    }

    private func stateName(_ state: AuthSessionState) -> String {
        switch state {
        case .checking: "checking"
        case .signedOut: "signedOut"
        case .signedIn: "signedIn"
        case .emailVerificationRequired: "emailVerificationRequired"
        case .emailVerificationSucceeded: "emailVerificationSucceeded"
        }
    }

    private var rootContentIdentity: String {
        switch authManager.sessionState {
        case .checking:
            "checking"
        case .signedIn:
            showsAuthenticationRoot ? "auth" : "main"
        case .signedOut, .emailVerificationRequired, .emailVerificationSucceeded:
            "auth"
        }
    }

    private var showsAuthenticationRoot: Bool {
        switch authManager.sessionState {
        case .signedIn:
            authenticatedHandoffAttemptID != nil
        case .checking:
            false
        case .signedOut, .emailVerificationRequired, .emailVerificationSucceeded:
            true
        }
    }

    private var releasesAuthUIAfterLaunch: Bool {
        guard hasCompletedLaunchAnimation, !isLaunchAnimationVisible else { return false }

        switch authManager.sessionState {
        case .signedOut, .emailVerificationRequired, .emailVerificationSucceeded:
            return true
        case .checking, .signedIn:
            return false
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

        await finishLaunchForResolvedSession()
    }

    @MainActor
    private func finishLaunchForResolvedSession() async {
        while case .checking = authManager.sessionState {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
        }

        guard !Task.isCancelled else { return }

        if case .signedIn = authManager.sessionState {
            await dismissLaunchBoltIntoMainApp()
        } else {
            await handOffLaunchBoltToAuth()
        }
    }

    @MainActor
    private func dismissLaunchBoltIntoMainApp() async {
        let exitAnimation: Animation = reduceMotion
            ? .easeOut(duration: 0.16)
            : .easeInOut(duration: 0.24)
        let exitDelay: Duration = reduceMotion ? .milliseconds(160) : .milliseconds(240)

#if DEBUG
        authLaunchDebugLog("signed-in startup exits without auth handoff")
#endif
        withAnimation(exitAnimation) {
            isLaunchSymbolPresented = false
        }

        try? await Task.sleep(for: exitDelay)
        guard !Task.isCancelled else { return }

        isLaunchAnimationVisible = false
    }

    @MainActor
    private func handOffLaunchBoltToAuth() async {
        let handoffAnimation: Animation = reduceMotion
            ? .easeInOut(duration: 0.18)
            : .smooth(duration: 0.64, extraBounce: 0)
        let handoffDelay: Duration = reduceMotion ? .milliseconds(180) : .milliseconds(640)

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

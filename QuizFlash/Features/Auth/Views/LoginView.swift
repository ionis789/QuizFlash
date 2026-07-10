//
//  LoginView.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.12.2025.
//

import SwiftUI
import AuthenticationServices
import GoogleSignIn
import UIKit

#if DEBUG
private func authLayoutDebugLog(_ message: String) {
    print("AUTH_LAYOUT_DEBUG \(String(format: "%.3f", Date().timeIntervalSince1970)) login \(message)")
}
#endif

// MARK: - Login View

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(OnboardingStateStore.self) private var onboardingStateStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var authSheetMode: AuthSheetMode = .actions
    @State private var isAuthSheetPresented = false
    @State private var activeSheet: AuthSheet?
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var presentingViewController: UIViewController?
    @State private var authSheetPresentationTask: Task<Void, Never>?
    @State private var authWalkthroughVisibilityTask: Task<Void, Never>?
    @State private var isAuthWalkthroughHiddenBySheet = false
    @State private var isAuthWalkthroughAnimationPausedForSheet = false
    @State private var authenticationHandoffAttemptID: UUID?
    @State private var authenticationWelcomeAttemptID: UUID?
    @State private var isAuthenticationCenterContentVisible = true
    @State private var showsAuthenticationWelcome = false

    let showsAuthWalkthrough: Bool
    let showsAuthWalkthroughBolt: Bool
    let showsAuthWalkthroughText: Bool
    let allowsAuthWalkthroughAnimation: Bool
    let allowsAuthSheetPresentation: Bool
    let launchBoltNamespace: Namespace.ID?
    let onAuthWalkthroughPrepared: () -> Void
    let onAuthenticationAttemptStarted: @MainActor (UUID) -> Void
    let onAuthenticationAttemptCancelled: @MainActor (UUID) -> Void
    let onAuthenticationHandoffCompleted: @MainActor (UUID) -> Void

    init(
        showsAuthWalkthrough: Bool = true,
        showsAuthWalkthroughBolt: Bool = true,
        showsAuthWalkthroughText: Bool = true,
        allowsAuthWalkthroughAnimation: Bool = true,
        allowsAuthSheetPresentation: Bool = true,
        launchBoltNamespace: Namespace.ID? = nil,
        onAuthWalkthroughPrepared: @escaping () -> Void = {},
        onAuthenticationAttemptStarted: @escaping @MainActor (UUID) -> Void = { _ in },
        onAuthenticationAttemptCancelled: @escaping @MainActor (UUID) -> Void = { _ in },
        onAuthenticationHandoffCompleted: @escaping @MainActor (UUID) -> Void = { _ in }
    ) {
        self.showsAuthWalkthrough = showsAuthWalkthrough
        self.showsAuthWalkthroughBolt = showsAuthWalkthroughBolt
        self.showsAuthWalkthroughText = showsAuthWalkthroughText
        self.allowsAuthWalkthroughAnimation = allowsAuthWalkthroughAnimation
        self.allowsAuthSheetPresentation = allowsAuthSheetPresentation
        self.launchBoltNamespace = launchBoltNamespace
        self.onAuthWalkthroughPrepared = onAuthWalkthroughPrepared
        self.onAuthenticationAttemptStarted = onAuthenticationAttemptStarted
        self.onAuthenticationAttemptCancelled = onAuthenticationAttemptCancelled
        self.onAuthenticationHandoffCompleted = onAuthenticationHandoffCompleted
    }

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    var body: some View {
        ZStack {
            themeManager.screenBackground
                .ignoresSafeArea()

            if showsLoginForm {
                loginForm
            } else {
                authenticationStatusContent
            }
        }
        .background {
            AuthPresentingViewControllerReader { controller in
                presentingViewController = controller
            }
            .frame(width: 0, height: 0)
        }
        .fullScreenSheet(
            item: $activeSheet,
            configuration: secondaryAuthSheetConfiguration
        ) { sheet, _ in
            switch sheet {
            case .forgotPassword:
                ForgotPasswordView(
                    onSuccess: {
                        presentNotice(
                            title: AppLocalization.string("Email sent", locale: locale),
                            message: AppLocalization.string("Password reset link sent.", locale: locale)
                        )
                    },
                    onError: presentError
                )
            }
        } background: {
            AuthLoginSheetBackground()
        }
        .alert(
            alertTitle,
            isPresented: $showAlert
        ) {
            Button(AppLocalization.string("Done", locale: locale), role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            AuthFlowDebugTrace.recordWindowCheckpoint(
                "login-view.appear",
                layer: "login-view",
                state: authManager.sessionState
            )
        }
        .onDisappear {
            AuthFlowDebugTrace.recordWindowCheckpoint(
                "login-view.disappear",
                layer: "login-view",
                state: authManager.sessionState
            )
        }
        .onChange(of: isAuthSheetPresented) { oldValue, newValue in
            AuthFlowDebugTrace.record(
                "primary-sheet.changed",
                layer: "login-view",
                details: [
                    "from": String(oldValue),
                    "to": String(newValue),
                    "mode": String(describing: authSheetMode),
                    "state": authManager.sessionState.debugName
                ]
            )
        }
        .onChange(of: scenePhase) { oldValue, newValue in
            AuthFlowDebugTrace.record(
                "scene-phase.changed",
                layer: "login-view",
                details: [
                    "from": String(describing: oldValue),
                    "to": String(describing: newValue),
                    "state": authManager.sessionState.debugName
                ]
            )
        }
        .onChange(of: authManager.sessionState) { oldValue, newValue in
            AuthFlowDebugTrace.recordWindowCheckpoint(
                "observed-state.\(oldValue.debugName)-to-\(newValue.debugName)",
                layer: "login-view",
                state: newValue
            )
        }
    }

    private var loginForm: some View {
        authLanding
            .onAppear {
                presentAuthSheetIfNeeded()
            }
            .onDisappear {
                authSheetPresentationTask?.cancel()
                authSheetPresentationTask = nil
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                presentAuthSheetIfNeeded()
            }
            .onChange(of: allowsAuthSheetPresentation) { _, isAllowed in
                guard isAllowed else {
                    authSheetPresentationTask?.cancel()
                    authSheetPresentationTask = nil
                    return
                }

                presentAuthSheetIfNeeded()
            }
            .onChange(of: onboardingStateStore.presentation?.id) { _, presentationID in
                guard presentationID == nil else {
                    authSheetPresentationTask?.cancel()
                    authSheetPresentationTask = nil
                    return
                }

                presentAuthSheetIfNeeded()
            }
            .ignoresSafeArea(.keyboard, edges: activeSheet == nil ? [] : .bottom)
    }

    @ViewBuilder
    private var authenticationStatusContent: some View {
        switch authManager.sessionState {
        case .emailVerificationRequired(let user):
            EmailVerificationRequiredView(
                user: user,
                onResend: {
                    try await authManager.resendEmailVerification()
                },
                onReload: {
                    try await authManager.reloadEmailVerificationStatus()
                },
                onCancel: {
                    try await authManager.logout()
                },
                onResendSuccess: {
                    presentNotice(
                        title: AppLocalization.string("Email sent", locale: locale),
                        message: AppLocalization.string(
                            "Verification link sent. Check Inbox and Spam.",
                            locale: locale
                        )
                    )
                },
                onError: presentError
            )
        case .emailVerificationSucceeded(let user):
            EmailVerificationSuccessView(
                user: user,
                onContinue: {
                    authManager.completeEmailVerificationSuccess()
                }
            )
        case .checking:
            ProgressActivityDots(color: themeManager.accentColor.color)
        case .signedOut, .signedIn:
            EmptyView()
        }
    }

    private var showsLoginForm: Bool {
        switch authManager.sessionState {
        case .signedOut, .signedIn:
            true
        case .emailVerificationRequired, .emailVerificationSucceeded:
            authenticationHandoffAttemptID != nil
        case .checking:
            false
        }
    }

    private var authLanding: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                Group {
                    if showsAuthWalkthrough {
                        if showsAuthenticationWelcome {
                            Text(AppLocalization.string("Welcome", locale: locale))
                                .font(.system(size: 46, weight: .heavy))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .accessibilityAddTraits(.isHeader)
                        } else {
                            AuthWalkthroughText(
                                phrases: walkthroughPhrases,
                                symbolColor: themeManager.accentColor.color,
                                reduceMotion: reduceMotion,
                                animates: allowsAuthWalkthroughAnimation
                                    && !isAuthWalkthroughAnimationPausedForSheet,
                                showsBolt: showsAuthWalkthroughBolt,
                                showsText: showsAuthWalkthroughText,
                                launchBoltNamespace: launchBoltNamespace,
                                onPrepared: onAuthWalkthroughPrepared
                            )
                        }
                    } else {
                        Color.clear
                    }
                }
                .scaleRevealMotion(
                    isVisible: isAuthenticationCenterContentVisible,
                    reduceMotion: reduceMotion
                )
                .padding(.horizontal, UIConstants.Spacing.extraLarge)
                .frame(maxWidth: .infinity)
                .frame(height: 86)
                .compositingGroup()
                .opacity(isAuthWalkthroughHiddenBySheet ? 0 : 1)
                .animation(authWalkthroughVisibilityAnimation, value: isAuthWalkthroughHiddenBySheet)
                .accessibilityHidden(
                    isAuthWalkthroughHiddenBySheet || !isAuthenticationCenterContentVisible
                )
                .position(
                    x: proxy.size.width / 2,
                    y: proxy.size.height * AuthLaunchLayout.walkthroughCenterYRatio
                )
            }
        }
        .onAppear {
            isAuthWalkthroughHiddenBySheet = isEmailAuthSheetActive
            isAuthWalkthroughAnimationPausedForSheet = isEmailAuthSheetActive
        }
        .onChange(of: isEmailAuthSheetActive) { _, shouldHide in
            scheduleAuthWalkthroughVisibility(shouldHide: shouldHide)
        }
        .task(id: authenticationWelcomeAttemptID) {
            await transitionToAuthenticationWelcomeIfNeeded()
        }
        .onDisappear {
            authWalkthroughVisibilityTask?.cancel()
            authWalkthroughVisibilityTask = nil
        }
        .fullScreenSheet(
            isPresented: $isAuthSheetPresented,
            configuration: authSheetConfiguration
        ) { safeAreaInsets in
            AuthLoginSheetContent(
                mode: $authSheetMode,
                email: $email,
                password: $password,
                passwordConfirmation: $passwordConfirmation,
                activeAuthenticationAttemptID: $authenticationHandoffAttemptID,
                safeAreaInsets: safeAreaInsets,
                locale: locale,
                accentColor: themeManager.accentColor.color,
                reduceMotion: reduceMotion,
                onAuthenticationAttemptStarted: { attemptID in
                    onAuthenticationAttemptStarted(attemptID)
                },
                onAuthenticationAttemptCancelled: { attemptID in
                    onAuthenticationAttemptCancelled(attemptID)
                },
                onAuthenticationSheetDismissed: { attemptID in
                    completeAuthenticationHandoffAfterSheetDisappears(attemptID: attemptID)
                },
                hasAuthenticationStateAdvanced: {
                    switch authManager.sessionState {
                    case .signedIn, .emailVerificationRequired, .emailVerificationSucceeded:
                        true
                    case .checking, .signedOut:
                        false
                    }
                },
                onAppleSignIn: {
                    try await authManager.signInWithApple()
                },
                onGoogleSignIn: {
                    try await authManager.signInWithGoogle(
                        presentingViewController: presentingViewController
                    )
                },
                onForgotPassword: {
                    activeSheet = .forgotPassword
                },
                onSignIn: { email, password in
                    try await authManager.signIn(email: email, password: password)
                },
                onCreateAccount: { email, password, confirmation in
                    let user = try await authManager.createAccount(
                        email: email,
                        password: password,
                        confirmation: confirmation
                    )
                    onboardingStateStore.markPendingForNewAccount(uid: user.uid)
                },
                onError: presentError
            )
        } background: {
            AuthLoginSheetBackground()
        }
    }

    private var authSheetConfiguration: FullScreenSheetConfiguration {
        .sheet(
            heightMode: .adaptiveAbsolute(authSheetHeight, maxFraction: 0.66),
            dragActivationArea: .fixed(0),
            showsBackdropBlur: false,
            showsDefaultTopProgressiveBlur: false,
            avoidsKeyboard: activeSheet == nil,
            hidesTabBar: false,
            debugIdentifier: "auth.primary"
        )
    }

    private var secondaryAuthSheetConfiguration: FullScreenSheetConfiguration {
        .sheet(
            heightMode: .adaptiveAbsolute(380, maxFraction: 0.62),
            dragActivationArea: .fullSurface,
            showsDragIndicator: false,
            showsBackdropBlur: true,
            showsDefaultTopProgressiveBlur: false,
            avoidsKeyboard: true,
            hidesTabBar: false,
            debugIdentifier: "auth.secondary"
        )
    }

    private var authSheetHeight: CGFloat {
        switch authSheetMode {
        case .actions:
            280
        case .login:
            500
        case .signUp:
            570
        }
    }

    private var isEmailAuthSheetActive: Bool {
        isAuthSheetPresented && authSheetMode != .actions
    }

    private var authWalkthroughVisibilityAnimation: Animation {
        reduceMotion
            ? .linear(duration: UIConstants.Animation.instant)
            : .easeInOut(duration: UIConstants.Animation.standard)
    }

    private func scheduleAuthWalkthroughVisibility(shouldHide: Bool) {
        authWalkthroughVisibilityTask?.cancel()
        authWalkthroughVisibilityTask = Task { @MainActor in
            guard !reduceMotion else {
                isAuthWalkthroughHiddenBySheet = shouldHide
                isAuthWalkthroughAnimationPausedForSheet = shouldHide
                return
            }

            if shouldHide {
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }

                isAuthWalkthroughHiddenBySheet = true

                try? await Task.sleep(for: .seconds(UIConstants.Animation.standard))
                guard !Task.isCancelled else { return }

                isAuthWalkthroughAnimationPausedForSheet = true
                return
            }

            isAuthWalkthroughAnimationPausedForSheet = true

            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            isAuthWalkthroughHiddenBySheet = false

            try? await Task.sleep(for: .seconds(UIConstants.Animation.standard))
            guard !Task.isCancelled else { return }

            isAuthWalkthroughAnimationPausedForSheet = false
        }
    }

    private var walkthroughPhrases: [String] {
        [
            AppLocalization.string("Let's study", locale: locale),
            AppLocalization.string("Let's review", locale: locale),
            AppLocalization.string("Let's master", locale: locale),
            AppLocalization.string("Let's focus", locale: locale)
        ]
    }

    private func presentError(_ error: Error) {
        guard !isUserCancelledSignIn(error) else { return }

        alertTitle = AppLocalization.string("Something went wrong", locale: locale)
        alertMessage = localizedError(error)
        showAlert = true
    }

    private func presentNotice(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    private func localizedError(_ error: Error) -> String {
        AuthErrorPresentation.message(for: error, locale: locale)
    }

    private func isUserCancelledSignIn(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == kGIDSignInErrorDomain
            && error.code == GIDSignInError.canceled.rawValue {
            return true
        }

        return error.domain == ASAuthorizationError.errorDomain
            && error.code == ASAuthorizationError.canceled.rawValue
    }

    private func completeAuthenticationHandoffAfterSheetDisappears(attemptID: UUID) {
        guard authenticationHandoffAttemptID == attemptID else {
            AuthFlowDebugTrace.record(
                "handoff.local-release.ignored",
                layer: "login-view",
                details: [
                    "attempt": attemptID.uuidString,
                    "owner": authenticationHandoffAttemptID?.uuidString ?? "none"
                ]
            )
            return
        }

        AuthFlowDebugTrace.record(
            "handoff.local-release.scheduled",
            layer: "login-view",
            details: ["attempt": attemptID.uuidString]
        )
        Task { @MainActor in
            await Task.yield()
            guard authenticationHandoffAttemptID == attemptID else { return }

            if case .signedIn = authManager.sessionState {
                authenticationWelcomeAttemptID = attemptID
                AuthFlowDebugTrace.record(
                    "handoff.welcome.requested",
                    layer: "login-view",
                    details: ["attempt": attemptID.uuidString]
                )
            } else {
                completeAuthenticationHandoff(attemptID: attemptID)
            }
        }
    }

    @MainActor
    private func transitionToAuthenticationWelcomeIfNeeded() async {
        guard let attemptID = authenticationWelcomeAttemptID,
              authenticationHandoffAttemptID == attemptID else {
            return
        }

        AuthFlowDebugTrace.record(
            "welcome.scale-reveal.hide-walkthrough",
            layer: "login-view",
            details: ["attempt": attemptID.uuidString]
        )
        isAuthenticationCenterContentVisible = false

        guard await waitForAuthenticationWelcomePhase(
            reduceMotion ? .milliseconds(10) : ScaleRevealMotion.contentSwapDelay,
            attemptID: attemptID
        ) else { return }

        showsAuthenticationWelcome = true
        AuthFlowDebugTrace.record(
            "welcome.scale-reveal.content-swapped",
            layer: "login-view",
            details: ["attempt": attemptID.uuidString]
        )

        guard await waitForAuthenticationWelcomePhase(
            reduceMotion ? .milliseconds(10) : ScaleRevealMotion.revealDelay,
            attemptID: attemptID
        ) else { return }

        isAuthenticationCenterContentVisible = true
        AuthFlowDebugTrace.record(
            "welcome.scale-reveal.visible",
            layer: "login-view",
            details: ["attempt": attemptID.uuidString]
        )

        guard await waitForAuthenticationWelcomePhase(
            .seconds(UIConstants.Animation.slow * 2),
            attemptID: attemptID
        ) else { return }

        isAuthenticationCenterContentVisible = false
        AuthFlowDebugTrace.record(
            "welcome.scale-reveal.hide-before-home",
            layer: "login-view",
            details: ["attempt": attemptID.uuidString]
        )

        guard await waitForAuthenticationWelcomePhase(
            reduceMotion ? .milliseconds(10) : ScaleRevealMotion.contentSwapDelay,
            attemptID: attemptID
        ) else { return }

        completeAuthenticationWelcome()
    }

    @MainActor
    private func waitForAuthenticationWelcomePhase(
        _ duration: Duration,
        attemptID: UUID
    ) async -> Bool {
        do {
            try await Task.sleep(for: duration)
        } catch {
            return false
        }

        return authenticationWelcomeAttemptID == attemptID
            && authenticationHandoffAttemptID == attemptID
            && !Task.isCancelled
    }

    private func completeAuthenticationWelcome() {
        guard let attemptID = authenticationWelcomeAttemptID,
              authenticationHandoffAttemptID == attemptID else {
            AuthFlowDebugTrace.record(
                "handoff.welcome.completion-ignored",
                layer: "login-view",
                details: [
                    "welcomeAttempt": authenticationWelcomeAttemptID?.uuidString ?? "none",
                    "handoffOwner": authenticationHandoffAttemptID?.uuidString ?? "none"
                ]
            )
            return
        }

        AuthFlowDebugTrace.record(
            "handoff.welcome.completed",
            layer: "login-view",
            details: ["attempt": attemptID.uuidString]
        )
        authenticationWelcomeAttemptID = nil
        completeAuthenticationHandoff(attemptID: attemptID)
    }

    private func completeAuthenticationHandoff(attemptID: UUID) {
        guard authenticationHandoffAttemptID == attemptID else { return }
        authenticationHandoffAttemptID = nil
        onAuthenticationHandoffCompleted(attemptID)
    }

    private var canPresentAuthSheet: Bool {
        guard allowsAuthSheetPresentation else { return false }
        guard onboardingStateStore.presentation == nil else { return false }

        switch authManager.sessionState {
        case .signedOut, .signedIn:
            return true
        default:
            return false
        }
    }

    private func presentAuthSheetIfNeeded() {
        guard canPresentAuthSheet else {
            authSheetPresentationTask?.cancel()
            authSheetPresentationTask = nil
            return
        }

        authSheetPresentationTask?.cancel()

        authSheetPresentationTask = Task { @MainActor in
            await Task.yield()
            await Task.yield()
            guard !Task.isCancelled, canPresentAuthSheet else { return }

            if !isAuthSheetPresented {
                setAuthSheetPresentedWithoutExternalAnimation(true)
            }

            authSheetPresentationTask = nil
        }
    }

    private func setAuthSheetPresentedWithoutExternalAnimation(_ isPresented: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isAuthSheetPresented = isPresented
        }
    }
}

private enum AuthSheetMode: Equatable {
    case actions
    case login
    case signUp
}

// MARK: - Auth Login Sheet Content

private struct AuthLoginSheetContent: View {
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.fullScreenSheetDismissCoordinator) private var dismissCoordinator

    @Binding var mode: AuthSheetMode
    @Binding var email: String
    @Binding var password: String
    @Binding var passwordConfirmation: String
    @Binding var activeAuthenticationAttemptID: UUID?

    let safeAreaInsets: UIEdgeInsets
    let locale: Locale
    let accentColor: Color
    let reduceMotion: Bool
    let onAuthenticationAttemptStarted: @MainActor (UUID) -> Void
    let onAuthenticationAttemptCancelled: @MainActor (UUID) -> Void
    let onAuthenticationSheetDismissed: @MainActor (UUID) -> Void
    let hasAuthenticationStateAdvanced: @MainActor () -> Bool
    let onAppleSignIn: @MainActor @Sendable () async throws -> Void
    let onGoogleSignIn: @MainActor @Sendable () async throws -> Void
    let onForgotPassword: @MainActor @Sendable () -> Void
    let onSignIn: @MainActor @Sendable (String, String) async throws -> Void
    let onCreateAccount: @MainActor @Sendable (String, String, String) async throws -> Void
    let onError: @MainActor @Sendable (Error) -> Void

    @State private var displayedMode: AuthSheetMode = .actions
    @State private var isContentVisible = true
    @State private var modeTransitionTask: Task<Void, Never>?
    @State private var keyboardMonitor = KeyboardMonitor.shared
    @State private var successfulDismissAttemptID: UUID?

    private var contentTransition: Animation {
        ScaleRevealMotion.animation(reduceMotion: reduceMotion)
    }

    var body: some View {
        Group {
            if displayedMode == .actions {
                contentStack
                    .frame(maxHeight: .infinity, alignment: .top)
                    .dismissKeyboardOnBackgroundTap()
            } else {
                ScrollView(showsIndicators: false) {
                    contentStack
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .dismissKeyboardOnBackgroundTap()
            }
        }
#if DEBUG
        .authLayoutDebugFrame("content.root.\(displayedMode)")
#endif
        .onAppear {
            AuthFlowDebugTrace.record(
                "sheet-content.appear",
                layer: "login-sheet",
                details: [
                    "mode": String(describing: mode),
                    "displayedMode": String(describing: displayedMode)
                ]
            )
#if DEBUG
            authLayoutDebugLog(
                "content.onAppear mode=\(mode) displayedMode=\(displayedMode) visible=\(isContentVisible) safeTop=\(safeAreaInsets.top) safeBottom=\(safeAreaInsets.bottom) reduceMotion=\(reduceMotion)"
            )
#endif
            displayedMode = mode
            isContentVisible = true
            configureDismissCoordinator()
        }
        .onDisappear {
            let completedAttemptID = successfulDismissAttemptID
            AuthFlowDebugTrace.record(
                "sheet-content.disappear",
                layer: "login-sheet",
                details: [
                    "mode": String(describing: mode),
                    "displayedMode": String(describing: displayedMode),
                    "handoffAttempt": completedAttemptID?.uuidString ?? "none"
                ]
            )
            modeTransitionTask?.cancel()
            modeTransitionTask = nil
            dismissCoordinator?.shouldAllowDismiss = nil
            dismissCoordinator?.onBlockedDismiss = nil

            if let completedAttemptID {
                AuthFlowDebugTrace.record(
                    "handoff.sheet-content.disappeared",
                    layer: "login-sheet",
                    details: ["attempt": completedAttemptID.uuidString]
                )
                onAuthenticationSheetDismissed(completedAttemptID)
            }
        }
        .onChange(of: mode) { _, newMode in
            guard newMode != displayedMode else { return }
#if DEBUG
            authLayoutDebugLog("content.modeChange animated oldDisplayed=\(displayedMode) newMode=\(newMode)")
#endif
            setMode(newMode)
        }
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            modeContent
                .scaleRevealMotion(
                    isVisible: isContentVisible,
                    reduceMotion: reduceMotion,
                    hiddenOpacity: 0.3
                )
                .disabled(activeAuthenticationAttemptID != nil)
        }
        .padding(.horizontal, UIConstants.Spacing.large)
        .padding(.top, UIConstants.Spacing.extraLarge)
        .padding(.bottom, max(safeAreaInsets.bottom, UIConstants.Spacing.extraLarge))
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
#if DEBUG
        .authLayoutDebugFrame("content.stack.\(displayedMode)")
#endif
    }

    @ViewBuilder
    private var modeContent: some View {
        switch displayedMode {
        case .actions:
            actionButtons
        case .login:
            loginFields
        case .signUp:
            signUpFields
        }
    }

    private var actionButtons: some View {
        VStack(spacing: UIConstants.Spacing.medium) {
            AuthLandingAsyncButton(
                title: AppLocalization.string("Continue with Apple", locale: locale),
                systemImage: "applelogo",
                style: .light
            ) {
                try await performAuthenticatedSignIn(onAppleSignIn)
            } onError: { error in
                onError(error)
            }

            AuthLandingAsyncButton(
                title: AppLocalization.string("Continue with Google", locale: locale),
                textIcon: "G",
                style: .dark
            ) {
                try await performAuthenticatedSignIn(onGoogleSignIn)
            } onError: { error in
                onError(error)
            }

            AuthLandingButton(
                title: AppLocalization.string("Continue with email", locale: locale),
                systemImage: "envelope.fill",
                style: .dark
            ) {
                setMode(.login)
            }
        }
#if DEBUG
        .authLayoutDebugFrame("content.actions")
#endif
    }

    private var loginFields: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            VStack(spacing: UIConstants.Spacing.medium) {
                AuthIconTextField(
                    title: AppLocalization.string("Email Address", locale: locale),
                    icon: "envelope",
                    text: $email
                )
                .keyboardType(.emailAddress)
                .textContentType(.username)

                AuthIconTextField(
                    title: AppLocalization.string("Password", locale: locale),
                    icon: "lock",
                    isPassword: true,
                    text: $password
                )
            }

            Button(action: onForgotPassword) {
                Text(AppLocalization.string("Forgot Password?", locale: locale))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)

            AuthAsyncButton(
                title: AppLocalization.string("Sign In", locale: locale),
                icon: nil,
                tint: accentColor,
                isEnabled: canSignIn
            ) {
                try await performAuthenticatedSignIn {
                    try await onSignIn(email, password)
                }
            } onError: { error in
                onError(error)
            }
            .padding(.top, UIConstants.Spacing.small)

            switchToSignUpPrompt
        }
    }

    private var signUpFields: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            VStack(spacing: UIConstants.Spacing.medium) {
                AuthIconTextField(
                    title: AppLocalization.string("Email Address", locale: locale),
                    icon: "envelope",
                    text: $email
                )
                .keyboardType(.emailAddress)
                .textContentType(.username)

                AuthIconTextField(
                    title: AppLocalization.string("Password", locale: locale),
                    icon: "lock",
                    isPassword: true,
                    passwordTextContentType: .password,
                    text: $password
                )

                AuthIconTextField(
                    title: AppLocalization.string("Confirm Password", locale: locale),
                    icon: "lock",
                    isPassword: true,
                    passwordTextContentType: .password,
                    text: $passwordConfirmation
                )
            }

            AuthAsyncButton(
                title: AppLocalization.string("Create Account", locale: locale),
                icon: "person.badge.plus",
                tint: accentColor,
                isEnabled: canCreateAccount
            ) {
                try await performAuthenticatedSignIn {
                    try await onCreateAccount(email, password, passwordConfirmation)
                }
            } onError: { error in
                onError(error)
            }
            .padding(.top, UIConstants.Spacing.small)

            switchToSignInPrompt
        }
    }

    private var switchToSignUpPrompt: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            Text(AppLocalization.string("Don't have an account?", locale: locale))
                .foregroundStyle(Color.white.opacity(0.56))

            Button {
                setMode(.signUp)
            } label: {
                Text(AppLocalization.string("Sign Up", locale: locale))
                    .fontWeight(.semibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(accentColor)
        }
        .font(.callout)
        .frame(maxWidth: .infinity)
        .padding(.top, UIConstants.Spacing.small)
    }

    @MainActor
    private func performAuthenticatedSignIn(
        _ action: @MainActor @Sendable () async throws -> Void
    ) async throws {
        guard activeAuthenticationAttemptID == nil else {
            AuthFlowDebugTrace.record(
                "handoff.attempt.ignored",
                layer: "login-sheet",
                details: [
                    "reason": "attempt-in-progress",
                    "owner": activeAuthenticationAttemptID?.uuidString ?? "none"
                ]
            )
            return
        }

        let attemptID = UUID()
        activeAuthenticationAttemptID = attemptID
        onAuthenticationAttemptStarted(attemptID)

        do {
            try await action()
        } catch {
            if hasAuthenticationStateAdvanced() {
                AuthFlowDebugTrace.record(
                    "handoff.attempt.error-after-authentication",
                    layer: "login-sheet",
                    details: [
                        "attempt": attemptID.uuidString,
                        "error": String(describing: type(of: error))
                    ]
                )
                requestSuccessfulAuthenticationDismiss(attemptID: attemptID)
                return
            }

            guard activeAuthenticationAttemptID == attemptID else { throw error }
            activeAuthenticationAttemptID = nil
            onAuthenticationAttemptCancelled(attemptID)
            throw error
        }

        requestSuccessfulAuthenticationDismiss(attemptID: attemptID)
    }

    @MainActor
    private func requestSuccessfulAuthenticationDismiss(attemptID: UUID) {
        guard activeAuthenticationAttemptID == attemptID else {
            AuthFlowDebugTrace.record(
                "handoff.dismiss.ignored",
                layer: "login-sheet",
                details: [
                    "attempt": attemptID.uuidString,
                    "owner": activeAuthenticationAttemptID?.uuidString ?? "none"
                ]
            )
            return
        }

        successfulDismissAttemptID = attemptID
        AuthFlowDebugTrace.record(
            "handoff.dismiss.request",
            layer: "login-sheet",
            details: ["attempt": attemptID.uuidString]
        )
        dismissCoordinator?.shouldAllowDismiss = { true }

        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss {
                AuthFlowDebugTrace.record(
                    "handoff.dismiss.animation-completed",
                    layer: "login-sheet",
                    details: ["attempt": attemptID.uuidString]
                )
            }
        } else {
            AuthFlowDebugTrace.record(
                "handoff.dismiss.action-missing",
                layer: "login-sheet",
                details: ["attempt": attemptID.uuidString]
            )
            onAuthenticationSheetDismissed(attemptID)
        }
    }

    private var switchToSignInPrompt: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            Text(AppLocalization.string("Already have an account?", locale: locale))
                .foregroundStyle(Color.white.opacity(0.56))

            Button {
                setMode(.login)
            } label: {
                Text(AppLocalization.string("Sign In", locale: locale))
                    .fontWeight(.semibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(accentColor)
        }
        .font(.callout)
        .frame(maxWidth: .infinity)
        .padding(.top, UIConstants.Spacing.small)
    }

    private var canSignIn: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    private var canCreateAccount: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && password == passwordConfirmation
    }

    private func setMode(_ newMode: AuthSheetMode) {
        guard newMode != displayedMode else { return }

        modeTransitionTask?.cancel()
        modeTransitionTask = Task { @MainActor in
            defer { modeTransitionTask = nil }

#if DEBUG
            authLayoutDebugLog("setMode begin from=\(displayedMode) to=\(newMode) mode=\(mode)")
#endif
            await dismissKeyboardBeforeModeTransitionIfNeeded()
            guard !Task.isCancelled else { return }

            withAnimation(contentTransition) {
                isContentVisible = false
            }

            guard !reduceMotion else {
                displayedMode = newMode
                mode = newMode
                configureDismissCoordinator()
                isContentVisible = true
#if DEBUG
                authLayoutDebugLog("setMode reduceMotion applied displayedMode=\(displayedMode) mode=\(mode)")
#endif
                return
            }

            try? await Task.sleep(for: ScaleRevealMotion.contentSwapDelay)
            guard !Task.isCancelled else { return }

            displayedMode = newMode
            mode = newMode
            configureDismissCoordinator()
#if DEBUG
            authLayoutDebugLog("setMode swapped displayedMode=\(displayedMode) mode=\(mode)")
#endif

            try? await Task.sleep(for: ScaleRevealMotion.revealDelay)
            guard !Task.isCancelled else { return }

            withAnimation(contentTransition) {
                isContentVisible = true
            }
#if DEBUG
            authLayoutDebugLog("setMode reveal visible=\(isContentVisible) displayedMode=\(displayedMode) mode=\(mode)")
#endif
        }
    }

    @MainActor
    private func dismissKeyboardBeforeModeTransitionIfNeeded() async {
        guard keyboardMonitor.isVisible else { return }

        let dismissalDuration = max(
            keyboardMonitor.animationDuration,
            UIConstants.Animation.standard
        )

#if DEBUG
        authLayoutDebugLog("setMode dismissKeyboard duration=\(dismissalDuration)")
#endif
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )

        try? await Task.sleep(for: .seconds(dismissalDuration))
    }

    private func configureDismissCoordinator() {
        dismissCoordinator?.shouldAllowDismiss = {
            false
        }
        dismissCoordinator?.onBlockedDismiss = {
            guard mode != .actions else { return }
            setMode(.actions)
        }
    }
}

// MARK: - Auth Walkthrough Text

private struct AuthWalkthroughText: View {
    let phrases: [String]
    let symbolColor: Color
    let reduceMotion: Bool
    let animates: Bool
    let showsBolt: Bool
    let showsText: Bool
    let launchBoltNamespace: Namespace.ID?
    let onPrepared: () -> Void

    @State private var intros: [AuthIntro] = []
    @State private var activeIntro: AuthIntro?
    @State private var animationRunID = UUID()
    @State private var isTextLayerVisible = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            if let activeIntro {
                Rectangle()
                    .fill(activeIntro.backgroundColor)
                    .overlay {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 38, weight: .heavy))
                            .foregroundStyle(activeIntro.symbolColor)
                            .frame(width: 38, height: 38)
                            .modifier(
                                AuthLaunchBoltGeometryModifier(
                                    namespace: launchBoltNamespace,
                                    isSource: false
                                )
                            )
                            .opacity(showsBolt ? 1 : 0)
                            .animation(nil, value: showsBolt)
                            .background(alignment: .leading) {
                                Capsule()
                                    .fill(activeIntro.backgroundColor)
                                    .frame(width: size.width)
                            }
                            .background(alignment: .leading) {
                                Text(activeIntro.text)
                                    .font(.largeTitle.weight(.bold))
                                    .foregroundStyle(activeIntro.textColor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                    .frame(width: textSize(activeIntro.text), alignment: .leading)
                                    .offset(x: 10)
                                    .offset(x: activeIntro.textOffset)
                                    .opacity(showsText && isTextLayerVisible ? 1 : 0)
                                    .animation(nil, value: showsText)
                                    .animation(nil, value: isTextLayerVisible)
                            }
                            .offset(x: -activeIntro.symbolOffset)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 86)
        .clipped()
        .task(id: "\(phrases.joined(separator: "|"))-\(animates)") {
            let runID = UUID()
            animationRunID = runID
            isTextLayerVisible = false
            configureIntros()

            if activeIntro == nil {
                activeIntro = intros.first
                onPrepared()
#if DEBUG
                authLaunchDebugLog("walkthrough target ready")
#endif
            } else {
                resetActiveIntroState()
            }

            guard animates, intros.count > 1, !reduceMotion else { return }

            try? await Task.sleep(for: .milliseconds(250))
            guard animates, animationRunID == runID, !Task.isCancelled else { return }

            isTextLayerVisible = true
            animate(0, runID: runID)
        }
        .onChange(of: animates) { _, animates in
            animationRunID = UUID()
            guard !animates else { return }
            isTextLayerVisible = false
            resetActiveIntroState()
        }
    }

    private func configureIntros() {
        intros = phrases.map {
            AuthIntro(
                text: $0,
                textColor: .white,
                symbolColor: symbolColor,
                backgroundColor: .black
            )
        }

        if let first = intros.first {
            intros.append(first)
        }
    }

    private func animate(_ index: Int, loop: Bool = true, runID: UUID) {
        guard animates, animationRunID == runID else { return }

        if intros.indices.contains(index + 1) {
            activeIntro?.text = intros[index].text
            activeIntro?.textColor = intros[index].textColor

            withAnimation(.snappy(duration: 1), completionCriteria: .removed) {
                activeIntro?.textOffset = -(textSize(intros[index].text) + 20)
                activeIntro?.symbolOffset = -(textSize(intros[index].text) + 20) / 2
            } completion: {
                guard animates, animationRunID == runID else { return }

                withAnimation(.snappy(duration: 0.8), completionCriteria: .logicallyComplete) {
                    activeIntro?.textOffset = 0
                    activeIntro?.symbolOffset = 0
                    activeIntro?.symbolColor = intros[index + 1].symbolColor
                    activeIntro?.backgroundColor = intros[index + 1].backgroundColor
                } completion: {
                    guard animates, animationRunID == runID else { return }
                    animate(index + 1, loop: loop, runID: runID)
                }
            }
        } else if loop {
            animate(0, loop: loop, runID: runID)
        }
    }

    private func resetActiveIntroState() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let firstIntro = intros.first {
                activeIntro?.text = firstIntro.text
                activeIntro?.textColor = firstIntro.textColor
                activeIntro?.symbolColor = firstIntro.symbolColor
                activeIntro?.backgroundColor = firstIntro.backgroundColor
            }
            activeIntro?.textOffset = 0
            activeIntro?.symbolOffset = 0
        }
    }

    private func textSize(_ text: String) -> CGFloat {
        NSString(string: text).size(
            withAttributes: [
                .font: UIFont.preferredFont(forTextStyle: .largeTitle)
            ]
        ).width
    }
}

private struct AuthIntro: Identifiable {
    let id = UUID()
    var text: String
    var textColor: Color
    var symbolColor: Color
    var backgroundColor: Color
    var symbolOffset: CGFloat = 0
    var textOffset: CGFloat = 0
}

// MARK: - Auth Landing Buttons

private enum AuthLandingButtonStyle {
    case light
    case dark

    var background: Color {
        switch self {
        case .light: .white
        case .dark: Color.white.opacity(0.08)
        }
    }

    var foreground: Color {
        switch self {
        case .light: .black
        case .dark: .white
        }
    }
}

private struct AuthLandingButton: View {
    let title: String
    var systemImage: String?
    var textIcon: String?
    var style: AuthLandingButtonStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AuthLandingButtonLabel(
                title: title,
                systemImage: systemImage,
                textIcon: textIcon,
                style: style,
                isLoading: false
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AuthLandingAsyncButton: View {
    let title: String
    var systemImage: String?
    var textIcon: String?
    var style: AuthLandingButtonStyle
    let action: @MainActor @Sendable () async throws -> Void
    let onError: @MainActor @Sendable (Error) -> Void

    @State private var isLoading = false

    var body: some View {
        Button {
            guard !isLoading else { return }

            AuthFlowDebugTrace.record(
                "button.tap",
                layer: "login-sheet",
                details: ["title": title]
            )

            Task { @MainActor in
                isLoading = true
                AuthFlowDebugTrace.record(
                    "button.task.begin",
                    layer: "login-sheet",
                    details: ["title": title, "cancelled": String(Task.isCancelled)]
                )
                defer {
                    isLoading = false
                    AuthFlowDebugTrace.record(
                        "button.task.end",
                        layer: "login-sheet",
                        details: ["title": title, "cancelled": String(Task.isCancelled)]
                    )
                }

                do {
                    try await action()
                    AuthFlowDebugTrace.record(
                        "button.action.succeeded",
                        layer: "login-sheet",
                        details: ["title": title]
                    )
                } catch {
                    AuthFlowDebugTrace.record(
                        "button.action.failed",
                        layer: "login-sheet",
                        details: [
                            "title": title,
                            "error": String(describing: type(of: error)),
                            "cancelled": String(error is CancellationError)
                        ]
                    )
                    onError(error)
                }
            }
        } label: {
            AuthLandingButtonLabel(
                title: title,
                systemImage: systemImage,
                textIcon: textIcon,
                style: style,
                isLoading: isLoading
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .animation(.easeInOut(duration: UIConstants.Animation.instant), value: isLoading)
        .onDisappear {
            guard isLoading else { return }
            AuthFlowDebugTrace.record(
                "button.disappear.while-loading",
                layer: "login-sheet",
                details: ["title": title]
            )
        }
    }
}

private struct AuthLandingButtonLabel: View {
    let title: String
    var systemImage: String?
    var textIcon: String?
    var style: AuthLandingButtonStyle
    var isLoading: Bool

    var body: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title3.weight(.bold))
            } else if let textIcon {
                Text(textIcon)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
            }

            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .opacity(isLoading ? 0 : 1)
        .overlay {
            if isLoading {
                ProgressActivityDots(color: style.foreground)
            }
        }
        .foregroundStyle(style.foreground)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(style.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Auth Sheet Surface

private struct AuthLoginSheetBackground: View {
    var body: some View {
        Color.black
            .overlay(Color.white.opacity(0.10))
    }
}

// MARK: - Auth Sheet

private enum AuthSheet: Identifiable {
    case forgotPassword

    var id: String {
        switch self {
        case .forgotPassword: "forgotPassword"
        }
    }
}

// MARK: - Forgot Password View

private struct ForgotPasswordView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.fullScreenSheetDismissCoordinator) private var dismissCoordinator

    @State private var email = ""
    @State private var keyboardMonitor = KeyboardMonitor.shared

    let onSuccess: @MainActor @Sendable () -> Void
    let onError: @MainActor @Sendable (Error) -> Void

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                Text(AppLocalization.string("Forgot Password?", locale: locale))
                    .font(.title.weight(.bold))

                AuthIconTextField(
                    title: AppLocalization.string("Email Address", locale: locale),
                    icon: "envelope",
                    text: $email
                )
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .padding(.top, UIConstants.Spacing.small)

                AuthAsyncButton(
                    title: AppLocalization.string("Send Reset Link", locale: locale),
                    icon: "paperplane.fill",
                    tint: themeManager.accentColor.color,
                    isEnabled: !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    try await authManager.sendPasswordReset(email: email)
                    if let fullScreenSheetDismiss {
                        fullScreenSheetDismiss {
                            onSuccess()
                        }
                    } else {
                        onSuccess()
                    }
                } onError: { error in
                    onError(error)
                }
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.extraLarge)
            .padding(.bottom, UIConstants.Spacing.huge * 2)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.never)
        .dismissKeyboardOnBackgroundTap()
        .onAppear {
            configureDismissCoordinator()
        }
        .onDisappear {
            dismissCoordinator?.shouldAllowDismiss = nil
            dismissCoordinator?.onBlockedDismiss = nil
        }
        .onChange(of: keyboardMonitor.isVisible) {
            configureDismissCoordinator()
        }
    }

    private func configureDismissCoordinator() {
        dismissCoordinator?.shouldAllowDismiss = {
            !keyboardMonitor.isVisible
        }
        dismissCoordinator?.onBlockedDismiss = {
            dismissKeyboard()
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

// MARK: - Sign-In Success View

private struct SignInSuccessView: View {
    @Environment(AppPreferences.self) private var appPreferences

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    var body: some View {
        VStack(spacing: UIConstants.Spacing.large) {
            Spacer(minLength: 0)

            Text(AppLocalization.string("Welcome back", locale: locale))
                .font(.system(size: 46, weight: .heavy))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, UIConstants.Spacing.large)
        .frame(maxWidth: 440)
        .transition(.opacity)
    }
}

#if DEBUG
private struct AuthLayoutDebugFrameProbe: UIViewRepresentable {
    let label: String

    func makeUIView(context: Context) -> AuthLayoutDebugFrameProbeView {
        AuthLayoutDebugFrameProbeView(label: label)
    }

    func updateUIView(_ uiView: AuthLayoutDebugFrameProbeView, context: Context) {
        uiView.label = label
        uiView.setNeedsLayout()
    }
}

private final class AuthLayoutDebugFrameProbeView: UIView {
    var label: String
    private var lastSummary: String?

    init(label: String) {
        self.label = label
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        logFrame()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        logFrame()
    }

    private func logFrame() {
        let globalFrame: CGRect
        if let window {
            globalFrame = convert(bounds, to: window)
        } else {
            globalFrame = frame
        }

        let summary = [
            "frame.\(label)",
            "global=\(format(globalFrame))",
            "bounds=\(format(bounds))",
            "super=\(format(superview?.bounds ?? .zero))",
            "window=\(format(window?.bounds ?? .zero))"
        ].joined(separator: " ")

        guard summary != lastSummary else { return }
        lastSummary = summary
        authLayoutDebugLog(summary)
    }

    private func format(_ frame: CGRect) -> String {
        "x=\(format(frame.minX)),y=\(format(frame.minY)),w=\(format(frame.width)),h=\(format(frame.height))"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }
}

private extension View {
    func authLayoutDebugFrame(_ label: String) -> some View {
        background {
            AuthLayoutDebugFrameProbe(label: label)
                .allowsHitTesting(false)
        }
    }
}
#endif

// MARK: - Email Verification Success View

private struct EmailVerificationSuccessView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let user: AuthUserSnapshot
    let onContinue: @MainActor @Sendable () -> Void

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    var body: some View {
        VStack(spacing: UIConstants.Spacing.large) {
            Spacer(minLength: 0)

            VStack(spacing: UIConstants.Spacing.small) {
                Text(AppLocalization.string("Email verified", locale: locale))
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(AppLocalization.string("You're all set.", locale: locale))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, UIConstants.Spacing.large)
        .frame(maxWidth: 440)
        .transition(.opacity)
        .task(id: user.uid) {
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            onContinue()
        }
    }
}

// MARK: - Email Verification Required View

private struct EmailVerificationRequiredView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let user: AuthUserSnapshot
    let onResend: @MainActor @Sendable () async throws -> Void
    let onReload: @MainActor @Sendable () async throws -> Void
    let onCancel: @MainActor @Sendable () async throws -> Void
    let onResendSuccess: @MainActor @Sendable () -> Void
    let onError: @MainActor @Sendable (Error) -> Void

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    var body: some View {
        VStack(spacing: UIConstants.Spacing.large) {
            Spacer(minLength: 0)

            Image(systemName: "envelope.badge")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(themeManager.accentColor.color)

            VStack(spacing: UIConstants.Spacing.small) {
                Text(AppLocalization.string("Check your email", locale: locale))
                    .font(.title.weight(.bold))

                if let email = user.email {
                    Text(email)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            .multilineTextAlignment(.center)

            VStack(spacing: UIConstants.Spacing.medium) {
                ProgressActivityDots(color: themeManager.accentColor.color)
                .frame(maxWidth: .infinity)
                .frame(height: UIConstants.Size.buttonHeight)

                AuthAsyncButton(
                    title: AppLocalization.string("Resend Email", locale: locale),
                    icon: "arrow.clockwise",
                    tint: Color.primary.opacity(0.08),
                    foreground: .primary
                ) {
                    try await onResend()
                    onResendSuccess()
                } onError: { error in
                    onError(error)
                }

                AuthAsyncButton(
                    title: AppLocalization.string("Cancel", locale: locale),
                    icon: "xmark",
                    tint: Color.primary.opacity(0.08),
                    foreground: .secondary
                ) {
                    try await onCancel()
                } onError: { error in
                    onError(error)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, UIConstants.Spacing.large)
        .frame(maxWidth: 440)
        .task(id: user.uid) {
            await pollVerificationStatus()
        }
    }

    private func pollVerificationStatus() async {
        while !Task.isCancelled {
            do {
                try await onReload()
            } catch {
                // Polling should stay quiet; the explicit resend action still reports errors.
            }

            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthManager.shared)
        .environment(AppPreferences.shared)
        .environment(OnboardingStateStore.shared)
        .environment(ThemeManager.shared)
}

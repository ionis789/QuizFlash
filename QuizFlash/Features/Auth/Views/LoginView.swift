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

// MARK: - Login View

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(OnboardingStateStore.self) private var onboardingStateStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var email = ""
    @State private var password = ""
    @State private var showsCredentialForm = false
    @State private var activeSheet: AuthSheet?
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var presentingViewController: UIViewController?

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    var body: some View {
        ZStack {
            themeManager.screenBackground
                .ignoresSafeArea()

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
            case .signInSucceeded(let user):
                SignInSuccessView(
                    user: user,
                    onContinue: {
                        authManager.completeSignInSuccess()
                    }
                )
            case .checking:
                ProgressActivityDots(color: themeManager.accentColor.color)
            case .signedOut, .signedIn:
                loginForm
            }
        }
        .animation(.easeInOut(duration: 0.32), value: authManager.sessionState)
        .background {
            AuthPresentingViewControllerReader { controller in
                presentingViewController = controller
            }
            .frame(width: 0, height: 0)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .createAccount:
                CreateAccountView(onError: presentError)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.background)
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
                .presentationDetents([.height(300), .medium])
                .presentationBackground(.background)
            }
        }
        .alert(
            alertTitle,
            isPresented: $showAlert
        ) {
            Button(AppLocalization.string("Done", locale: locale), role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var loginForm: some View {
        ZStack {
            if showsCredentialForm {
                credentialForm
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                authLanding
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: showsCredentialForm)
    }

    private var authLanding: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: proxy.size.height * 0.26)

                AuthWalkthroughText(
                    phrases: walkthroughPhrases,
                    symbolColor: themeManager.accentColor.color,
                    reduceMotion: reduceMotion
                )
                .padding(.horizontal, UIConstants.Spacing.extraLarge)

                Spacer(minLength: UIConstants.Spacing.large)

                VStack(spacing: UIConstants.Spacing.medium) {
                    AuthLandingAsyncButton(
                        title: AppLocalization.string("Continue with Apple", locale: locale),
                        systemImage: "applelogo",
                        style: .light
                    ) {
                        try await authManager.signInWithApple()
                    } onError: { error in
                        presentError(error)
                    }

                    AuthLandingAsyncButton(
                        title: AppLocalization.string("Continue with Google", locale: locale),
                        textIcon: "G",
                        style: .dark
                    ) {
                        try await authManager.signInWithGoogle(
                            presentingViewController: presentingViewController
                        )
                    } onError: { error in
                        presentError(error)
                    }

                    AuthLandingButton(
                        title: AppLocalization.string("Log in or sign up", locale: locale),
                        style: .dark
                    ) {
                        showsCredentialForm = true
                    }
                }
                .padding(.horizontal, UIConstants.Spacing.large)
                .padding(.top, UIConstants.Spacing.large)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, UIConstants.Spacing.extraLarge))
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
                .background(alignment: .bottom) {
                    UnevenRoundedRectangle(
                        cornerRadii: RectangleCornerRadii(
                            topLeading: UIConstants.Radius.maximum,
                            topTrailing: UIConstants.Radius.maximum
                        ),
                        style: .continuous
                    )
                    .fill(Color.white.opacity(0.12))
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
        }
    }

    private var credentialForm: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                Button {
                    showsCredentialForm = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: UIConstants.Size.navigationChromeIcon, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: UIConstants.Size.buttonHeight, height: UIConstants.Size.buttonHeight)
                        .duoControlSurface(cornerRadius: UIConstants.Size.buttonHeight / 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.string("Back", locale: locale))
                .padding(.bottom, UIConstants.Spacing.small)

                Spacer(minLength: UIConstants.Spacing.huge)

                Text(AppLocalization.string("Log in or sign up", locale: locale))
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .padding(.bottom, UIConstants.Spacing.large)

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

                Button {
                    activeSheet = .forgotPassword
                } label: {
                    Text(AppLocalization.string("Forgot Password?", locale: locale))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .buttonStyle(.plain)

                AuthAsyncButton(
                    title: AppLocalization.string("Sign In", locale: locale),
                    icon: nil,
                    tint: themeManager.accentColor.color,
                    isEnabled: canSignIn
                ) {
                    try await authManager.signIn(email: email, password: password)
                } onError: { error in
                    presentError(error)
                }
                .padding(.top, UIConstants.Spacing.small)

                HStack(spacing: UIConstants.Spacing.small) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.10))
                        .frame(height: 1)

                    Text(AppLocalization.string("or", locale: locale))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Rectangle()
                        .fill(Color.primary.opacity(0.10))
                        .frame(height: 1)
                }
                .padding(.vertical, UIConstants.Spacing.small)

                AuthAsyncButton(
                    title: AppLocalization.string("Continue with Google", locale: locale),
                    icon: "globe",
                    tint: Color.primary.opacity(0.08),
                    foreground: .primary
                ) {
                    try await authManager.signInWithGoogle(
                        presentingViewController: presentingViewController
                    )
                } onError: { error in
                    presentError(error)
                }

                HStack(spacing: UIConstants.Spacing.small) {
                    Text(AppLocalization.string("Don't have an account?", locale: locale))
                        .foregroundStyle(.secondary)

                    Button {
                        activeSheet = .createAccount
                    } label: {
                        Text(AppLocalization.string("Sign Up", locale: locale))
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(themeManager.accentColor.color)
                }
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(.top, UIConstants.Spacing.small)

                Button {
                    onboardingStateStore.presentPreview()
                } label: {
                    Text(AppLocalization.string("Preview Onboarding", locale: locale))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.accentColor.color)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.huge)
            .padding(.bottom, UIConstants.Spacing.huge * 3)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.never)
        .dismissKeyboardOnBackgroundTap()
    }

    private var canSignIn: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
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
}

// MARK: - Auth Walkthrough Text

private struct AuthWalkthroughText: View {
    let phrases: [String]
    let symbolColor: Color
    let reduceMotion: Bool

    @State private var intros: [AuthIntro] = []
    @State private var activeIntro: AuthIntro?

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
                            }
                            .offset(x: -activeIntro.symbolOffset)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 86)
        .clipped()
        .task(id: phrases.joined(separator: "|")) {
            configureIntros()
            guard activeIntro == nil else { return }

            activeIntro = intros.first
            guard intros.count > 1, !reduceMotion else { return }

            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            animate(0)
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

    private func animate(_ index: Int, loop: Bool = true) {
        if intros.indices.contains(index + 1) {
            activeIntro?.text = intros[index].text
            activeIntro?.textColor = intros[index].textColor

            withAnimation(.snappy(duration: 1), completionCriteria: .removed) {
                activeIntro?.textOffset = -(textSize(intros[index].text) + 20)
                activeIntro?.symbolOffset = -(textSize(intros[index].text) + 20) / 2
            } completion: {
                withAnimation(.snappy(duration: 0.8), completionCriteria: .logicallyComplete) {
                    activeIntro?.textOffset = 0
                    activeIntro?.symbolOffset = 0
                    activeIntro?.symbolColor = intros[index + 1].symbolColor
                    activeIntro?.backgroundColor = intros[index + 1].backgroundColor
                } completion: {
                    animate(index + 1, loop: loop)
                }
            }
        } else if loop {
            animate(0, loop: loop)
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

            Task { @MainActor in
                isLoading = true
                defer { isLoading = false }

                do {
                    try await action()
                } catch {
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

// MARK: - Auth Sheet

private enum AuthSheet: Identifiable {
    case createAccount
    case forgotPassword

    var id: String {
        switch self {
        case .createAccount: "createAccount"
        case .forgotPassword: "forgotPassword"
        }
    }
}

// MARK: - Create Account View

private struct CreateAccountView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(OnboardingStateStore.self) private var onboardingStateStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""

    let onError: @MainActor @Sendable (Error) -> Void

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                Text(AppLocalization.string("Create Account", locale: locale))
                    .font(.title.weight(.bold))

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
                    tint: themeManager.accentColor.color,
                    isEnabled: canCreateAccount
                ) {
                    let user = try await authManager.createAccount(
                        email: email,
                        password: password,
                        confirmation: passwordConfirmation
                    )
                    onboardingStateStore.markPendingForNewAccount(uid: user.uid)
                    if !user.requiresEmailVerification {
                        onboardingStateStore.presentRequiredIfNeeded(for: user)
                    }
                    dismiss()
                } onError: { error in
                    onError(error)
                }
                .padding(.top, UIConstants.Spacing.small)
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.extraLarge)
            .padding(.bottom, UIConstants.Spacing.huge * 3)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.never)
        .dismissKeyboardOnBackgroundTap()
    }

    private var canCreateAccount: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && password == passwordConfirmation
    }
}

// MARK: - Forgot Password View

private struct ForgotPasswordView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""

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

                Text(AppLocalization.string("We'll send a reset link.", locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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
                    dismiss()
                    try? await Task.sleep(for: .milliseconds(250))
                    onSuccess()
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
    }
}

// MARK: - Sign-In Success View

private struct SignInSuccessView: View {
    @Environment(AppPreferences.self) private var appPreferences

    let user: AuthUserSnapshot
    let onContinue: @MainActor @Sendable () -> Void

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
        .task(id: user.uid) {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            onContinue()
        }
    }
}

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

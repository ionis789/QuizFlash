//
//  LoginView.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.12.2025.
//

import SwiftUI
import GoogleSignIn
import UIKit

// MARK: - Login View

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    @State private var email = ""
    @State private var password = ""
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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                Spacer(minLength: UIConstants.Spacing.huge)

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 46, weight: .heavy))
                        .foregroundStyle(themeManager.accentColor.color)

                    Text("QuizFlash")
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(.primary)

                    Text(AppLocalization.string("Welcome back", locale: locale))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
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
                    icon: "chevron.compact.right",
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
        return error.domain == kGIDSignInErrorDomain
            && error.code == GIDSignInError.canceled.rawValue
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
                    try await authManager.createAccount(
                        email: email,
                        password: password,
                        confirmation: passwordConfirmation
                    )
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
                HStack(spacing: UIConstants.Spacing.medium) {
                    Text(AppLocalization.string("Checking verification", locale: locale))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ProgressActivityDots(color: themeManager.accentColor.color)
                }
                .frame(maxWidth: .infinity)
                .frame(height: UIConstants.Size.buttonHeight)
                .background(Color.primary.opacity(0.06), in: Capsule())

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
                    foreground: .primary
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
        .environment(ThemeManager.shared)
}

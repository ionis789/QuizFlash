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
    @Environment(OnboardingStateStore.self) private var onboardingStateStore
    @Environment(ThemeManager.self) private var themeManager

    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var authStep: AuthStep = .landing
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
            Color.black
                .ignoresSafeArea()

            switch authStep {
            case .landing:
                authLanding
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .email:
                authEmailStep
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .password:
                authPasswordStep
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .createAccount:
                authCreateAccountStep
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: authStep)
        .dismissKeyboardOnBackgroundTap()
    }

    private var authLanding: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: proxy.size.height * 0.24)

                LoginMotivationText(phrases: loginMotivationPhrases)
                    .frame(maxWidth: 620)
                    .padding(.horizontal, UIConstants.Spacing.large)

                Spacer(minLength: UIConstants.Spacing.large)

                VStack(spacing: UIConstants.Spacing.medium) {
                    AuthFlowAsyncButton(
                        title: AppLocalization.string("Continue with Google", locale: locale),
                        icon: .google,
                        style: .secondary
                    ) {
                        try await authManager.signInWithGoogle(
                            presentingViewController: presentingViewController
                        )
                    } onError: { error in
                        presentError(error)
                    }

                    AuthFlowButton(
                        title: AppLocalization.string("Log in or sign up", locale: locale),
                        style: .primary
                    ) {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            authStep = .email
                        }
                    }

                    Button {
                        onboardingStateStore.presentPreview()
                    } label: {
                        Text(AppLocalization.string("Preview Onboarding", locale: locale))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.68))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, UIConstants.Spacing.small)
                }
                .padding(.horizontal, UIConstants.Spacing.large)
                .padding(.top, UIConstants.Spacing.large)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, UIConstants.Spacing.extraLarge))
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .background(alignment: .bottom) {
                    UnevenRoundedRectangle(
                        cornerRadii: RectangleCornerRadii(
                            topLeading: 44,
                            topTrailing: 44
                        ),
                        style: .continuous
                    )
                    .fill(Color.white.opacity(0.12))
                    .ignoresSafeArea(edges: .bottom)
                }
            }
        }
    }

    private var authEmailStep: some View {
        AuthFlowSurface {
            authTopBar(
                showsBack: false,
                onBack: {},
                onClose: closeAuthFlow
            )

            Spacer(minLength: UIConstants.Spacing.extraLarge)

            AuthFlowMark()

            Text(AppLocalization.string("Log in or sign up", locale: locale))
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.82)

            Text(AppLocalization.string("Build decks. Review faster.", locale: locale))
                .font(.title3)
                .foregroundStyle(.white.opacity(0.66))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, -UIConstants.Spacing.small)

            VStack(spacing: UIConstants.Spacing.standard) {
                AuthFlowTextField(
                    title: AppLocalization.string("Email", locale: locale),
                    keyboardType: .emailAddress,
                    textContentType: .username,
                    text: $email
                )

                AuthFlowButton(
                    title: AppLocalization.string("Continue", locale: locale),
                    style: .primary,
                    isEnabled: canContinueFromEmail
                ) {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        authStep = .password
                    }
                }

                authDivider

                AuthFlowAsyncButton(
                    title: AppLocalization.string("Continue with Google", locale: locale),
                    icon: .google,
                    style: .outline
                ) {
                    try await authManager.signInWithGoogle(
                        presentingViewController: presentingViewController
                    )
                } onError: { error in
                    presentError(error)
                }

                AuthFlowButton(
                    title: AppLocalization.string("Create Account", locale: locale),
                    style: .outline
                ) {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        authStep = .createAccount
                    }
                }
            }
            .padding(.top, UIConstants.Spacing.huge)

            Spacer(minLength: UIConstants.Spacing.huge)
        }
    }

    private var authPasswordStep: some View {
        AuthFlowSurface {
            authTopBar(
                showsBack: true,
                onBack: {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        authStep = .email
                    }
                },
                onClose: closeAuthFlow
            )

            Spacer(minLength: UIConstants.Spacing.extraLarge)

            AuthFlowMark()

            Text(AppLocalization.string("Enter your password", locale: locale))
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.82)

            VStack(spacing: UIConstants.Spacing.medium) {
                AuthFlowStaticField(
                    title: AppLocalization.string("Email", locale: locale),
                    value: email.trimmingCharacters(in: .whitespacesAndNewlines)
                )

                AuthFlowPasswordField(
                    title: AppLocalization.string("Password", locale: locale),
                    text: $password
                )

                AuthFlowAsyncButton(
                    title: AppLocalization.string("Continue", locale: locale),
                    icon: nil,
                    style: .primary,
                    isEnabled: canSignIn
                ) {
                    try await authManager.signIn(email: email, password: password)
                } onError: { error in
                    presentError(error)
                }
                .padding(.top, UIConstants.Spacing.standard)

                Button {
                    activeSheet = .forgotPassword
                } label: {
                    Text(AppLocalization.string("Forgot Password?", locale: locale))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.top, UIConstants.Spacing.small)
            }
            .padding(.top, UIConstants.Spacing.huge)

            Spacer(minLength: UIConstants.Spacing.huge)
        }
    }

    private var authCreateAccountStep: some View {
        AuthFlowSurface {
            authTopBar(
                showsBack: true,
                onBack: {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        authStep = .email
                    }
                },
                onClose: closeAuthFlow
            )

            Spacer(minLength: UIConstants.Spacing.extraLarge)

            AuthFlowMark()

            Text(AppLocalization.string("Create Account", locale: locale))
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.82)

            VStack(spacing: UIConstants.Spacing.medium) {
                AuthFlowTextField(
                    title: AppLocalization.string("Email", locale: locale),
                    keyboardType: .emailAddress,
                    textContentType: .username,
                    text: $email
                )

                AuthFlowPasswordField(
                    title: AppLocalization.string("Password", locale: locale),
                    text: $password
                )

                AuthFlowPasswordField(
                    title: AppLocalization.string("Confirm Password", locale: locale),
                    text: $passwordConfirmation
                )

                AuthFlowAsyncButton(
                    title: AppLocalization.string("Continue", locale: locale),
                    icon: nil,
                    style: .primary,
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
                } onError: { error in
                    presentError(error)
                }
                .padding(.top, UIConstants.Spacing.standard)
            }
            .padding(.top, UIConstants.Spacing.huge)

            Spacer(minLength: UIConstants.Spacing.huge)
        }
    }

    private var authDivider: some View {
        HStack(spacing: UIConstants.Spacing.large) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)

            Text(AppLocalization.string("or", locale: locale).uppercased())
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
        }
        .padding(.vertical, UIConstants.Spacing.small)
    }

    private var canSignIn: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    private var canContinueFromEmail: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canCreateAccount: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && password == passwordConfirmation
    }

    private var loginMotivationPhrases: [String] {
        [
            AppLocalization.string("Let's learn", locale: locale),
            AppLocalization.string("Stay productive", locale: locale),
            AppLocalization.string("Study smarter", locale: locale),
            AppLocalization.string("Keep your focus", locale: locale)
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
        return error.domain == kGIDSignInErrorDomain
            && error.code == GIDSignInError.canceled.rawValue
    }

    private func closeAuthFlow() {
        withAnimation(.easeInOut(duration: 0.28)) {
            authStep = .landing
            password = ""
            passwordConfirmation = ""
        }
    }

    @ViewBuilder
    private func authTopBar(
        showsBack: Bool,
        onBack: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) -> some View {
        HStack {
            if showsBack {
                AuthFlowCircleButton(
                    icon: "chevron.left",
                    title: AppLocalization.string("Back", locale: locale),
                    action: onBack
                )
            } else {
                Color.clear
                    .frame(width: 56, height: 56)
            }

            Spacer()

            AuthFlowCircleButton(
                icon: "xmark",
                title: AppLocalization.string("Close", locale: locale),
                action: onClose
            )
        }
    }
}

// MARK: - Auth Step

private enum AuthStep: Equatable {
    case landing
    case email
    case password
    case createAccount
}

// MARK: - Login Motivation Text

private struct LoginMotivationText: View {
    let phrases: [String]

    @State private var currentIndex = 0

    var body: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            ZStack {
                ForEach(Array(phrases.enumerated()), id: \.offset) { index, phrase in
                    if index == visibleIndex {
                        Text(phrase)
                            .font(.system(size: 46, weight: .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                            .multilineTextAlignment(.center)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                )
                            )
                    }
                }
            }

            Circle()
                .fill(.white)
                .frame(width: 52, height: 52)
                .scaleEffect(visibleIndex.isMultiple(of: 2) ? 1 : 0.82)
                .animation(.easeInOut(duration: 0.42), value: visibleIndex)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 120, alignment: .center)
        .clipped()
        .task(id: phrases.joined(separator: "|")) {
            currentIndex = 0
            guard phrases.count > 1 else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1800))
                guard !Task.isCancelled else { return }

                withAnimation(.easeInOut(duration: 0.42)) {
                    currentIndex = (currentIndex + 1) % phrases.count
                }
            }
        }
    }

    private var visibleIndex: Int {
        guard !phrases.isEmpty else { return 0 }
        return min(currentIndex, phrases.count - 1)
    }
}

// MARK: - Auth Flow Surface

private struct AuthFlowSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: UIConstants.Spacing.large) {
                    content
                }
                .padding(.horizontal, UIConstants.Spacing.large)
                .padding(.top, max(proxy.safeAreaInsets.top, UIConstants.Spacing.large))
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, UIConstants.Spacing.huge))
                .frame(maxWidth: 520)
                .frame(minHeight: proxy.size.height, alignment: .top)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background {
                RoundedRectangle(cornerRadius: 52, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .padding(.top, proxy.safeAreaInsets.top + UIConstants.Spacing.small)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

// MARK: - Auth Flow Mark

private struct AuthFlowMark: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.32), lineWidth: 2)
                .frame(width: 62, height: 62)

            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Auth Flow Controls

private enum AuthFlowButtonStyle {
    case primary
    case secondary
    case outline

    var background: Color {
        switch self {
        case .primary:
            .white
        case .secondary:
            .white.opacity(0.10)
        case .outline:
            .clear
        }
    }

    var foreground: Color {
        switch self {
        case .primary:
            .black
        case .secondary, .outline:
            .white
        }
    }

    var border: Color {
        switch self {
        case .primary:
            .clear
        case .secondary:
            .white.opacity(0.08)
        case .outline:
            .white.opacity(0.22)
        }
    }
}

private enum AuthFlowProviderIcon {
    case google
}

private struct AuthFlowButton: View {
    let title: String
    var icon: AuthFlowProviderIcon?
    var style: AuthFlowButtonStyle
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AuthFlowButtonLabel(title: title, icon: icon, style: style, isLoading: false)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.44)
    }
}

private struct AuthFlowAsyncButton: View {
    let title: String
    var icon: AuthFlowProviderIcon?
    var style: AuthFlowButtonStyle
    var isEnabled = true
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
            AuthFlowButtonLabel(title: title, icon: icon, style: style, isLoading: isLoading)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.44)
        .animation(.easeInOut(duration: UIConstants.Animation.instant), value: isLoading)
        .animation(.easeInOut(duration: UIConstants.Animation.instant), value: isEnabled)
    }
}

private struct AuthFlowButtonLabel: View {
    let title: String
    var icon: AuthFlowProviderIcon?
    var style: AuthFlowButtonStyle
    var isLoading: Bool

    var body: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            if let icon {
                authIcon(icon)
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
        .frame(height: 62)
        .background(style.background, in: Capsule())
        .overlay {
            Capsule()
                .stroke(style.border, lineWidth: 1.5)
        }
    }

    @ViewBuilder
    private func authIcon(_ icon: AuthFlowProviderIcon) -> some View {
        switch icon {
        case .google:
            Text("G")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
        }
    }
}

private struct AuthFlowCircleButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.10), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct AuthFlowTextField: View {
    let title: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(keyboardType)
            .textContentType(textContentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.title3)
            .foregroundStyle(.white)
            .padding(.horizontal, UIConstants.Spacing.standard)
            .frame(height: 66)
            .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.26), lineWidth: 1.5)
            }
    }
}

private struct AuthFlowStaticField: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.tiny) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.58))

            Text(value)
                .font(.title3)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, UIConstants.Spacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 66)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
        }
    }
}

private struct AuthFlowPasswordField: View {
    @Environment(AppPreferences.self) private var appPreferences

    let title: String
    @Binding var text: String

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            Group {
                if isVisible {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.title3)
            .foregroundStyle(.white)

            Button {
                withAnimation(.easeInOut(duration: UIConstants.Animation.instant)) {
                    isVisible.toggle()
                }
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(passwordVisibilityTitle)
        }
        .padding(.leading, UIConstants.Spacing.standard)
        .padding(.trailing, UIConstants.Spacing.small)
        .frame(height: 66)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(text.isEmpty ? 0.26 : 0.18), lineWidth: 1.5)
        }
    }

    private var passwordVisibilityTitle: String {
        AppLocalization.string(isVisible ? "Hide" : "Show", locale: appPreferences.resolvedLocale)
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

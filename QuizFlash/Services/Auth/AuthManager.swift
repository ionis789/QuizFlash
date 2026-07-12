//
//  AuthManager.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.12.2025.
//

import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import Foundation
import GoogleSignIn
import Observation
import UIKit

#if DEBUG
private func authSessionFlowDebugLog(_ message: String) {
    print("AUTH_SESSION_FLOW \(String(format: "%.3f", Date().timeIntervalSince1970)) \(message)")
}
#endif

// MARK: - Auth Flow Diagnostics

/// Emits one ordered, privacy-safe timeline for the complete external-auth handoff.
///
/// Keep this active in DEBUG until the runtime tester confirms the login transition. Every line
/// starts with `QF_AUTH_TRACE`, so the complete attempt can be copied from Xcode's console with a
/// single filter.
@MainActor
enum AuthFlowDebugTrace {
#if DEBUG
    private static let maximumBufferedEvents = 80
    private static var sequence = 0
    private static var attemptID = "launch"
    private static var bufferedEvents: [String] = []
#endif

    static func beginAttempt(
        provider: String,
        state: AuthSessionState
    ) -> String {
#if DEBUG
        attemptID = String(UUID().uuidString.prefix(8))
        sequence = 0
        bufferedEvents.removeAll(keepingCapacity: true)
        record(
            "attempt.begin",
            layer: "auth-manager",
            details: [
                "provider": provider,
                "state": state.debugName,
                "windows": windowSnapshot()
            ]
        )
#endif
        return currentAttemptID
    }

    static var currentAttemptID: String {
#if DEBUG
        attemptID
#else
        "release"
#endif
    }

    static func record(
        _ event: String,
        layer: String,
        details: [String: String] = [:]
    ) {
#if DEBUG
        sequence += 1
        let detail = details
            .map { key, value in "\(sanitize(key))=\(sanitize(value))" }
            .sorted()
            .joined(separator: " ")
        let suffix = detail.isEmpty ? "" : " \(detail)"
        let line = "QF_AUTH_TRACE attempt=\(attemptID) seq=\(sequence) "
            + "time=\(String(format: "%.3f", Date().timeIntervalSince1970)) "
            + "main=\(Thread.isMainThread) layer=\(sanitize(layer)) event=\(sanitize(event))\(suffix)"
        bufferedEvents.append(line)
        if bufferedEvents.count > maximumBufferedEvents {
            bufferedEvents.removeFirst(bufferedEvents.count - maximumBufferedEvents)
        }
        print(line)
#endif
    }

    static func recordWindowCheckpoint(
        _ event: String,
        layer: String,
        state: AuthSessionState
    ) {
#if DEBUG
        record(
            event,
            layer: layer,
            details: [
                "state": state.debugName,
                "windows": windowSnapshot()
            ]
        )
#endif
    }

#if DEBUG
    private static func windowSnapshot() -> String {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { $0.activationState.sortPriority < $1.activationState.sortPriority }

        guard !scenes.isEmpty else { return "none" }

        return scenes.enumerated().map { sceneIndex, scene in
            let windows = scene.windows.enumerated().map { windowIndex, window in
                let rootName = window.rootViewController.map { shortTypeName($0) } ?? "nil"
                let presented = window.rootViewController.map(presentedChain) ?? "none"
                return "w\(windowIndex){key:\(window.isKeyWindow),hidden:\(window.isHidden),"
                    + "level:\(Int(window.windowLevel.rawValue)),root:\(rootName),presented:\(presented)}"
            }.joined(separator: ",")
            return "s\(sceneIndex){state:\(scene.activationState.debugName),\(windows)}"
        }.joined(separator: ";")
    }

    private static func presentedChain(from root: UIViewController) -> String {
        var names: [String] = []
        var current = root.presentedViewController
        while let controller = current, names.count < 8 {
            names.append(shortTypeName(controller))
            current = controller.presentedViewController
        }
        return names.isEmpty ? "none" : names.joined(separator: ">")
    }

    private static func shortTypeName(_ value: Any) -> String {
        String(describing: type(of: value)).replacingOccurrences(of: " ", with: "_")
    }

    private static func sanitize(_ value: String) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: " ", with: "_")
        return String(singleLine.prefix(700))
    }
#endif
}

extension AuthSessionState {
    var debugName: String {
        switch self {
        case .checking: "checking"
        case .signedOut: "signedOut"
        case .signedIn: "signedIn"
        case .emailVerificationRequired: "emailVerificationRequired"
        case .emailVerificationSucceeded: "emailVerificationSucceeded"
        }
    }
}

private extension UIScene.ActivationState {
    var debugName: String {
        switch self {
        case .foregroundActive: "foregroundActive"
        case .foregroundInactive: "foregroundInactive"
        case .background: "background"
        case .unattached: "unattached"
        @unknown default: "unknown"
        }
    }
}

// MARK: - Auth User Snapshot

/// Lightweight, UI-safe snapshot of the current Firebase user.
struct AuthUserSnapshot: Equatable, Sendable {
    let uid: String
    let email: String?
    let displayName: String?
    let photoURLString: String?
    let providers: [String]
    let isEmailVerified: Bool

    var requiresEmailVerification: Bool {
        let providerSet = Set(providers)
        return providerSet.contains(AuthProviderID.password.rawValue)
            && providerSet.isDisjoint(with: [
                AuthProviderID.google.rawValue,
                AuthProviderID.apple.rawValue
            ])
            && !isEmailVerified
    }
}

// MARK: - Auth Session State

/// Root authentication gate state for the app.
enum AuthSessionState: Equatable, Sendable {
    case checking
    case signedOut
    case signedIn(AuthUserSnapshot)
    case emailVerificationRequired(AuthUserSnapshot)
    case emailVerificationSucceeded(AuthUserSnapshot)
}

// MARK: - Auth Provider ID

enum AuthProviderID: String, Sendable {
    case password = "password"
    case google = "google.com"
    case apple = "apple.com"
}

// MARK: - Auth Reauthentication Request

enum AuthReauthenticationRequest {
    case password(String)
    case google(UIViewController)
    case apple
}

// MARK: - Auth Manager Error

enum AuthManagerError: LocalizedError, Equatable {
    case missingCurrentUser
    case missingPresenter
    case passwordConfirmationMismatch
    case missingGoogleClientID
    case firebaseSignInTimedOut
    case missingCredential
    case missingAppleIdentityToken
    case invalidAppleIdentityToken

    var errorDescription: String? {
        switch self {
        case .missingCurrentUser:
            "No signed-in user was found."
        case .missingPresenter:
            "The sign-in window is not ready yet."
        case .passwordConfirmationMismatch:
            "Passwords do not match."
        case .missingGoogleClientID:
            "Google Sign-In is not configured."
        case .firebaseSignInTimedOut:
            "Firebase did not finish sign-in. Please try again."
        case .missingCredential:
            "The sign-in credential could not be created."
        case .missingAppleIdentityToken:
            "Apple did not return an identity token."
        case .invalidAppleIdentityToken:
            "Apple returned an invalid identity token."
        }
    }
}

// MARK: - Auth Providing

@MainActor
protocol AuthProviding: AnyObject {
    var currentUser: AuthUserSnapshot? { get }

    func observeAuthState(
        _ handler: @escaping @MainActor (AuthUserSnapshot?) -> Void
    ) -> @MainActor () -> Void

    func signIn(email: String, password: String) async throws -> AuthUserSnapshot
    func createAccount(email: String, password: String) async throws -> AuthUserSnapshot
    func updateDisplayName(_ displayName: String?) async throws -> AuthUserSnapshot
    func sendPasswordReset(email: String) async throws
    func sendEmailVerification() async throws
    func reloadCurrentUser() async throws -> AuthUserSnapshot?
    func signInWithGoogle(presentingViewController: UIViewController) async throws -> AuthUserSnapshot
    func signInWithApple() async throws -> AuthUserSnapshot
    func reauthenticate(with request: AuthReauthenticationRequest) async throws
    func signOut() async throws
    func deleteCurrentUser() async throws
}

// MARK: - AuthManager

/// Coordinates Firebase-backed authentication for QuizFlash.
@Observable
@MainActor
final class AuthManager {

    // MARK: - Shared Instance

    /// The app-wide authentication coordinator.
    static let shared = AuthManager()

    // MARK: - Dependencies

    @ObservationIgnored
    private let makeAuthProvider: @MainActor () -> AuthProviding

    @ObservationIgnored
    private var cachedAuthProvider: AuthProviding?

    // MARK: - State

    private(set) var sessionState: AuthSessionState = .checking

    var currentUser: AuthUserSnapshot? {
        switch sessionState {
        case .checking, .signedOut:
            nil
        case .signedIn(let user),
             .emailVerificationRequired(let user),
             .emailVerificationSucceeded(let user):
            user
        }
    }

    var isAuthenticated: Bool {
        if case .signedIn = sessionState {
            return true
        }
        return false
    }

    @ObservationIgnored
    private var removeAuthStateListener: (@MainActor () -> Void)?

    @ObservationIgnored
    private var externalSignInTask: Task<AuthUserSnapshot, Error>?

    @ObservationIgnored
    private var externalSignInID: UUID?

    // MARK: - Init

    convenience init() {
        self.init(makeAuthProvider: { FirebaseAuthClient() })
    }

    convenience init(authProvider: AuthProviding) {
        self.init(makeAuthProvider: { authProvider })
    }

    private init(makeAuthProvider: @escaping @MainActor () -> AuthProviding) {
        self.makeAuthProvider = makeAuthProvider
    }

    deinit {
        MainActor.assumeIsolated {
            removeAuthStateListener?()
            externalSignInTask?.cancel()
        }
    }

    // MARK: - Public

    /// Starts observing Firebase Auth state changes.
    func startListening() {
        guard removeAuthStateListener == nil else {
            AuthFlowDebugTrace.record(
                "listener.start.skipped",
                layer: "auth-manager",
                details: ["reason": "already-installed", "state": sessionState.debugName]
            )
            return
        }
        AuthFlowDebugTrace.record(
            "listener.start",
            layer: "auth-manager",
            details: ["previousState": sessionState.debugName]
        )
        sessionState = .checking
        let provider = authProvider
        removeAuthStateListener = provider.observeAuthState { [weak self] user in
            AuthFlowDebugTrace.record(
                "listener.delivered",
                layer: "auth-manager",
                details: ["user": BackendTraceStore.safeUID(user?.uid)]
            )
            self?.apply(user)
        }
        AuthFlowDebugTrace.record(
            "listener.installed",
            layer: "auth-manager",
            details: ["currentUser": BackendTraceStore.safeUID(provider.currentUser?.uid)]
        )
        apply(provider.currentUser)
    }

    func signIn(email: String, password: String) async throws {
#if DEBUG
        authSessionFlowDebugLog("email sign-in started")
#endif
        let user = try await authProvider.signIn(
            email: normalizedEmail(email),
            password: password
        )
#if DEBUG
        authSessionFlowDebugLog("email Firebase sign-in returned")
#endif
        applySignInSuccess(user)
    }

    @discardableResult
    func createAccount(
        email: String,
        password: String,
        confirmation: String
    ) async throws -> AuthUserSnapshot {
        let traceID = AuthFlowDebugTrace.beginAttempt(
            provider: "email-sign-up",
            state: sessionState
        )
        guard password == confirmation else {
            AuthFlowDebugTrace.record(
                "account-create.rejected",
                layer: "auth-manager",
                details: ["operation": traceID, "reason": "password-mismatch"]
            )
            throw AuthManagerError.passwordConfirmationMismatch
        }

        AuthFlowDebugTrace.record(
            "account-create.requested",
            layer: "auth-manager",
            details: ["operation": traceID]
        )

        do {
            let user = try await authProvider.createAccount(
                email: normalizedEmail(email),
                password: password
            )
            AuthFlowDebugTrace.record(
                "account-create.completed",
                layer: "auth-manager",
                details: [
                    "operation": traceID,
                    "user": BackendTraceStore.safeUID(user.uid)
                ]
            )
            apply(user)
            return user
        } catch {
            AuthFlowDebugTrace.record(
                "account-create.failed",
                layer: "auth-manager",
                details: authErrorTraceDetails(error, extra: ["operation": traceID])
            )
            throw error
        }
    }

    func updateDisplayName(_ displayName: String?) async throws {
        let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayName = trimmedDisplayName?.isEmpty == false ? trimmedDisplayName : nil
        let user = try await authProvider.updateDisplayName(normalizedDisplayName)
        apply(user)
    }

    func sendPasswordReset(email: String) async throws {
        try await authProvider.sendPasswordReset(email: normalizedEmail(email))
    }

    func resendEmailVerification() async throws {
        let traceID = AuthFlowDebugTrace.beginAttempt(
            provider: "email-resend",
            state: sessionState
        )
        AuthFlowDebugTrace.record(
            "verification-resend.requested",
            layer: "auth-manager",
            details: ["operation": traceID]
        )

        do {
            try await authProvider.sendEmailVerification()
            AuthFlowDebugTrace.record(
                "verification-resend.completed",
                layer: "auth-manager",
                details: ["operation": traceID]
            )
        } catch {
            AuthFlowDebugTrace.record(
                "verification-resend.failed",
                layer: "auth-manager",
                details: authErrorTraceDetails(error, extra: ["operation": traceID])
            )
            throw error
        }
    }

    func reloadEmailVerificationStatus() async throws {
        let user = try await authProvider.reloadCurrentUser()
        apply(user)
    }

    func completeEmailVerificationSuccess() {
        if case .emailVerificationSucceeded(let user) = sessionState {
            sessionState = .signedIn(user)
        }
    }

    func signInWithGoogle(presentingViewController: UIViewController?) async throws {
        guard let presentingViewController else {
            AuthFlowDebugTrace.record(
                "attempt.rejected",
                layer: "auth-manager",
                details: ["reason": "missing-presenter"]
            )
            throw AuthManagerError.missingPresenter
        }

        let traceID = AuthFlowDebugTrace.beginAttempt(provider: "google", state: sessionState)
        AuthFlowDebugTrace.record(
            "presenter.accepted",
            layer: "auth-manager",
            details: [
                "operation": traceID,
                "type": String(describing: type(of: presentingViewController)),
                "windowAttached": String(presentingViewController.viewIfLoaded?.window != nil)
            ]
        )
#if DEBUG
        authSessionFlowDebugLog("Google sign-in started")
#endif
        let provider = authProvider
        let operationID = UUID()
        let task = Task { @MainActor [weak self] in
            AuthFlowDebugTrace.record(
                "external-task.started",
                layer: "auth-manager",
                details: ["operation": traceID, "cancelled": String(Task.isCancelled)]
            )
            defer {
                AuthFlowDebugTrace.record(
                    "external-task.finished",
                    layer: "auth-manager",
                    details: [
                        "operation": traceID,
                        "state": self?.sessionState.debugName ?? "manager-released"
                    ]
                )
                if self?.externalSignInID == operationID {
                    self?.externalSignInTask = nil
                    self?.externalSignInID = nil
                }
            }

            let user = try await provider.signInWithGoogle(
                presentingViewController: presentingViewController
            )
#if DEBUG
            authSessionFlowDebugLog("Google Firebase sign-in returned")
#endif
            self?.applySignInSuccess(user)
            return user
        }
        externalSignInID = operationID
        externalSignInTask = task
        do {
            _ = try await task.value
            AuthFlowDebugTrace.record(
                "attempt.await.returned",
                layer: "auth-manager",
                details: ["operation": traceID, "state": sessionState.debugName]
            )
        } catch {
            AuthFlowDebugTrace.record(
                "attempt.await.failed",
                layer: "auth-manager",
                details: [
                    "operation": traceID,
                    "error": String(describing: type(of: error)),
                    "cancelled": String(error is CancellationError),
                    "state": sessionState.debugName
                ]
            )
            throw error
        }
    }

    func signInWithApple() async throws {
        let provider = authProvider
        let operationID = UUID()
        let task = Task { @MainActor [weak self] in
            defer {
                if self?.externalSignInID == operationID {
                    self?.externalSignInTask = nil
                    self?.externalSignInID = nil
                }
            }

            let user = try await provider.signInWithApple()
            self?.applySignInSuccess(user)
            return user
        }
        externalSignInID = operationID
        externalSignInTask = task
        _ = try await task.value
    }

    func logout() async throws {
#if DEBUG
        authSessionFlowDebugLog("logout started")
#endif
        externalSignInTask?.cancel()
        externalSignInTask = nil
        externalSignInID = nil
        try await authProvider.signOut()
        sessionState = .signedOut
#if DEBUG
        authSessionFlowDebugLog("logout published signedOut")
#endif
    }

    func deleteAccount(reauthentication: AuthReauthenticationRequest) async throws {
        try await authProvider.reauthenticate(with: reauthentication)
        try await authProvider.deleteCurrentUser()
        sessionState = .signedOut
    }

    // MARK: - Private

    private func apply(_ user: AuthUserSnapshot?) {
        let previousState = sessionState
#if DEBUG
        authSessionFlowDebugLog("applying auth listener user=\(user?.uid ?? "nil")")
#endif
        guard let user else {
            sessionState = .signedOut
            AuthFlowDebugTrace.record(
                "state.applied",
                layer: "auth-manager.listener",
                details: [
                    "from": previousState.debugName,
                    "to": sessionState.debugName,
                    "reason": "nil-user"
                ]
            )
            return
        }

        if user.requiresEmailVerification {
            sessionState = .emailVerificationRequired(user)
            AuthFlowDebugTrace.record(
                "state.applied",
                layer: "auth-manager.listener",
                details: [
                    "from": previousState.debugName,
                    "to": sessionState.debugName,
                    "reason": "email-verification-required",
                    "user": BackendTraceStore.safeUID(user.uid)
                ]
            )
            return
        }

        let wasWaitingForSameEmailUser: Bool = {
            switch sessionState {
            case .emailVerificationRequired(let previousUser),
                 .emailVerificationSucceeded(let previousUser):
                return previousUser.uid == user.uid
            default:
                return false
            }
        }()

        if wasWaitingForSameEmailUser {
            sessionState = .emailVerificationSucceeded(user)
        } else {
            sessionState = .signedIn(user)
        }
        AuthFlowDebugTrace.record(
            "state.applied",
            layer: "auth-manager.listener",
            details: [
                "from": previousState.debugName,
                "to": sessionState.debugName,
                "reason": wasWaitingForSameEmailUser ? "verified-email" : "authenticated-user",
                "user": BackendTraceStore.safeUID(user.uid)
            ]
        )
    }

    private func authErrorTraceDetails(
        _ error: Error,
        extra: [String: String] = [:]
    ) -> [String: String] {
        let nsError = error as NSError
        var details = extra
        details["errorType"] = String(describing: type(of: error))
        details["errorDomain"] = nsError.domain
        details["errorCode"] = String(nsError.code)
        return details
    }

    private func applySignInSuccess(_ user: AuthUserSnapshot) {
        let previousState = sessionState
        guard !user.requiresEmailVerification else {
            sessionState = .emailVerificationRequired(user)
            AuthFlowDebugTrace.record(
                "state.applied",
                layer: "auth-manager.operation",
                details: [
                    "from": previousState.debugName,
                    "to": sessionState.debugName,
                    "reason": "email-verification-required"
                ]
            )
            return
        }

        sessionState = .signedIn(user)
        AuthFlowDebugTrace.record(
            "state.applied",
            layer: "auth-manager.operation",
            details: [
                "from": previousState.debugName,
                "to": sessionState.debugName,
                "reason": "provider-returned",
                "user": BackendTraceStore.safeUID(user.uid)
            ]
        )
#if DEBUG
        authSessionFlowDebugLog("published signedIn")
#endif
    }

    private var authProvider: AuthProviding {
        if let cachedAuthProvider {
            return cachedAuthProvider
        }

        let provider = makeAuthProvider()
        cachedAuthProvider = provider
        return provider
    }

    private func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Firebase Auth Client

@MainActor
private final class FirebaseAuthClient: AuthProviding {
    private var appleCoordinator: AppleSignInCoordinator?
    private var firebaseSignInCoordinator: FirebaseCredentialSignInCoordinator?
    private var googleCoordinator: GoogleSignInCoordinator?

    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    var currentUser: AuthUserSnapshot? {
        Auth.auth().currentUser?.authSnapshot
    }

    func observeAuthState(
        _ handler: @escaping @MainActor (AuthUserSnapshot?) -> Void
    ) -> @MainActor () -> Void {
        AuthFlowDebugTrace.record(
            "listener.register",
            layer: "firebase-auth",
            details: ["currentUser": BackendTraceStore.safeUID(Auth.auth().currentUser?.uid)]
        )
        let handle = Auth.auth().addStateDidChangeListener { _, user in
#if DEBUG
            authSessionFlowDebugLog("Firebase listener callback user=\(user?.uid ?? "nil")")
#endif
            Task { @MainActor in
                AuthFlowDebugTrace.record(
                    "listener.callback",
                    layer: "firebase-auth",
                    details: [
                        "user": BackendTraceStore.safeUID(user?.uid),
                        "providerCount": String(user?.providerData.count ?? 0)
                    ]
                )
#if DEBUG
                authSessionFlowDebugLog("Firebase listener delivering user=\(user?.uid ?? "nil")")
#endif
                handler(user?.authSnapshot)
            }
        }

        return {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func signIn(email: String, password: String) async throws -> AuthUserSnapshot {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        return result.user.authSnapshot
    }

    func createAccount(email: String, password: String) async throws -> AuthUserSnapshot {
        AuthFlowDebugTrace.record(
            "create-user.request.start",
            layer: "firebase-email"
        )

        let result: AuthDataResult
        do {
            result = try await Auth.auth().createUser(withEmail: email, password: password)
        } catch {
            let nsError = error as NSError
            AuthFlowDebugTrace.record(
                "create-user.request.failed",
                layer: "firebase-email",
                details: [
                    "errorType": String(describing: type(of: error)),
                    "errorDomain": nsError.domain,
                    "errorCode": String(nsError.code)
                ]
            )
            throw error
        }

        AuthFlowDebugTrace.record(
            "create-user.request.success",
            layer: "firebase-email",
            details: ["user": BackendTraceStore.safeUID(result.user.uid)]
        )
        AuthFlowDebugTrace.record(
            "verification-email.request.start",
            layer: "firebase-email",
            details: [
                "phase": "initial",
                "user": BackendTraceStore.safeUID(result.user.uid)
            ]
        )

        do {
            try await result.user.sendEmailVerification()
        } catch {
            let nsError = error as NSError
            AuthFlowDebugTrace.record(
                "verification-email.request.failed",
                layer: "firebase-email",
                details: [
                    "phase": "initial",
                    "user": BackendTraceStore.safeUID(result.user.uid),
                    "errorType": String(describing: type(of: error)),
                    "errorDomain": nsError.domain,
                    "errorCode": String(nsError.code)
                ]
            )
            throw error
        }

        AuthFlowDebugTrace.record(
            "verification-email.request.success",
            layer: "firebase-email",
            details: [
                "phase": "initial",
                "user": BackendTraceStore.safeUID(result.user.uid)
            ]
        )
        return result.user.authSnapshot
    }

    func updateDisplayName(_ displayName: String?) async throws -> AuthUserSnapshot {
        guard let user = Auth.auth().currentUser else {
            throw AuthManagerError.missingCurrentUser
        }

        let request = user.createProfileChangeRequest()
        request.displayName = displayName
        try await request.commitChanges()
        try await user.reload()
        guard let updatedUser = Auth.auth().currentUser else {
            throw AuthManagerError.missingCurrentUser
        }
        return updatedUser.authSnapshot
    }

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func sendEmailVerification() async throws {
        guard let user = Auth.auth().currentUser else {
            AuthFlowDebugTrace.record(
                "verification-email.request.rejected",
                layer: "firebase-email",
                details: ["phase": "resend", "reason": "missing-current-user"]
            )
            throw AuthManagerError.missingCurrentUser
        }

        AuthFlowDebugTrace.record(
            "verification-email.request.start",
            layer: "firebase-email",
            details: [
                "phase": "resend",
                "user": BackendTraceStore.safeUID(user.uid)
            ]
        )

        do {
            try await user.sendEmailVerification()
        } catch {
            let nsError = error as NSError
            AuthFlowDebugTrace.record(
                "verification-email.request.failed",
                layer: "firebase-email",
                details: [
                    "phase": "resend",
                    "user": BackendTraceStore.safeUID(user.uid),
                    "errorType": String(describing: type(of: error)),
                    "errorDomain": nsError.domain,
                    "errorCode": String(nsError.code)
                ]
            )
            throw error
        }

        AuthFlowDebugTrace.record(
            "verification-email.request.success",
            layer: "firebase-email",
            details: [
                "phase": "resend",
                "user": BackendTraceStore.safeUID(user.uid)
            ]
        )
    }

    func reloadCurrentUser() async throws -> AuthUserSnapshot? {
        guard let user = Auth.auth().currentUser else { return nil }
        try await user.reload()
        return Auth.auth().currentUser?.authSnapshot
    }

    func signInWithGoogle(presentingViewController: UIViewController) async throws -> AuthUserSnapshot {
        let credential = try await googleCredential(presentingViewController: presentingViewController)
        return try await signInWithFirebaseCredential(credential)
    }

    func signInWithApple() async throws -> AuthUserSnapshot {
        let credential = try await appleCredential()
        return try await signInWithFirebaseCredential(credential)
    }

    func reauthenticate(with request: AuthReauthenticationRequest) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthManagerError.missingCurrentUser
        }

        switch request {
        case .password(let password):
            guard let email = user.email else {
                throw AuthManagerError.missingCredential
            }
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            try await user.reauthenticate(with: credential)
        case .google(let presentingViewController):
            let credential = try await googleCredential(presentingViewController: presentingViewController)
            try await user.reauthenticate(with: credential)
        case .apple:
            let credential = try await appleCredential()
            try await user.reauthenticate(with: credential)
        }
    }

    func signOut() async throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }

    func deleteCurrentUser() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthManagerError.missingCurrentUser
        }

        try await user.delete()
    }

    private func googleCredential(presentingViewController: UIViewController) async throws -> AuthCredential {
        AuthFlowDebugTrace.record(
            "credential.begin",
            layer: "google-provider",
            details: ["firebaseCurrentUser": BackendTraceStore.safeUID(Auth.auth().currentUser?.uid)]
        )
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            AuthFlowDebugTrace.record(
                "credential.rejected",
                layer: "google-provider",
                details: ["reason": "missing-client-id"]
            )
            throw AuthManagerError.missingGoogleClientID
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let coordinator = GoogleSignInCoordinator(
            presentingViewController: presentingViewController
        )
        googleCoordinator = coordinator
        defer { googleCoordinator = nil }

        let result = try await coordinator.start()

        guard let idToken = result.user.idToken?.tokenString else {
            AuthFlowDebugTrace.record(
                "credential.rejected",
                layer: "google-provider",
                details: ["reason": "missing-id-token"]
            )
            throw AuthManagerError.missingCredential
        }

        AuthFlowDebugTrace.record(
            "credential.created",
            layer: "google-provider",
            details: [
                "hasIDToken": "true",
                "hasAccessToken": String(!result.user.accessToken.tokenString.isEmpty)
            ]
        )
        return GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
    }

    private func signInWithFirebaseCredential(_ credential: AuthCredential) async throws -> AuthUserSnapshot {
        AuthFlowDebugTrace.record(
            "credential-sign-in.begin",
            layer: "firebase-auth",
            details: ["provider": credential.provider]
        )
        let coordinator = FirebaseCredentialSignInCoordinator(credential: credential)
        firebaseSignInCoordinator = coordinator
        defer { firebaseSignInCoordinator = nil }
        return try await coordinator.start()
    }

    private func appleCredential() async throws -> AuthCredential {
        let nonce = AppleSignInNonce.randomNonceString()
        let coordinator = AppleSignInCoordinator(nonce: nonce)
        appleCoordinator = coordinator
        defer { appleCoordinator = nil }

        let result = try await coordinator.start()
        return OAuthProvider.appleCredential(
            withIDToken: result.identityToken,
            rawNonce: nonce,
            fullName: result.fullName
        )
    }
}

// MARK: - Firebase Credential Sign-In

/// Wraps Firebase's callback API so a stalled SDK request cannot freeze the auth UI forever.
/// Firebase may still finish after the timeout; the global auth-state listener remains the source
/// of truth and will publish that late success to the root navigation gate.
@MainActor
private final class FirebaseCredentialSignInCoordinator {
    private let credential: AuthCredential
    private var continuation: CheckedContinuation<AuthUserSnapshot, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var wasCancelledBeforeStart = false

    init(credential: AuthCredential) {
        self.credential = credential
    }

    func start() async throws -> AuthUserSnapshot {
        AuthFlowDebugTrace.record(
            "request.start",
            layer: "firebase-credential",
            details: [
                "provider": credential.provider,
                "currentUser": BackendTraceStore.safeUID(Auth.auth().currentUser?.uid),
                "cancelled": String(Task.isCancelled)
            ]
        )
#if DEBUG
        authSessionFlowDebugLog("Firebase credential request started")
#endif
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !wasCancelledBeforeStart else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                self.continuation = continuation
                timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(20))
                    } catch {
                        return
                    }

                    if let user = Auth.auth().currentUser?.authSnapshot {
                        AuthFlowDebugTrace.record(
                            "request.timeout.recovered",
                            layer: "firebase-credential",
                            details: ["currentUser": BackendTraceStore.safeUID(user.uid)]
                        )
#if DEBUG
                        authSessionFlowDebugLog("Firebase request timed out but currentUser is available")
#endif
                        self?.finish(.success(user))
                    } else {
                        AuthFlowDebugTrace.record(
                            "request.timeout.failed",
                            layer: "firebase-credential",
                            details: ["currentUser": "none"]
                        )
#if DEBUG
                        authSessionFlowDebugLog("Firebase credential request timed out without a user")
#endif
                        self?.finish(.failure(AuthManagerError.firebaseSignInTimedOut))
                    }
                }

                Auth.auth().signIn(with: credential) { [weak self] result, error in
                    Task { @MainActor in
                        AuthFlowDebugTrace.record(
                            "request.callback",
                            layer: "firebase-credential",
                            details: [
                                "hasResult": String(result != nil),
                                "error": error.map { String(describing: type(of: $0)) } ?? "none",
                                "currentUser": BackendTraceStore.safeUID(Auth.auth().currentUser?.uid)
                            ]
                        )
#if DEBUG
                        authSessionFlowDebugLog(
                            "Firebase credential callback result=\(result != nil) error=\(error?.localizedDescription ?? "none")"
                        )
#endif
                        if let result {
                            self?.finish(.success(result.user.authSnapshot))
                        } else if let error {
                            self?.finish(.failure(error))
                        } else {
                            self?.finish(.failure(AuthManagerError.missingCredential))
                        }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                AuthFlowDebugTrace.record(
                    "request.cancelled",
                    layer: "firebase-credential",
                    details: ["continuationInstalled": String(continuation != nil)]
                )
                wasCancelledBeforeStart = continuation == nil
                finish(.failure(CancellationError()))
            }
        }
    }

    private func finish(_ result: Result<AuthUserSnapshot, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(with: result)
    }
}

// MARK: - Google Sign-In

/// Owns the complete Google authorization lifetime.
///
/// GoogleSignIn stores its presenter weakly. Retaining the stable window root here prevents a
/// transient SwiftUI sheet controller from disappearing while ASWebAuthenticationSession is active.
/// The guarded continuation also guarantees that cancellation and a late SDK callback can never
/// resume the same login request more than once. The interactive Google flow intentionally has no
/// app-imposed timeout because account selection and browser authorization are user-paced.
@MainActor
private final class GoogleSignInCoordinator {
    private let presentingViewController: UIViewController
    private var continuation: CheckedContinuation<GIDSignInResult, Error>?
    private var wasCancelledBeforeStart = false

    init(presentingViewController fallbackPresenter: UIViewController) {
        presentingViewController = Self.stableWindowRoot ?? fallbackPresenter
        AuthFlowDebugTrace.record(
            "coordinator.created",
            layer: "google-sdk",
            details: [
                "selected": String(describing: type(of: presentingViewController)),
                "fallback": String(describing: type(of: fallbackPresenter)),
                "usedStableRoot": String(Self.stableWindowRoot != nil),
                "windowAttached": String(presentingViewController.viewIfLoaded?.window != nil)
            ]
        )
    }

    func start() async throws -> GIDSignInResult {
        AuthFlowDebugTrace.record(
            "request.start",
            layer: "google-sdk",
            details: [
                "presenter": String(describing: type(of: presentingViewController)),
                "windowAttached": String(presentingViewController.viewIfLoaded?.window != nil),
                "cancelled": String(Task.isCancelled)
            ]
        )
#if DEBUG
        authSessionFlowDebugLog(
            "Google SDK request presenter=\(String(describing: type(of: presentingViewController))) "
                + "windowAttached=\(presentingViewController.viewIfLoaded?.window != nil)"
        )
#endif

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !wasCancelledBeforeStart else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                self.continuation = continuation
                GIDSignIn.sharedInstance.signIn(
                    withPresenting: presentingViewController
                ) { [weak self] result, error in
                    Task { @MainActor in
                        AuthFlowDebugTrace.record(
                            "request.callback",
                            layer: "google-sdk",
                            details: [
                                "hasResult": String(result != nil),
                                "error": error.map { String(describing: type(of: $0)) } ?? "none",
                                "currentUser": BackendTraceStore.safeUID(Auth.auth().currentUser?.uid)
                            ]
                        )
#if DEBUG
                        authSessionFlowDebugLog(
                            "Google SDK callback result=\(result != nil) error=\(error?.localizedDescription ?? "none")"
                        )
#endif
                        if let error {
                            self?.finish(.failure(error))
                        } else if let result {
                            self?.finish(.success(result))
                        } else {
                            self?.finish(.failure(AuthManagerError.missingCredential))
                        }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                AuthFlowDebugTrace.record(
                    "request.cancelled",
                    layer: "google-sdk",
                    details: ["continuationInstalled": String(continuation != nil)]
                )
                wasCancelledBeforeStart = continuation == nil
                finish(.failure(CancellationError()))
            }
        }
    }

    private func finish(_ result: Result<GIDSignInResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    private static var stableWindowRoot: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { lhs, rhs in
                lhs.activationState.sortPriority < rhs.activationState.sortPriority
            }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

private extension UIScene.ActivationState {
    var sortPriority: Int {
        switch self {
        case .foregroundActive: 0
        case .foregroundInactive: 1
        case .background: 2
        case .unattached: 3
        @unknown default: 4
        }
    }
}

// MARK: - Firebase User Snapshot

private extension User {
    var authSnapshot: AuthUserSnapshot {
        AuthUserSnapshot(
            uid: uid,
            email: email,
            displayName: displayName,
            photoURLString: photoURL?.absoluteString,
            providers: providerData.map(\.providerID),
            isEmailVerified: isEmailVerified
        )
    }
}

// MARK: - Apple Sign-In

private struct AppleSignInResult {
    let identityToken: String
    let fullName: PersonNameComponents?
}

@MainActor
private final class AppleSignInCoordinator: NSObject {
    private let nonce: String
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?

    init(nonce: String) {
        self.nonce = nonce
    }

    func start() async throws -> AppleSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleSignInNonce.sha256(nonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<AppleSignInResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                finish(.failure(AuthManagerError.missingCredential))
                return
            }

            guard let identityToken = credential.identityToken else {
                finish(.failure(AuthManagerError.missingAppleIdentityToken))
                return
            }

            guard let tokenString = String(data: identityToken, encoding: .utf8) else {
                finish(.failure(AuthManagerError.invalidAppleIdentityToken))
                return
            }

            finish(.success(AppleSignInResult(
                identityToken: tokenString,
                fullName: credential.fullName
            )))
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            finish(.failure(error))
        }
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.activeKeyWindow ?? ASPresentationAnchor()
        }
    }
}

private enum AppleSignInNonce {
    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            guard status == errSecSuccess else {
                fatalError("Unable to generate nonce.")
            }

            randoms.forEach { random in
                guard remainingLength > 0 else { return }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }
}

private extension UIApplication {
    var activeKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

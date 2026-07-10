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
    case googleSignInTimedOut
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
        case .googleSignInTimedOut:
            "Google Sign-In did not finish. Please try again."
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
        guard removeAuthStateListener == nil else { return }
        sessionState = .checking
        let provider = authProvider
        removeAuthStateListener = provider.observeAuthState { [weak self] user in
            self?.apply(user)
        }
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
        guard password == confirmation else {
            throw AuthManagerError.passwordConfirmationMismatch
        }

        let user = try await authProvider.createAccount(
            email: normalizedEmail(email),
            password: password
        )
        apply(user)
        return user
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
        try await authProvider.sendEmailVerification()
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
            throw AuthManagerError.missingPresenter
        }

#if DEBUG
        authSessionFlowDebugLog("Google sign-in started")
#endif
        let provider = authProvider
        let operationID = UUID()
        let task = Task { @MainActor [weak self] in
            defer {
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
        _ = try await task.value
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
#if DEBUG
        authSessionFlowDebugLog("applying auth listener user=\(user?.uid ?? "nil")")
#endif
        guard let user else {
            sessionState = .signedOut
            return
        }

        if user.requiresEmailVerification {
            sessionState = .emailVerificationRequired(user)
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
    }

    private func applySignInSuccess(_ user: AuthUserSnapshot) {
        guard !user.requiresEmailVerification else {
            sessionState = .emailVerificationRequired(user)
            return
        }

        sessionState = .signedIn(user)
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
        let handle = Auth.auth().addStateDidChangeListener { _, user in
#if DEBUG
            authSessionFlowDebugLog("Firebase listener callback user=\(user?.uid ?? "nil")")
#endif
            Task { @MainActor in
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
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        try await result.user.sendEmailVerification()
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
            throw AuthManagerError.missingCurrentUser
        }

        try await user.sendEmailVerification()
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
        guard let clientID = FirebaseApp.app()?.options.clientID else {
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
            throw AuthManagerError.missingCredential
        }

        return GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
    }

    private func signInWithFirebaseCredential(_ credential: AuthCredential) async throws -> AuthUserSnapshot {
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
#if DEBUG
                        authSessionFlowDebugLog("Firebase request timed out but currentUser is available")
#endif
                        self?.finish(.success(user))
                    } else {
#if DEBUG
                        authSessionFlowDebugLog("Firebase credential request timed out without a user")
#endif
                        self?.finish(.failure(AuthManagerError.firebaseSignInTimedOut))
                    }
                }

                Auth.auth().signIn(with: credential) { [weak self] result, error in
                    Task { @MainActor in
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
/// The guarded continuation also guarantees that cancellation, timeout, and a late SDK callback
/// can never resume the same login request more than once.
@MainActor
private final class GoogleSignInCoordinator {
    private let presentingViewController: UIViewController
    private var continuation: CheckedContinuation<GIDSignInResult, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var wasCancelledBeforeStart = false

    init(presentingViewController fallbackPresenter: UIViewController) {
        presentingViewController = Self.stableWindowRoot ?? fallbackPresenter
    }

    func start() async throws -> GIDSignInResult {
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
                timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(60))
                    } catch {
                        return
                    }

#if DEBUG
                    authSessionFlowDebugLog("Google SDK callback timed out")
#endif
                    self?.finish(.failure(AuthManagerError.googleSignInTimedOut))
                }

                GIDSignIn.sharedInstance.signIn(
                    withPresenting: presentingViewController
                ) { [weak self] result, error in
                    Task { @MainActor in
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
                wasCancelledBeforeStart = continuation == nil
                finish(.failure(CancellationError()))
            }
        }
    }

    private func finish(_ result: Result<GIDSignInResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
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

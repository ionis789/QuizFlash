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
        case .signedIn(let user), .emailVerificationRequired(let user), .emailVerificationSucceeded(let user):
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
        let user = try await authProvider.signIn(
            email: normalizedEmail(email),
            password: password
        )
        apply(user)
    }

    func createAccount(
        email: String,
        password: String,
        confirmation: String
    ) async throws {
        guard password == confirmation else {
            throw AuthManagerError.passwordConfirmationMismatch
        }

        let user = try await authProvider.createAccount(
            email: normalizedEmail(email),
            password: password
        )
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

        let user = try await authProvider.signInWithGoogle(
            presentingViewController: presentingViewController
        )
        apply(user)
    }

    func signInWithApple() async throws {
        let user = try await authProvider.signInWithApple()
        apply(user)
    }

    func logout() async throws {
        try await authProvider.signOut()
        sessionState = .signedOut
    }

    func deleteAccount(reauthentication: AuthReauthenticationRequest) async throws {
        try await authProvider.reauthenticate(with: reauthentication)
        try await authProvider.deleteCurrentUser()
        sessionState = .signedOut
    }

    // MARK: - Private

    private func apply(_ user: AuthUserSnapshot?) {
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
            Task { @MainActor in
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
        let result = try await Auth.auth().signIn(with: credential)
        return result.user.authSnapshot
    }

    func signInWithApple() async throws -> AuthUserSnapshot {
        let credential = try await appleCredential()
        let result = try await Auth.auth().signIn(with: credential)
        return result.user.authSnapshot
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
        let result: GIDSignInResult = try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result else {
                    continuation.resume(throwing: AuthManagerError.missingCredential)
                    return
                }

                continuation.resume(returning: result)
            }
        }

        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthManagerError.missingCredential
        }

        return GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
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

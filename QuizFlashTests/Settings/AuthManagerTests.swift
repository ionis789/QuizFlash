//
//  AuthManagerTests.swift
//  QuizFlashTests
//
//  Covers Firebase-backed authentication state coordination.
//

import UIKit
import XCTest
@testable import QuizFlash

@MainActor
final class AuthManagerTests: XCTestCase {
    func testStartListeningPublishesSignedOutWhenNoUserExists() {
        let provider = MockAuthProvider(currentUser: nil)
        let manager = AuthManager(authProvider: provider)

        manager.startListening()

        XCTAssertEqual(manager.sessionState, .signedOut)
        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertNil(manager.currentUser)
    }

    func testStartListeningPublishesSignedInForVerifiedPasswordUser() {
        let user = AuthUserSnapshot.verifiedPasswordUser
        let provider = MockAuthProvider(currentUser: user)
        let manager = AuthManager(authProvider: provider)

        manager.startListening()

        XCTAssertEqual(manager.sessionState, .signedIn(user))
        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertEqual(manager.currentUser, user)
    }

    func testStartListeningBlocksUnverifiedPasswordUser() {
        let user = AuthUserSnapshot.unverifiedPasswordUser
        let provider = MockAuthProvider(currentUser: user)
        let manager = AuthManager(authProvider: provider)

        manager.startListening()

        XCTAssertEqual(manager.sessionState, .emailVerificationRequired(user))
        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertEqual(manager.currentUser, user)
    }

    func testStartListeningAllowsGoogleUserWithoutEmailVerification() {
        let user = AuthUserSnapshot.googleUser
        let provider = MockAuthProvider(currentUser: user)
        let manager = AuthManager(authProvider: provider)

        manager.startListening()

        XCTAssertEqual(manager.sessionState, .signedIn(user))
        XCTAssertTrue(manager.isAuthenticated)
    }

    func testStartListeningFallsBackToCurrentUserWhenInitialListenerDoesNotEmit() {
        let user = AuthUserSnapshot.verifiedPasswordUser
        let provider = MockAuthProvider(currentUser: user)
        provider.shouldEmitInitialAuthState = false
        let manager = AuthManager(authProvider: provider)

        manager.startListening()

        XCTAssertEqual(manager.sessionState, .signedIn(user))
        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertEqual(manager.currentUser, user)
    }

    func testCreateAccountSendsVerificationAndRequiresVerification() async throws {
        let user = AuthUserSnapshot.unverifiedPasswordUser
        let provider = MockAuthProvider(currentUser: nil)
        provider.createAccountResult = user
        let manager = AuthManager(authProvider: provider)

        try await manager.createAccount(
            email: " user@example.com ",
            password: "password",
            confirmation: "password"
        )

        XCTAssertEqual(provider.createdEmail, "user@example.com")
        XCTAssertEqual(provider.sentVerificationCount, 1)
        XCTAssertEqual(manager.sessionState, .emailVerificationRequired(user))
        XCTAssertFalse(manager.isAuthenticated)
    }

    func testCreateAccountRejectsMismatchedConfirmation() async {
        let provider = MockAuthProvider(currentUser: nil)
        let manager = AuthManager(authProvider: provider)

        do {
            try await manager.createAccount(
                email: "user@example.com",
                password: "password",
                confirmation: "different"
            )
            XCTFail("Expected mismatch error.")
        } catch {
            XCTAssertEqual(error as? AuthManagerError, .passwordConfirmationMismatch)
        }
    }

    func testReloadShowsEmailVerificationSuccessBeforeSigningIn() async throws {
        let unverifiedUser = AuthUserSnapshot.unverifiedPasswordUser
        let verifiedUser = AuthUserSnapshot(
            uid: unverifiedUser.uid,
            email: unverifiedUser.email,
            displayName: unverifiedUser.displayName,
            photoURLString: unverifiedUser.photoURLString,
            providers: unverifiedUser.providers,
            isEmailVerified: true
        )
        let provider = MockAuthProvider(currentUser: unverifiedUser)
        provider.reloadResult = verifiedUser
        let manager = AuthManager(authProvider: provider)
        manager.startListening()

        try await manager.reloadEmailVerificationStatus()

        XCTAssertEqual(manager.sessionState, .emailVerificationSucceeded(verifiedUser))
        XCTAssertFalse(manager.isAuthenticated)

        manager.completeEmailVerificationSuccess()

        XCTAssertEqual(manager.sessionState, .signedIn(verifiedUser))
        XCTAssertTrue(manager.isAuthenticated)
    }

    func testPasswordResetNormalizesEmail() async throws {
        let provider = MockAuthProvider(currentUser: nil)
        let manager = AuthManager(authProvider: provider)

        try await manager.sendPasswordReset(email: " user@example.com ")

        XCTAssertEqual(provider.passwordResetEmail, "user@example.com")
    }

    func testUpdateDisplayNameTrimsAndPublishesUpdatedUser() async throws {
        let provider = MockAuthProvider(currentUser: .verifiedPasswordUser)
        let manager = AuthManager(authProvider: provider)

        try await manager.updateDisplayName("  Ada Lovelace  ")

        XCTAssertEqual(provider.updatedDisplayName, "Ada Lovelace")
        XCTAssertEqual(manager.currentUser?.displayName, "Ada Lovelace")
    }

    func testLogoutClearsSession() async throws {
        let provider = MockAuthProvider(currentUser: .verifiedPasswordUser)
        let manager = AuthManager(authProvider: provider)
        manager.startListening()

        try await manager.logout()

        XCTAssertTrue(provider.didSignOut)
        XCTAssertEqual(manager.sessionState, .signedOut)
        XCTAssertFalse(manager.isAuthenticated)
    }

    func testDeleteAccountReauthenticatesThenDeletes() async throws {
        let provider = MockAuthProvider(currentUser: .verifiedPasswordUser)
        let manager = AuthManager(authProvider: provider)

        try await manager.deleteAccount(reauthentication: .password("password"))

        XCTAssertEqual(provider.reauthenticatedPassword, "password")
        XCTAssertTrue(provider.didDeleteUser)
        XCTAssertEqual(manager.sessionState, .signedOut)
    }
}

@MainActor
private final class MockAuthProvider: AuthProviding {
    var currentUser: AuthUserSnapshot?
    var signInResult: AuthUserSnapshot = .verifiedPasswordUser
    var createAccountResult: AuthUserSnapshot = .unverifiedPasswordUser
    var googleSignInResult: AuthUserSnapshot = .googleUser
    var appleSignInResult: AuthUserSnapshot = .appleUser
    var reloadResult: AuthUserSnapshot?
    var createdEmail: String?
    var signedInEmail: String?
    var passwordResetEmail: String?
    var updatedDisplayName: String?
    var sentVerificationCount = 0
    var didSignOut = false
    var didDeleteUser = false
    var reauthenticatedPassword: String?
    var shouldEmitInitialAuthState = true

    init(currentUser: AuthUserSnapshot?) {
        self.currentUser = currentUser
    }

    func observeAuthState(
        _ handler: @escaping @MainActor (AuthUserSnapshot?) -> Void
    ) -> @MainActor () -> Void {
        if shouldEmitInitialAuthState {
            handler(currentUser)
        }
        return { }
    }

    func signIn(email: String, password: String) async throws -> AuthUserSnapshot {
        signedInEmail = email
        currentUser = signInResult
        return signInResult
    }

    func createAccount(email: String, password: String) async throws -> AuthUserSnapshot {
        createdEmail = email
        sentVerificationCount += 1
        currentUser = createAccountResult
        return createAccountResult
    }

    func updateDisplayName(_ displayName: String?) async throws -> AuthUserSnapshot {
        updatedDisplayName = displayName
        let updatedUser = AuthUserSnapshot(
            uid: currentUser?.uid ?? "updated-user",
            email: currentUser?.email,
            displayName: displayName,
            photoURLString: currentUser?.photoURLString,
            providers: currentUser?.providers ?? [],
            isEmailVerified: currentUser?.isEmailVerified ?? true
        )
        currentUser = updatedUser
        return updatedUser
    }

    func sendPasswordReset(email: String) async throws {
        passwordResetEmail = email
    }

    func sendEmailVerification() async throws {
        sentVerificationCount += 1
    }

    func reloadCurrentUser() async throws -> AuthUserSnapshot? {
        currentUser = reloadResult
        return reloadResult
    }

    func signInWithGoogle(presentingViewController: UIViewController) async throws -> AuthUserSnapshot {
        currentUser = googleSignInResult
        return googleSignInResult
    }

    func signInWithApple() async throws -> AuthUserSnapshot {
        currentUser = appleSignInResult
        return appleSignInResult
    }

    func reauthenticate(with request: AuthReauthenticationRequest) async throws {
        if case .password(let password) = request {
            reauthenticatedPassword = password
        }
    }

    func signOut() async throws {
        didSignOut = true
        currentUser = nil
    }

    func deleteCurrentUser() async throws {
        didDeleteUser = true
        currentUser = nil
    }
}

private extension AuthUserSnapshot {
    static let verifiedPasswordUser = AuthUserSnapshot(
        uid: "password-verified",
        email: "user@example.com",
        displayName: nil,
        photoURLString: nil,
        providers: [AuthProviderID.password.rawValue],
        isEmailVerified: true
    )

    static let unverifiedPasswordUser = AuthUserSnapshot(
        uid: "password-unverified",
        email: "user@example.com",
        displayName: nil,
        photoURLString: nil,
        providers: [AuthProviderID.password.rawValue],
        isEmailVerified: false
    )

    static let googleUser = AuthUserSnapshot(
        uid: "google-user",
        email: "user@example.com",
        displayName: "User",
        photoURLString: nil,
        providers: [AuthProviderID.google.rawValue],
        isEmailVerified: false
    )

    static let appleUser = AuthUserSnapshot(
        uid: "apple-user",
        email: "user@example.com",
        displayName: nil,
        photoURLString: nil,
        providers: [AuthProviderID.apple.rawValue],
        isEmailVerified: false
    )
}

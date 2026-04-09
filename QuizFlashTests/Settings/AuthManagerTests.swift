//
//  AuthManagerTests.swift
//  QuizFlashTests
//
//  Covers authentication state persistence backed by UserDefaults.
//

import XCTest
@testable import QuizFlash

@MainActor
final class AuthManagerTests: XCTestCase {
    func testAuthManagerPersistsAuthenticationState() async {
        let suiteName = "AuthManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = AuthManager(
            userDefaults: defaults,
            simulatedLoginDelay: .zero
        )
        XCTAssertFalse(manager.isAuthenticated)

        await manager.loginWithGoogle()
        XCTAssertTrue(manager.isAuthenticated)

        let reloadedManager = AuthManager(userDefaults: defaults)
        XCTAssertTrue(reloadedManager.isAuthenticated)

        reloadedManager.logout()

        let loggedOutManager = AuthManager(userDefaults: defaults)
        XCTAssertFalse(loggedOutManager.isAuthenticated)
    }
}

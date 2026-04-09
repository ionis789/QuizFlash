//
//  AuthManager.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.12.2025.
//

import Foundation
import Observation

// MARK: - AuthManager

/// Manages the authentication state of the current user.
///
/// `AuthManager` is a singleton that persists the authenticated status in
/// `UserDefaults` and exposes it as an `@Observable` property so any SwiftUI
/// view that reads `isAuthenticated` is automatically invalidated on change.
///
/// All state mutations happen on the `MainActor` to guarantee thread-safe
/// observation updates.
@Observable
@MainActor
final class AuthManager {

    // MARK: - Shared Instance

    /// The app-wide singleton.
    static let shared = AuthManager()

    private enum Keys {
        static let isAuthenticated = "is_authenticated"
    }

    private let userDefaults: UserDefaults
    private let simulatedLoginDelay: Duration

    // MARK: - State

    /// Whether a user is currently authenticated.
    ///
    /// Persisted in the manager's injected `UserDefaults` store.
    private(set) var isAuthenticated: Bool {
        didSet {
            userDefaults.set(isAuthenticated, forKey: Keys.isAuthenticated)
        }
    }

    // MARK: - Init

    init(
        userDefaults: UserDefaults = .standard,
        simulatedLoginDelay: Duration = .seconds(1)
    ) {
        self.userDefaults = userDefaults
        self.simulatedLoginDelay = simulatedLoginDelay
        self.isAuthenticated = userDefaults.object(forKey: Keys.isAuthenticated) as? Bool ?? false
    }

    // MARK: - Public Interface

    /// Simulates a Google Sign-In flow.
    ///
    /// In production replace this stub with the real Google Sign-In SDK call.
    /// The method is `async` so call-sites can `await` completion without
    /// blocking the main thread.
    func loginWithGoogle() async {
        try? await Task.sleep(for: simulatedLoginDelay)
        isAuthenticated = true
    }

    /// Signs the current user out and clears the persisted session.
    func logout() {
        isAuthenticated = false
    }
}

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

    // MARK: - State

    /// Whether a user is currently authenticated.
    ///
    /// Persisted in `UserDefaults` under the key `"is_authenticated"`.
    private(set) var isAuthenticated: Bool {
        didSet {
            UserDefaults.standard.set(isAuthenticated, forKey: "is_authenticated")
        }
    }

    // MARK: - Init

    private init() {
        self.isAuthenticated = UserDefaults.standard.bool(forKey: "is_authenticated")
    }

    // MARK: - Public Interface

    /// Simulates a Google Sign-In flow.
    ///
    /// In production replace this stub with the real Google Sign-In SDK call.
    /// The method is `async` so call-sites can `await` completion without
    /// blocking the main thread.
    func loginWithGoogle() async {
        try? await Task.sleep(for: .seconds(1))
        isAuthenticated = true
    }

    /// Signs the current user out and clears the persisted session.
    func logout() {
        isAuthenticated = false
    }
}

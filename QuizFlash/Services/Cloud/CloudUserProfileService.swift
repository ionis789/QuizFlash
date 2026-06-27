//
//  CloudUserProfileService.swift
//  QuizFlash
//

import FirebaseFirestore
import FirebaseFunctions
import Foundation
import Observation

// MARK: - Cloud User Profile Service

/// Owns Firebase user-profile operations.
@Observable
@MainActor
final class CloudUserProfileService {

    // MARK: - Shared

    static let shared = CloudUserProfileService()

    // MARK: - State

    private(set) var lastUpsertedUID: String?
    private(set) var lastErrorMessage: String?

    @ObservationIgnored
    private var cachedFunctions: Functions?

    @ObservationIgnored
    private var cachedFirestore: Firestore?

    // MARK: - Init

    init() { }

    init(functions: Functions, firestore: Firestore) {
        self.cachedFunctions = functions
        self.cachedFirestore = firestore
    }

    // MARK: - Public

    /// Creates or refreshes the user profile document.
    func upsertUserProfile(for user: AuthUserSnapshot?) async {
        guard let user else {
            lastUpsertedUID = nil
            lastErrorMessage = nil
            return
        }

        do {
            try await upsertUserProfileDirectly(for: user)
            await upsertUserProfileThroughFunctionIfAvailable(for: user)
            lastUpsertedUID = user.uid
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Deletes cloud-owned user data before the Firebase Auth account is deleted.
    func deleteUserData() async throws {
        _ = try await functions.httpsCallable("deleteUserData").call([:])
    }

    /// Reads the server-owned user profile document.
    func userProfileDocument(uid: String) async throws -> [String: Any]? {
        try await firestore.collection("users").document(uid).getDocument().data()
    }

    private func upsertUserProfileDirectly(for user: AuthUserSnapshot) async throws {
        var payload: [String: Any] = [
            "providers": user.providers,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let email = user.email { payload["email"] = email }
        if let displayName = user.displayName { payload["displayName"] = displayName }
        if let photoURL = user.photoURLString { payload["photoURL"] = photoURL }

        try await firestore
            .collection("users")
            .document(user.uid)
            .setData(payload, merge: true)
    }

    private func upsertUserProfileThroughFunctionIfAvailable(for user: AuthUserSnapshot) async {
        var payload: [String: Any] = ["providers": user.providers]
        if let email = user.email { payload["email"] = email }
        if let displayName = user.displayName { payload["displayName"] = displayName }
        if let photoURL = user.photoURLString { payload["photoURL"] = photoURL }

        _ = try? await functions.httpsCallable("upsertUserProfile").call(payload)
    }

    private var functions: Functions {
        if let cachedFunctions { return cachedFunctions }
        let functions = Functions.functions()
        cachedFunctions = functions
        return functions
    }

    private var firestore: Firestore {
        if let cachedFirestore { return cachedFirestore }
        let firestore = Firestore.firestore()
        cachedFirestore = firestore
        return firestore
    }
}

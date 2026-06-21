//
//  SubscriptionManager.swift
//  QuizFlash
//

import FirebaseAuth
import FirebaseFirestore
import Foundation
import Observation

// MARK: - Subscription Manager

/// Reads the current subscription state from Firebase while App Store setup is unavailable.
@Observable
@MainActor
final class SubscriptionManager {

    // MARK: - Shared

    static let shared = SubscriptionManager()
    static let defaultFreeGenerationsLimit = 5

    // MARK: - State

    private(set) var isPremium = false
    private(set) var planSource: SubscriptionPlanSource = .none
    private(set) var freeGenerationsUsed: Int?
    private(set) var freeGenerationsLimit: Int?
    private(set) var lastErrorMessage: String?
    var presentPaywall = false

    @ObservationIgnored
    private var cachedFirestore: Firestore?

    // MARK: - Init

    init() { }

    init(firestore: Firestore) {
        self.cachedFirestore = firestore
    }

    // MARK: - Public

    /// Refreshes premium state for the current Firebase user.
    func configure(for user: AuthUserSnapshot?) async {
        guard let user else {
            applySignedOutState()
            return
        }

        await refresh(uid: user.uid)
    }

    /// Re-reads custom claims and the user profile document.
    func refresh(uid: String? = Auth.auth().currentUser?.uid) async {
        guard let uid else {
            applySignedOutState()
            return
        }

        do {
            let tokenResult = try await Auth.auth().currentUser?.getIDTokenResult(forcingRefresh: true)
            let claimPremium = tokenResult?.claims["premium"] as? Bool

            let userData = try await firestore
                .collection("users")
                .document(uid)
                .getDocument()
                .data()

            let profilePremium = userData?["premium"] as? Bool
            let profilePlan = userData?["plan"] as? String
            lastErrorMessage = nil

            if claimPremium == true {
                isPremium = true
                planSource = .firebaseCustomClaim
            } else if profilePremium == true || profilePlan == "premium" {
                isPremium = true
                planSource = .manualFirestore
            } else {
                isPremium = false
                planSource = .free
            }

            let usage = userData?["freeGenerationsUsed"] as? Int
            let limit = userData?["freeGenerationsLimit"] as? Int
            freeGenerationsUsed = isPremium ? nil : usage ?? 0
            freeGenerationsLimit = isPremium ? nil : limit ?? Self.defaultFreeGenerationsLimit
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func aiGenerationLimitMessage(locale: Locale) -> String? {
        guard !isPremium,
              let freeGenerationsUsed,
              let freeGenerationsLimit,
              freeGenerationsUsed >= freeGenerationsLimit else {
            return nil
        }

        return AppLocalization.string("Upgrade to Premium to generate more cards.", locale: locale)
    }

    /// Placeholder action until App Store Connect purchases are available.
    func restorePurchases() async throws {
        throw SubscriptionManagerError.storeUnavailable
    }

    // MARK: - Private

    private func applySignedOutState() {
        isPremium = false
        planSource = .none
        freeGenerationsUsed = nil
        freeGenerationsLimit = nil
        lastErrorMessage = nil
    }

    private var firestore: Firestore {
        if let cachedFirestore { return cachedFirestore }
        let firestore = Firestore.firestore()
        cachedFirestore = firestore
        return firestore
    }
}

// MARK: - Subscription Plan Source

enum SubscriptionPlanSource: String, Sendable {
    case none
    case free
    case manualFirestore
    case firebaseCustomClaim

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .none:
            return AppLocalization.string("Not signed in", locale: locale)
        case .free:
            return AppLocalization.string("Free", locale: locale)
        case .manualFirestore:
            return AppLocalization.string("Manual premium", locale: locale)
        case .firebaseCustomClaim:
            return AppLocalization.string("Firebase claim", locale: locale)
        }
    }
}

// MARK: - Subscription Manager Error

enum SubscriptionManagerError: LocalizedError {
    case storeUnavailable

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            return "Purchases are not available until App Store Connect is ready."
        }
    }
}

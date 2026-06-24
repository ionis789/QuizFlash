//
//  SubscriptionManager.swift
//  QuizFlash
//

import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
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
    static let freeMaxCardsPerGeneration = 30
    static let premiumMaxCardsPerGeneration = 100

    // MARK: - State

    private(set) var isPremium = false
    private(set) var planSource: SubscriptionPlanSource = .none
    private(set) var freeGenerationsUsed: Int?
    private(set) var freeGenerationsLimit: Int?
    private(set) var cloudAIUsageQuota: CloudAIQuotaState?
    private(set) var lastErrorMessage: String?
    var presentPaywall = false

    @ObservationIgnored
    private var cachedFirestore: Firestore?

    @ObservationIgnored
    private var cachedFunctions: Functions?

    // MARK: - Init

    init() { }

    init(firestore: Firestore, functions: Functions? = nil) {
        self.cachedFirestore = firestore
        self.cachedFunctions = functions
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

    var maxCardsPerGeneration: Int {
        isPremium ? Self.premiumMaxCardsPerGeneration : Self.freeMaxCardsPerGeneration
    }

    var cloudAIUsageProgress: Double {
        cloudAIUsageQuota?.usageProgress ?? 0
    }

    func consumeAIGenerationQuota(targetCards: Int) async throws {
        do {
            let result = try await functions.httpsCallable("consumeAIGenerationQuota").call([
                "targetCards": targetCards
            ])

            guard let response = result.data as? [String: Any] else {
                await refresh()
                return
            }

            applyQuotaResponse(response)
        } catch {
            try await consumeAIGenerationQuotaDirectly(targetCards: targetCards)
        }
    }

    func applyCloudAIQuotaState(_ state: CloudAIQuotaState) {
        isPremium = state.premium
        planSource = state.premium ? .manualFirestore : .free
        freeGenerationsUsed = state.premium ? nil : state.freeGenerationsUsed
        freeGenerationsLimit = state.premium ? nil : state.freeGenerationsLimit ?? Self.defaultFreeGenerationsLimit
        cloudAIUsageQuota = state
        lastErrorMessage = nil
    }

    private func applyQuotaResponse(_ response: [String: Any]) {
        if response["premium"] as? Bool == true {
            isPremium = true
            planSource = .manualFirestore
            freeGenerationsUsed = nil
            freeGenerationsLimit = nil
        } else {
            isPremium = false
            planSource = .free
            freeGenerationsUsed = response["freeGenerationsUsed"] as? Int ?? freeGenerationsUsed
            freeGenerationsLimit = response["freeGenerationsLimit"] as? Int ?? freeGenerationsLimit ?? Self.defaultFreeGenerationsLimit
        }
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
        cloudAIUsageQuota = nil
    }

    private func consumeAIGenerationQuotaDirectly(targetCards: Int) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw SubscriptionManagerError.signInRequired
        }

        let userRef = firestore.collection("users").document(uid)
        let response: [String: Any] = try await withCheckedThrowingContinuation { continuation in
            firestore.runTransaction({ transaction, errorPointer -> Any? in
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(userRef)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }

                let data = snapshot.data() ?? [:]
                let premium = data["premium"] as? Bool == true || data["plan"] as? String == "premium"
                let maxCards = premium ? Self.premiumMaxCardsPerGeneration : Self.freeMaxCardsPerGeneration

                guard targetCards <= maxCards else {
                    errorPointer?.pointee = SubscriptionManagerError.aiCardLimitExceeded(maximum: maxCards) as NSError
                    return nil
                }

                if premium {
                    return [
                        "premium": true
                    ]
                }

                let used = data["freeGenerationsUsed"] as? Int ?? 0
                let limit = data["freeGenerationsLimit"] as? Int ?? Self.defaultFreeGenerationsLimit

                guard used < limit else {
                    errorPointer?.pointee = SubscriptionManagerError.freeGenerationLimitReached as NSError
                    return nil
                }

                let nextUsed = used + 1
                transaction.setData([
                    "freeGenerationsUsed": nextUsed,
                    "freeGenerationsLimit": limit,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: userRef, merge: true)

                return [
                    "premium": false,
                    "freeGenerationsUsed": nextUsed,
                    "freeGenerationsLimit": limit
                ]
            }) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: object as? [String: Any] ?? [:])
                }
            }
        }

        applyQuotaResponse(response)
    }

    private var firestore: Firestore {
        if let cachedFirestore { return cachedFirestore }
        let firestore = Firestore.firestore()
        cachedFirestore = firestore
        return firestore
    }

    private var functions: Functions {
        if let cachedFunctions { return cachedFunctions }
        let functions = Functions.functions()
        cachedFunctions = functions
        return functions
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
    case signInRequired
    case aiCardLimitExceeded(maximum: Int)
    case freeGenerationLimitReached

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            return "Purchases are not available until App Store Connect is ready."
        case .signInRequired:
            return "Sign in is required."
        case .aiCardLimitExceeded(let maximum):
            return "This plan allows up to \(maximum) cards per generation."
        case .freeGenerationLimitReached:
            return "Free AI generation limit reached."
        }
    }
}

//
//  OnboardingStateStore.swift
//  QuizFlash
//
//  Created by Ion Socol on 03.07.2026.
//

import Foundation
import Observation

// MARK: - Onboarding Presentation

/// Describes the active onboarding surface and whether completion should be persisted.
enum OnboardingPresentation: Identifiable, Equatable, Sendable {
    case intro(UUID)
    case required(uid: String)
    case preview(UUID)

    var id: String {
        switch self {
        case .intro(let id):
            "intro-\(id.uuidString)"
        case .required(let uid):
            "required-\(uid)"
        case .preview(let id):
            "preview-\(id.uuidString)"
        }
    }

    var allowsClose: Bool {
        if case .preview = self {
            return true
        }
        return false
    }

    var isIntro: Bool {
        if case .intro = self {
            return true
        }
        return false
    }
}

// MARK: - Onboarding State Store

/// Persists first-account onboarding state and owns manual preview presentation.
@Observable
@MainActor
final class OnboardingStateStore {

    // MARK: - Shared Instance

    static let shared = OnboardingStateStore()

    // MARK: - Dependencies

    @ObservationIgnored
    private let userDefaults: UserDefaults

    // MARK: - State

    private(set) var presentation: OnboardingPresentation?
    private var hasDismissedIntroForCurrentAuthAttempt = false

    // MARK: - Init

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Public

    func markPendingForNewAccount(uid: String) {
        guard !uid.isEmpty else { return }
        var pendingUIDs = storedSet(forKey: Self.pendingUIDsKey)
        pendingUIDs.insert(uid)
        store(pendingUIDs, forKey: Self.pendingUIDsKey)
    }

    func presentRequiredIfNeeded(for user: AuthUserSnapshot?) {
        guard let uid = user?.uid, shouldPresentRequiredOnboarding(for: uid) else {
            if case .required = presentation {
                presentation = nil
            }
            return
        }

        guard presentation != .required(uid: uid) else { return }
        presentation = .required(uid: uid)
    }

    func presentIntroIfNeeded() {
        guard !hasDismissedIntroForCurrentAuthAttempt else { return }
        guard presentation == nil else { return }
        presentation = .intro(UUID())
    }

    func presentPreview() {
        presentation = .preview(UUID())
    }

    func complete(_ completedPresentation: OnboardingPresentation) {
        if case .intro = completedPresentation {
            hasDismissedIntroForCurrentAuthAttempt = true
            userDefaults.set(true, forKey: Self.pendingPostAuthSetupKey)
        } else if case .required(let uid) = completedPresentation {
            markCompleted(uid: uid)
            userDefaults.set(false, forKey: Self.pendingPostAuthSetupKey)
            hasDismissedIntroForCurrentAuthAttempt = false
        }

        if presentation?.id == completedPresentation.id {
            presentation = nil
        }
    }

    func closePreview(_ previewPresentation: OnboardingPresentation) {
        guard previewPresentation.allowsClose else { return }
        guard presentation?.id == previewPresentation.id else { return }
        presentation = nil
    }

    func hasCompletedOnboarding(for uid: String) -> Bool {
        storedSet(forKey: Self.completedUIDsKey).contains(uid)
    }

    func hasPendingOnboarding(for uid: String) -> Bool {
        storedSet(forKey: Self.pendingUIDsKey).contains(uid)
    }

    // MARK: - Private

    private static let completedUIDsKey = "onboarding.completedUIDs"
    private static let pendingPostAuthSetupKey = "onboarding.pendingPostAuthSetup"
    private static let pendingUIDsKey = "onboarding.pendingUIDs"

    private func shouldPresentRequiredOnboarding(for uid: String) -> Bool {
        !hasCompletedOnboarding(for: uid)
            && (hasPendingOnboarding(for: uid) || userDefaults.bool(forKey: Self.pendingPostAuthSetupKey))
    }

    private func markCompleted(uid: String) {
        guard !uid.isEmpty else { return }

        var completedUIDs = storedSet(forKey: Self.completedUIDsKey)
        completedUIDs.insert(uid)
        store(completedUIDs, forKey: Self.completedUIDsKey)

        var pendingUIDs = storedSet(forKey: Self.pendingUIDsKey)
        pendingUIDs.remove(uid)
        store(pendingUIDs, forKey: Self.pendingUIDsKey)
    }

    private func storedSet(forKey key: String) -> Set<String> {
        Set(userDefaults.stringArray(forKey: key) ?? [])
    }

    private func store(_ values: Set<String>, forKey key: String) {
        userDefaults.set(values.sorted(), forKey: key)
    }
}

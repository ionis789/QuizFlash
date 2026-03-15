//
//  AIGenerationBackgroundCoordinator.swift
//  QuizFlash
//
//  Best-effort background continuation support for AI generation sessions.
//

import Foundation
import UIKit
import UserNotifications

final class AIGenerationBackgroundCoordinator {
    static let shared = AIGenerationBackgroundCoordinator()

    private enum NotificationKind: String {
        case completed
        case interrupted
    }

    private let notificationCenter = UNUserNotificationCenter.current()
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var activeSessionID: UUID?

    private init() { }

    func requestNotificationAuthorizationIfNeeded() async -> Bool {
        let settings = await notificationCenter.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func beginSession(
        id: UUID,
        onExpiration: @escaping @MainActor @Sendable () -> Void
    ) {
        endSession(id: activeSessionID)
        activeSessionID = id

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "QuizFlashAIGeneration") { [weak self] in
            guard let self else { return }
            guard self.activeSessionID == id else { return }

            let taskID = self.backgroundTaskID
            self.activeSessionID = nil
            self.backgroundTaskID = .invalid

            // Notify the main actor first to let it do quick cleanup
            Task { @MainActor in
                onExpiration()
            }
            
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
            }
        }
    }

    func endSession(id: UUID?) {
        guard let id, activeSessionID == id else { return }

        let taskID = backgroundTaskID
        activeSessionID = nil
        backgroundTaskID = .invalid

        if taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }

    func notifyCompletionIfNeeded(
        sessionID: UUID,
        deckTitle: String,
        generatedCardCount: Int
    ) async {
        let applicationState = await MainActor.run { UIApplication.shared.applicationState }
        guard applicationState != .active else { return }
        guard await requestNotificationAuthorizationIfNeeded() else { return }

        let title = generatedCardCount == 1
            ? "1 AI card is ready"
            : "\(generatedCardCount) AI cards are ready"
        let body = deckTitle.isEmpty
            ? "QuizFlash finished generating your cards."
            : "\"\(deckTitle)\" finished generating in QuizFlash."

        scheduleNotification(
            id: sessionID,
            kind: .completed,
            title: title,
            body: body
        )
    }

    func notifyInterruptionIfNeeded(
        sessionID: UUID,
        deckTitle: String,
        generatedCardCount: Int
    ) async {
        let applicationState = await MainActor.run { UIApplication.shared.applicationState }
        guard applicationState != .active else { return }
        guard await requestNotificationAuthorizationIfNeeded() else { return }

        let keptCardsText = generatedCardCount > 0
            ? "\(generatedCardCount) cards were kept."
            : "No cards were produced yet."
        let body = deckTitle.isEmpty
            ? "QuizFlash ran out of background time. \(keptCardsText)"
            : "\"\(deckTitle)\" ran out of background time. \(keptCardsText)"

        scheduleNotification(
            id: sessionID,
            kind: .interrupted,
            title: "AI generation paused",
            body: body
        )
    }

    private func scheduleNotification(
        id: UUID,
        kind: NotificationKind,
        title: String,
        body: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [
            "destination": "ai_generation",
            "kind": kind.rawValue,
            "session_id": id.uuidString
        ]

        let request = UNNotificationRequest(
            identifier: "ai-generation-\(kind.rawValue)-\(id.uuidString)",
            content: content,
            trigger: nil
        )

        notificationCenter.add(request)
    }
}

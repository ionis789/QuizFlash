//
//  ZoneFocusManager.swift
//  QuizFlash
//
//  Logic: focus and keyboard retention for zone editor (no UI).
//

import SwiftUI
import Combine

// MARK: - Focus Notifications

extension Notification.Name {
    static let focusNewZone = Notification.Name("focusNewZone")
    static let scrollToCursor = Notification.Name("scrollToCursor")
}

// MARK: - Zone Focus Manager

/// Singleton that manages focus for new zones and prevents keyboard flicker by syncing with SwiftUI render cycle.
@MainActor
final class ZoneFocusManager: ObservableObject {
    static let shared = ZoneFocusManager()

    @Published var pendingFocusZoneID: UUID?
    @Published var shouldRetainKeyboard: Bool = false

    private var releaseTask: Task<Void, Never>?

    func requestFocus(for zoneID: UUID) {
        pendingFocusZoneID = zoneID
    }

    func clearPendingFocus() {
        pendingFocusZoneID = nil
        releaseTask?.cancel()
        releaseTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !Task.isCancelled {
                self.shouldRetainKeyboard = false
            }
        }
    }

    func prepareForInsertion() {
        releaseTask?.cancel()
        shouldRetainKeyboard = true
    }
}

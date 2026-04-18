//
//  ZoneFocusManager.swift
//  QuizFlash
//
//  Manages focus state and keyboard retention for zone editor.
//  Works in conjunction with ZoneController.
//

import SwiftUI

// MARK: - Focus Notifications

extension Notification.Name {
    static let focusNewZone = Notification.Name("focusNewZone")
    static let scrollToCursor = Notification.Name("scrollToCursor")
    static let zoneFocusRequest = Notification.Name("zoneFocusRequest")
    static let focusZoneTextView = Notification.Name("focusZoneTextView")
}

// MARK: - Zone Focus Manager

/// Singleton managing focus state and keyboard retention for zone editing.
@Observable
@MainActor
final class ZoneFocusManager {
    static let shared = ZoneFocusManager()
    
    // MARK: - Public Properties
    
    /// Zone ID that should receive focus on next render cycle
    var pendingFocusZoneID: UUID?
    
    /// Currently focused zone ID
    var focusedZoneID: UUID?
    
    /// Flag to retain keyboard during operations
    var shouldRetainKeyboard: Bool = false
    
    // MARK: - Private State
    
    private var keyboardRetainTask: Task<Void, Never>?
    private var focusRetentionTask: Task<Void, Never>?
    private var focusNotificationTask: Task<Void, Never>?
    
    // MARK: - Focus Management
    
    /// Requests focus for a specific zone
    func requestFocus(for zoneID: UUID) {
        pendingFocusZoneID = zoneID
        focusedZoneID = zoneID
        
        // Post notification for UIKit components
        NotificationCenter.default.post(
            name: .zoneFocusRequest,
            object: zoneID
        )
        
        // Also post focus notification
        focusNotificationTask?.cancel()
        focusNotificationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(
                name: .focusZoneTextView,
                object: zoneID
            )
        }
    }
    
    /// Clears pending focus after successful focus
    func clearPendingFocus() {
        pendingFocusZoneID = nil
        releaseKeyboardRetention()
    }
    
    /// Updates the currently focused zone
    func updateFocusedZone(_ zoneID: UUID?) {
        focusedZoneID = zoneID
    }
    
    // MARK: - Keyboard Retention
    
    /// Prepares for zone insertion - retains keyboard
    func prepareForZoneInsertion() {
        keyboardRetainTask?.cancel()
        shouldRetainKeyboard = true
    }
    
    /// Releases keyboard retention after a delay
    func releaseKeyboardRetention(afterDelay delay: Double = 0.12) {
        keyboardRetainTask?.cancel()
        keyboardRetainTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.shouldRetainKeyboard = false
            }
        }
    }
    
    /// Force releases keyboard immediately
    func forceReleaseKeyboard() {
        keyboardRetainTask?.cancel()
        shouldRetainKeyboard = false
    }
    
    // MARK: - Focus Retention for Transitions
    
    /// Retains focus during Front/Back transitions
    func retainFocusForTransition() {
        focusRetentionTask?.cancel()
        keyboardRetainTask?.cancel()
        shouldRetainKeyboard = true
    }
    
    /// Releases focus retention after transition
    func releaseFocusAfterTransition() {
        focusRetentionTask?.cancel()
        focusRetentionTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.releaseKeyboardRetention(afterDelay: 0.05)
            }
        }
    }
}

// MARK: - Focused Zone Info

/// Information about the currently focused zone
struct FocusedZoneInfo: Equatable {
    let zoneID: UUID
    let lineIndex: Int
    let totalLines: Int
    
    var canSplit: Bool { totalLines >= 2 }
}

// MARK: - Zone Line Tracker

/// Tracks which line within a zone has focus
@Observable
@MainActor
final class ZoneLineTracker {
    static let shared = ZoneLineTracker()
    
    /// Maps zone ID to focused line index
    private var focusedLines: [UUID: Int] = [:]
    
    /// Maps zone ID to total line count
    private var lineCounts: [UUID: Int] = [:]
    
    /// Updates focused line for a zone
    func updateFocusedLine(for zoneID: UUID, lineIndex: Int, totalLines: Int? = nil) {
        focusedLines[zoneID] = lineIndex
        if let totalLines = totalLines {
            lineCounts[zoneID] = totalLines
        }
    }
    
    /// Gets focused line for a zone
    func focusedLine(for zoneID: UUID) -> Int? {
        focusedLines[zoneID]
    }
    
    /// Gets total lines for a zone
    func lineCount(for zoneID: UUID) -> Int? {
        lineCounts[zoneID]
    }
    
    /// Returns true if zone can be split
    func canSplitZone(zoneID: UUID) -> Bool {
        guard let count = lineCounts[zoneID] else { return false }
        return count >= 2
    }
    
    /// Clears focused line for a zone
    func clearFocusedLine(for zoneID: UUID) {
        focusedLines.removeValue(forKey: zoneID)
    }
    
    /// Clears all tracked lines
    func clearAll() {
        focusedLines.removeAll()
        lineCounts.removeAll()
    }
}

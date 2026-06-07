//
//  ZoneFocusManager.swift
//  QuizFlash
//
//  Manages focus state and keyboard retention for zone editor.
//  Works in conjunction with ZoneController.
//

import SwiftUI
import UIKit

// MARK: - Focus Notifications

extension Notification.Name {
    static let focusNewZone = Notification.Name("focusNewZone")
    static let scrollToCursor = Notification.Name("scrollToCursor")
    static let zoneFocusRequest = Notification.Name("zoneFocusRequest")
    static let focusZoneTextView = Notification.Name("focusZoneTextView")
    static let zoneEditorCaretMoved = Notification.Name("zoneEditorCaretMoved")
    static let zoneEditorZoneTapped = Notification.Name("zoneEditorZoneTapped")
    static let zoneEditorWillFocusTextView = Notification.Name("zoneEditorWillFocusTextView")
    static let zoneEditorInsertForcedLineBreak = Notification.Name("zoneEditorInsertForcedLineBreak")
}

enum ZoneEditorCaretScrollNotification {
    static let pathIDKey = "pathID"
    static let anchorYKey = "anchorY"
    static let caretRectInWindowKey = "caretRectInWindow"
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
        ZoneEditorDebugStore.shared.recordFocusEvent("manager requestFocus", zoneID: zoneID)
        reportDebugState()
        
        // Post notification for UIKit components
        NotificationCenter.default.post(
            name: .zoneFocusRequest,
            object: zoneID
        )
        
        // Also post focus notification
        focusNotificationTask?.cancel()
        focusNotificationTask = Task { @MainActor in
            for delay in [0, 16, 48, 96] {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                guard !Task.isCancelled,
                      self.pendingFocusZoneID == zoneID || self.focusedZoneID == zoneID else {
                    return
                }
                NotificationCenter.default.post(
                    name: .focusZoneTextView,
                    object: zoneID
                )
            }
        }
    }

    /// Completes a pending focus request once UIKit confirms first-responder state.
    func completeFocus(for zoneID: UUID) {
        focusNotificationTask?.cancel()
        focusNotificationTask = nil
        if focusedZoneID != zoneID {
            focusedZoneID = zoneID
        }
        if pendingFocusZoneID == zoneID {
            pendingFocusZoneID = nil
        }
        releaseKeyboardRetention(afterDelay: 0.1)
        ZoneEditorDebugStore.shared.recordFocusEvent("manager completeFocus", zoneID: zoneID)
        reportDebugState()
    }
    
    /// Clears pending focus after successful focus
    func clearPendingFocus() {
        pendingFocusZoneID = nil
        releaseKeyboardRetention()
        ZoneEditorDebugStore.shared.recordFocusEvent("manager clearPending", zoneID: focusedZoneID)
        reportDebugState()
    }

    /// Updates the currently focused zone
    func updateFocusedZone(_ zoneID: UUID?) {
        guard focusedZoneID != zoneID else { return }
        focusedZoneID = zoneID
        ZoneEditorDebugStore.shared.recordFocusEvent("manager updateFocused", zoneID: zoneID)
        reportDebugState()
    }
    
    // MARK: - Keyboard Retention
    
    /// Prepares for zone insertion - retains keyboard
    func prepareForZoneInsertion() {
        keyboardRetainTask?.cancel()
        shouldRetainKeyboard = true
        reportDebugState()
    }
    
    /// Releases keyboard retention after a delay
    func releaseKeyboardRetention(afterDelay delay: Double = 0.12) {
        keyboardRetainTask?.cancel()
        keyboardRetainTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.shouldRetainKeyboard = false
                self.reportDebugState()
            }
        }
    }
    
    /// Force releases keyboard immediately
    func forceReleaseKeyboard() {
        focusNotificationTask?.cancel()
        keyboardRetainTask?.cancel()
        pendingFocusZoneID = nil
        focusedZoneID = nil
        shouldRetainKeyboard = false
        ZoneEditorDebugStore.shared.recordFocusEvent("manager forceRelease", zoneID: nil)
        reportDebugState()
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
    
    // MARK: - Focus Retention for Transitions
    
    /// Retains focus during Front/Back transitions
    func retainFocusForTransition() {
        focusRetentionTask?.cancel()
        keyboardRetainTask?.cancel()
        shouldRetainKeyboard = true
        reportDebugState()
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

    private func reportDebugState() {
        ZoneEditorDebugStore.shared.updateFocusManager(
            focusedZoneID: focusedZoneID,
            pendingZoneID: pendingFocusZoneID,
            retainKeyboard: shouldRetainKeyboard
        )
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
        if focusedLines[zoneID] == lineIndex,
           totalLines == nil || lineCounts[zoneID] == totalLines {
            return
        }

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

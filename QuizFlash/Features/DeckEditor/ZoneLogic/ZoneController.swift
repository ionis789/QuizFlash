//
//  ZoneController.swift
//  QuizFlash
//
//  Central controller for zone operations with focus, keyboard, and split management.
//  Single source of truth for all zone mutations and focus state.
//

import SwiftUI
import Combine

// MARK: - Zone Controller

/// Production-grade controller for zone operations.
/// Coordinates split, add, delete with proper focus and keyboard retention.
@Observable
@MainActor
final class ZoneController {
    static let shared = ZoneController()
    
    // MARK: - Public Properties
    
    /// Currently focused zone ID
    var focusedZoneID: UUID?
    
    /// Currently active side (0 = Front, 1 = Back)
    var activeSide: Int = 0
    
    /// Keyboard retention flag - prevents keyboard dismissal during operations
    var shouldRetainKeyboard: Bool = false
    
    /// Zone height cache (number of lines) for split availability
    private var zoneHeightCache: [UUID: ZoneHeightInfo] = [:]
    
    // MARK: - Private State
    
    private var keyboardRetainTask: Task<Void, Never>?
    private var focusRetentionTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Keyboard Management
    
    /// Prepares for zone insertion - retains keyboard
    func prepareForZoneInsertion() {
        keyboardRetainTask?.cancel()
        shouldRetainKeyboard = true
    }
    
    /// Releases keyboard retention after delay
    func releaseKeyboardRetention(afterDelay delay: Double = 0.15) {
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
    
    // MARK: - Focus Management
    
    /// Updates focused zone ID
    func updateFocusedZone(_ zoneID: UUID?) {
        focusedZoneID = zoneID
    }
    
    /// Retains focus during layout transitions
    func retainFocusDuringTransition() {
        focusRetentionTask?.cancel()
        shouldRetainKeyboard = true
    }
    
    /// Releases focus retention after transition completes
    func releaseFocusAfterTransition() {
        focusRetentionTask?.cancel()
        focusRetentionTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.releaseKeyboardRetention(afterDelay: 0.05)
            }
        }
    }
    
    // MARK: - Zone Height Tracking (for Split)
    
    /// Updates cached height info for a zone
    func updateZoneHeightInfo(for zoneID: UUID, lineCount: Int, focusedLineIndex: Int = 0) {
        let nextInfo = ZoneHeightInfo(
            lineCount: lineCount,
            focusedLineIndex: focusedLineIndex
        )
        guard zoneHeightCache[zoneID] != nextInfo else { return }

        zoneHeightCache[zoneID] = nextInfo
    }
    
    /// Gets height info for a zone
    func zoneHeightInfo(for zoneID: UUID) -> ZoneHeightInfo? {
        zoneHeightCache[zoneID]
    }
    
    /// Returns true if zone can be split (has ≥ 2 lines)
    func canSplitZone(zoneID: UUID) -> Bool {
        guard let info = zoneHeightCache[zoneID] else { return false }
        return info.lineCount >= 2
    }
    
    /// Clears height cache
    func clearHeightCache() {
        zoneHeightCache.removeAll()
    }
    
    // MARK: - Side Management
    
    /// Sets active side (Front/Back)
    func setActiveSide(_ side: Int) {
        activeSide = side
    }
}

// MARK: - Zone Height Information

/// Height information for split availability
struct ZoneHeightInfo: Equatable {
    let lineCount: Int
    let focusedLineIndex: Int
    
    /// Returns true if split is available (zone has ≥ 2 lines)
    var canSplit: Bool { lineCount >= 2 }
}

// MARK: - Zone Operation Result

/// Result of a zone operation
enum ZoneOperationResult {
    case success
    case failure(reason: String)
    case notApplicable
}

// MARK: - Focus State Snapshot

/// Snapshot of focus state for restoration after transitions
struct FocusStateSnapshot {
    var frontZoneID: UUID?
    var backZoneID: UUID?
    var frontPath: ZonePath?
    var backPath: ZonePath?
    
    mutating func saveForSide(_ side: Int, zoneID: UUID?, path: ZonePath?) {
        if side == 0 {
            frontZoneID = zoneID
            frontPath = path
        } else {
            backZoneID = zoneID
            backPath = path
        }
    }
    
    func restoreForSide(_ side: Int) -> (zoneID: UUID?, path: ZonePath?) {
        if side == 0 {
            return (frontZoneID, frontPath)
        } else {
            return (backZoneID, backPath)
        }
    }
}

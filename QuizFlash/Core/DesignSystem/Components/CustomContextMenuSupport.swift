//
//  CustomContextMenuSupport.swift
//  QuizFlash
//
//  Shared models, config, and debug helpers for the custom context-menu system.
//

import SwiftUI
import OSLog

enum CustomContextMenuLog {
    static let logger = QuizFlashLog.make("CustomContextMenu")

    static func debug(_ message: String) {
#if DEBUG
        logger.debug("\(message, privacy: .public)")
#endif
    }
}

// MARK: - Action Model

/// Semantic role for one custom context-menu action.
enum CustomContextMenuActionRole {
    case normal
    case destructive
}

/// One row rendered inside the custom context-menu card.
struct CustomContextMenuAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let role: CustomContextMenuActionRole
    let action: @MainActor @Sendable () -> Void
}

/// One non-interactive detail row rendered inside the context-menu card above actions.
struct CustomContextMenuInfoRow: Identifiable, Hashable {
    let label: String
    let value: String

    var id: String {
        "\(label)|\(value)"
    }
}

// MARK: - Config

/// Visual and interaction tuning for the reusable custom context-menu system.
struct CustomContextMenuConfig {
    var longPressDuration: Double = 0.35
    var pressIntentDelay: Double = 0.2
    var pressIntentMovementTolerance: CGFloat = 2.5
    var allowableMovement: CGFloat = 14
    var menuGap: CGFloat = 16
    var horizontalPadding: CGFloat = 12
    var bottomPadding: CGFloat = 12
    var bottomReservedSpace: CGFloat = UIConstants.Size.bottomChromeBarHeight
        + UIConstants.Layout.bottomChromeBottomPadding
        + UIConstants.Layout.bottomChromeVisualBottomOffset
        + 16
    var pressScale: CGFloat = 0.95
    var liftOvershootScale: CGFloat = 1
    var finalPreviewScale: CGFloat = 1
    var backgroundDimOpacity: Double = 0.4
    var backdropMaterialMaxOpacity: Double = 1
    var menuInitialScale: CGFloat = 0.93
    var menuInitialOffsetY: CGFloat = 12
    var menuRevealDelay: Double = 0.065
    var rowStagger: Double = 0.032
    var menuCornerRadius: CGFloat = 32
    var isLoggingEnabled = false
    var estimatedMenuSize: CGSize? = nil
}

extension CustomContextMenuConfig {
    static var deckGridCardMenu: CustomContextMenuConfig {
        var config = CustomContextMenuConfig()
        config.estimatedMenuSize = CGSize(width: 255, height: 270)
        return config
    }
}

enum CustomContextMenuPhase: Equatable {
    case idle
    case pressing
    case lifting
    case expanded
    case dismissing
}

@MainActor
enum CustomContextMenuDebugConsole {
    private static var nextInteractionNumber = 0
    private static var activeInteractionNumber: Int?
    private static var activeSourceID: String?
    private static var timelineStart: Date?

    static func beginIfNeeded(enabled: Bool, sourceID: String) {
        guard enabled else { return }
        guard activeInteractionNumber == nil else { return }

        nextInteractionNumber += 1
        activeInteractionNumber = nextInteractionNumber
        activeSourceID = sourceID
        timelineStart = Date()
        log(enabled: enabled, sourceID: sourceID, event: "InteractionBegin")
    }

    static func log(
        enabled: Bool,
        sourceID: String? = nil,
        event: String,
        details: String = ""
    ) {
        guard enabled else { return }
        guard shouldEmitLog(for: sourceID) else { return }
        let elapsed = timelineStart.map { Date().timeIntervalSince($0) } ?? 0
        let interactionLabel = activeInteractionNumber.map { "#\($0)" } ?? "#-"
        let resolvedSourceID = sourceID ?? activeSourceID ?? "-"
        let suffix = details.isEmpty ? "" : " \(details)"
        CustomContextMenuLog.debug(
            "[CustomContextMenu][Timeline][\(interactionLabel)][+\(String(format: "%.3f", elapsed))s] \(event) sourceID=\(resolvedSourceID)\(suffix)"
        )
    }

    static func end(enabled: Bool, sourceID: String? = nil, reason: String) {
        guard enabled else { return }
        log(
            enabled: enabled,
            sourceID: sourceID,
            event: "InteractionEnd",
            details: "reason=\(reason)"
        )
        activeInteractionNumber = nil
        activeSourceID = nil
        timelineStart = nil
    }

    private static func shouldEmitLog(for sourceID: String?) -> Bool {
        guard let activeSourceID else { return true }
        guard let sourceID else { return true }
        return sourceID == activeSourceID
    }
}

@MainActor
enum CustomContextMenuMenuSizeCache {
    private static var sizes: [String: CGSize] = [:]

    static func key(
        for actions: [CustomContextMenuAction],
        infoRows: [CustomContextMenuInfoRow]
    ) -> String {
        let actionKey = actions.map {
            "\($0.role)|\($0.systemImage)|\($0.title)"
        }
        .joined(separator: "||")

        let infoKey = infoRows.map {
            "\($0.label)|\($0.value)"
        }
        .joined(separator: "||")

        return "\(actionKey)##\(infoKey)"
    }

    static func size(for key: String) -> CGSize? {
        sizes[key]
    }

    static func store(_ size: CGSize, for key: String) {
        guard size != .zero else { return }
        sizes[key] = size
    }
}

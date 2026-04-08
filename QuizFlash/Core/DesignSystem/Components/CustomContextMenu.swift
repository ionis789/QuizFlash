//
//  CustomContextMenu.swift
//  QuizFlash
//
//  Lightweight reusable custom context-menu infrastructure.
//

import SwiftUI
import UIKit

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
    let action: @MainActor () -> Void
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
}

enum CustomContextMenuPhase: Equatable {
    case idle
    case pressing
    case lifting
    case expanded
    case dismissing
}

@MainActor
private enum CustomContextMenuDebugConsole {
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
#if DEBUG
        print(
            "[CustomContextMenu][Timeline][\(interactionLabel)][+\(String(format: "%.3f", elapsed))s] \(event) sourceID=\(resolvedSourceID)\(suffix)"
        )
#endif
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
private enum CustomContextMenuMenuSizeCache {
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

// MARK: - Placement

/// Placement mode chosen for the context menu relative to the source view.
enum CustomContextMenuPlacementMode {
    case anchoredBelowTrailing
    case pushedUpToFitBelowTrailing
    case pushedDownToClearTopSafeArea
    case adjustedBetweenTopAndBottomConstraints
}

/// Resolved geometry for one active menu presentation.
struct CustomContextMenuResolvedLayout {
    let mode: CustomContextMenuPlacementMode
    let menuFrame: CGRect
    let previewOffset: CGSize
    let debug: DebugPayload

    struct DebugPayload {
        let screenBounds: CGRect
        let safeInsets: UIEdgeInsets
        let safeFrame: CGRect
        let menuSize: CGSize
        let anchoredTrailingX: CGFloat
        let bottomLimitWithReserved: CGFloat
        let bottomLimitWithoutReserved: CGFloat
        let topLimit: CGFloat
        let idealPreviewY: CGFloat
        let idealMenuBottom: CGFloat
        let requiredLiftWithReserved: CGFloat
        let requiredLiftWithoutReserved: CGFloat
        let appliedRequiredLift: CGFloat
        let previewYAfterBottomLift: CGFloat
        let requiredTopPush: CGFloat
        let clampedPreviewOrigin: CGPoint
        let menuOrigin: CGPoint
    }
}

// MARK: - Coordinator

/// Main-actor coordinator that owns the one active custom context-menu presentation.
@MainActor
@Observable
final class CustomContextMenuCoordinator {

    /// Active menu payload rendered by the global host.
    struct Presentation: Identifiable {
        let id = UUID()
        let sourceID: AnyHashable
        let sourceFrame: CGRect
        let preview: AnyView
        let infoRows: [CustomContextMenuInfoRow]
        let actions: [CustomContextMenuAction]
        let menuSize: CGSize
        let config: CustomContextMenuConfig
        let layout: CustomContextMenuResolvedLayout
    }

    /// Input used to resolve geometry and create a presentation payload.
    struct Request {
        let sourceID: AnyHashable
        let sourceFrame: CGRect
        let preview: AnyView
        let infoRows: [CustomContextMenuInfoRow]
        let actions: [CustomContextMenuAction]
        let measuredMenuSize: CGSize
        let config: CustomContextMenuConfig
    }

    var presentation: Presentation?
    var phase: CustomContextMenuPhase = .idle

    @ObservationIgnored
    private var dismissTask: Task<Void, Never>?

    @ObservationIgnored
    private var phaseTask: Task<Void, Never>?

    @ObservationIgnored
    private weak var lockedScrollView: UIScrollView?

    @ObservationIgnored
    private var lockedScrollWasEnabled = false

    func setIsPressing(
        _ isPressing: Bool,
        sourceDescription: String? = nil,
        config: CustomContextMenuConfig? = nil
    ) {
        guard presentation == nil else { return }
        let nextPhase: CustomContextMenuPhase = isPressing ? .pressing : .idle
        if phase != nextPhase {
            CustomContextMenuDebugConsole.log(
                enabled: config?.isLoggingEnabled ?? false,
                sourceID: sourceDescription,
                event: "CoordinatorPhase",
                details: "phase=\(nextPhase)"
            )
        }
        phase = nextPhase
    }

    /// Presents a new context menu and animates it into place.
    func present(_ request: Request) {
        guard request.sourceFrame != .zero else { return }
        guard !request.actions.isEmpty else { return }

        dismissTask?.cancel()
        phaseTask?.cancel()

        let sourceDescription = String(describing: request.sourceID)

        let layout = Self.resolveLayout(
            sourceFrame: request.sourceFrame,
            measuredMenuSize: request.measuredMenuSize,
            config: request.config
        )

        CustomContextMenuDebugConsole.log(
            enabled: request.config.isLoggingEnabled,
            sourceID: sourceDescription,
            event: "CoordinatorPresentRequested",
            details: "actionsCount=\(request.actions.count) menuSize=(w:\(Self.fmt(request.measuredMenuSize.width)), h:\(Self.fmt(request.measuredMenuSize.height)))"
        )
        Self.logPresentationDebug(request: request, layout: layout)
        Self.emitRevealHaptic()

        presentation = Presentation(
            sourceID: request.sourceID,
            sourceFrame: request.sourceFrame,
            preview: request.preview,
            infoRows: request.infoRows,
            actions: request.actions,
            menuSize: request.measuredMenuSize,
            config: request.config,
            layout: layout
        )

        phase = .lifting
        CustomContextMenuDebugConsole.log(
            enabled: request.config.isLoggingEnabled,
            sourceID: sourceDescription,
            event: "CoordinatorPhase",
            details: "phase=\(phase)"
        )

        let presentationID = presentation?.id
        phaseTask = Task { @MainActor in
            try? await Task.sleep(
                for: .seconds(request.config.menuRevealDelay + 0.28)
            )
            guard !Task.isCancelled else { return }
            guard presentation?.id == presentationID else { return }
            phase = .expanded
            CustomContextMenuDebugConsole.log(
                enabled: request.config.isLoggingEnabled,
                sourceID: sourceDescription,
                event: "CoordinatorPhase",
                details: "phase=\(phase)"
            )
        }
    }

    func lockScrollInteraction(
        on scrollView: UIScrollView?,
        sourceDescription: String? = nil,
        config: CustomContextMenuConfig? = nil
    ) {
        guard let scrollView else { return }
        guard lockedScrollView !== scrollView else { return }

        unlockScrollInteraction(sourceDescription: sourceDescription, config: config)
        lockedScrollView = scrollView
        lockedScrollWasEnabled = scrollView.isScrollEnabled
        scrollView.isScrollEnabled = false

        CustomContextMenuDebugConsole.log(
            enabled: config?.isLoggingEnabled ?? false,
            sourceID: sourceDescription,
            event: "ScrollLocked"
        )
    }

    func unlockScrollInteraction(
        sourceDescription: String? = nil,
        config: CustomContextMenuConfig? = nil
    ) {
        guard let lockedScrollView else { return }

        lockedScrollView.isScrollEnabled = lockedScrollWasEnabled
        self.lockedScrollView = nil
        lockedScrollWasEnabled = false

        CustomContextMenuDebugConsole.log(
            enabled: config?.isLoggingEnabled ?? false,
            sourceID: sourceDescription,
            event: "ScrollUnlocked"
        )
    }

    /// Dismisses the active context menu with the shared spring and clears it afterwards.
    func dismiss() {
        dismiss(after: nil)
    }

    /// Dismisses the active menu and then executes one action after the reverse animation.
    func performAction(_ action: @escaping @MainActor () -> Void) {
        dismiss(after: action)
    }

    /// Returns true while the given source view should remain visually hidden in-place.
    func isSourceHidden<ID: Hashable>(_ id: ID) -> Bool {
        presentation?.sourceID == AnyHashable(id)
    }

    private func dismiss(after action: (@MainActor () -> Void)?) {
        guard let currentPresentation = presentation else { return }

        dismissTask?.cancel()
        phaseTask?.cancel()

        let presentationID = currentPresentation.id
        let sourceDescription = String(describing: currentPresentation.sourceID)
        let loggingEnabled = currentPresentation.config.isLoggingEnabled
        CustomContextMenuDebugConsole.log(
            enabled: loggingEnabled,
            sourceID: sourceDescription,
            event: "CoordinatorDismissRequested",
            details: "hasPendingAction=\(action != nil)"
        )
        phase = .dismissing
        CustomContextMenuDebugConsole.log(
            enabled: loggingEnabled,
            sourceID: sourceDescription,
            event: "CoordinatorPhase",
            details: "phase=\(phase)"
        )

        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            guard presentation?.id == presentationID else { return }
            let pendingAction = action
            unlockScrollInteraction(
                sourceDescription: sourceDescription,
                config: currentPresentation.config
            )
            presentation = nil
            phase = .idle
            CustomContextMenuDebugConsole.log(
                enabled: loggingEnabled,
                sourceID: sourceDescription,
                event: "CoordinatorPhase",
                details: "phase=\(phase)"
            )
            CustomContextMenuDebugConsole.log(
                enabled: loggingEnabled,
                sourceID: sourceDescription,
                event: "CoordinatorPresentationCleared"
            )
            CustomContextMenuDebugConsole.end(
                enabled: loggingEnabled,
                sourceID: sourceDescription,
                reason: pendingAction == nil ? "dismissCompleted" : "dismissCompletedAfterAction"
            )
            pendingAction?()
        }
    }

    private static func resolveLayout(
        sourceFrame: CGRect,
        measuredMenuSize: CGSize,
        config: CustomContextMenuConfig
    ) -> CustomContextMenuResolvedLayout {
        let windowBounds = currentWindowBounds()
        let safeInsets = currentSafeAreaInsets()
        let safeFrame = windowBounds.inset(by: safeInsets)
        let menuSize = measuredMenuSize == .zero ? CGSize(width: 255, height: 234) : measuredMenuSize

        let anchoredTrailingX = min(
            max(safeFrame.minX + config.horizontalPadding, sourceFrame.maxX - menuSize.width),
            safeFrame.maxX - menuSize.width - config.horizontalPadding
        )

        let bottomLimitWithReserved = safeFrame.maxY - config.bottomReservedSpace
        let bottomLimitWithoutReserved = safeFrame.maxY - config.bottomPadding
        let topLimit = safeFrame.minY
        let idealPreviewY = sourceFrame.minY
        let idealMenuBottom = sourceFrame.maxY + config.menuGap + menuSize.height
        let requiredLiftWithReserved = max(0, idealMenuBottom - bottomLimitWithReserved)
        let requiredLiftWithoutReserved = max(0, idealMenuBottom - bottomLimitWithoutReserved)
        let unconstrainedLift = requiredLiftWithoutReserved
        let maxLiftBeforeTopCollision = max(0, sourceFrame.minY - safeFrame.minY)
        let appliedRequiredLift = min(unconstrainedLift, maxLiftBeforeTopCollision)
        let previewYAfterBottomLift = idealPreviewY - appliedRequiredLift
        let requiredTopPush = max(0, topLimit - previewYAfterBottomLift)

        let clampedPreviewOrigin = CGPoint(
            x: sourceFrame.minX,
            y: previewYAfterBottomLift + requiredTopPush
        )

        let menuOrigin = CGPoint(
            x: anchoredTrailingX,
            y: clampedPreviewOrigin.y + sourceFrame.height + config.menuGap
        )

        let mode: CustomContextMenuPlacementMode
        if appliedRequiredLift > 0, requiredTopPush > 0 {
            mode = .adjustedBetweenTopAndBottomConstraints
        } else if appliedRequiredLift > 0 {
            mode = .pushedUpToFitBelowTrailing
        } else if requiredTopPush > 0 {
            mode = .pushedDownToClearTopSafeArea
        } else {
            mode = .anchoredBelowTrailing
        }

        return CustomContextMenuResolvedLayout(
            mode: mode,
            menuFrame: CGRect(origin: menuOrigin, size: menuSize),
            previewOffset: CGSize(
                width: clampedPreviewOrigin.x - sourceFrame.minX,
                height: clampedPreviewOrigin.y - sourceFrame.minY
            ),
            debug: .init(
                screenBounds: windowBounds,
                safeInsets: safeInsets,
                safeFrame: safeFrame,
                menuSize: menuSize,
                anchoredTrailingX: anchoredTrailingX,
                bottomLimitWithReserved: bottomLimitWithReserved,
                bottomLimitWithoutReserved: bottomLimitWithoutReserved,
                topLimit: topLimit,
                idealPreviewY: idealPreviewY,
                idealMenuBottom: idealMenuBottom,
                requiredLiftWithReserved: requiredLiftWithReserved,
                requiredLiftWithoutReserved: requiredLiftWithoutReserved,
                appliedRequiredLift: appliedRequiredLift,
                previewYAfterBottomLift: previewYAfterBottomLift,
                requiredTopPush: requiredTopPush,
                clampedPreviewOrigin: clampedPreviewOrigin,
                menuOrigin: menuOrigin
            )
        )
    }

    private static func logPresentationDebug(
        request: Request,
        layout: CustomContextMenuResolvedLayout
    ) {
        guard request.config.isLoggingEnabled else { return }
        let d = layout.debug
        let previewFrame = CGRect(origin: d.clampedPreviewOrigin, size: request.sourceFrame.size)
        let message = """
[CustomContextMenu][LayoutDebug]
sourceFrame=(x:\(fmt(request.sourceFrame.minX)), y:\(fmt(request.sourceFrame.minY)), w:\(fmt(request.sourceFrame.width)), h:\(fmt(request.sourceFrame.height)))
screen=(w:\(fmt(d.screenBounds.width)), h:\(fmt(d.screenBounds.height)))
safeInsets=(top:\(fmt(d.safeInsets.top)), left:\(fmt(d.safeInsets.left)), bottom:\(fmt(d.safeInsets.bottom)), right:\(fmt(d.safeInsets.right)))
safeFrame=(x:\(fmt(d.safeFrame.minX)), y:\(fmt(d.safeFrame.minY)), w:\(fmt(d.safeFrame.width)), h:\(fmt(d.safeFrame.height)))
menuSize=(w:\(fmt(d.menuSize.width)), h:\(fmt(d.menuSize.height)))
anchoredTrailingX=\(fmt(d.anchoredTrailingX))
bottomLimitWithReserved=\(fmt(d.bottomLimitWithReserved))
bottomLimitWithoutReserved=\(fmt(d.bottomLimitWithoutReserved))
topLimit=\(fmt(d.topLimit))
idealPreviewY=\(fmt(d.idealPreviewY))
idealMenuBottom=\(fmt(d.idealMenuBottom))
requiredLiftWithReserved=\(fmt(d.requiredLiftWithReserved))
requiredLiftWithoutReserved=\(fmt(d.requiredLiftWithoutReserved))
appliedRequiredLift=\(fmt(d.appliedRequiredLift))
previewYAfterBottomLift=\(fmt(d.previewYAfterBottomLift))
requiredTopPush=\(fmt(d.requiredTopPush))
resolvedMode=\(layout.mode)
previewOrigin=(x:\(fmt(d.clampedPreviewOrigin.x)), y:\(fmt(d.clampedPreviewOrigin.y)))
previewFrame=(x:\(fmt(previewFrame.minX)), y:\(fmt(previewFrame.minY)), w:\(fmt(previewFrame.width)), h:\(fmt(previewFrame.height)))
previewOffset=(dx:\(fmt(layout.previewOffset.width)), dy:\(fmt(layout.previewOffset.height)))
menuOrigin=(x:\(fmt(d.menuOrigin.x)), y:\(fmt(d.menuOrigin.y)))
menuFrame=(x:\(fmt(layout.menuFrame.minX)), y:\(fmt(layout.menuFrame.minY)), w:\(fmt(layout.menuFrame.width)), h:\(fmt(layout.menuFrame.height)))
"""
        debugLog(message)
    }

    private static func fmt(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private static func currentWindowBounds() -> CGRect {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .bounds ?? UIScreen.main.bounds
    }

    private static func currentSafeAreaInsets() -> UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }

    private static func emitRevealHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 1)
    }

    private static func debugLog(_ message: String) {
#if DEBUG
        print(message)
#endif
    }
}

// MARK: - Source Registry

/// Central registry for all visible custom-context-menu sources.
@MainActor
@Observable
final class CustomContextMenuSourceRegistry {

    final class SourceRecord {
        let id: AnyHashable
        let sourceDescription: String
        weak var anchorView: UIView?
        var isEnabled: Bool
        var config: CustomContextMenuConfig
        let setPressing: @MainActor (Bool) -> Void
        let activate: @MainActor (CGRect) -> Void

        init(
            id: AnyHashable,
            sourceDescription: String,
            anchorView: UIView,
            isEnabled: Bool,
            config: CustomContextMenuConfig,
            setPressing: @escaping @MainActor (Bool) -> Void,
            activate: @escaping @MainActor (CGRect) -> Void
        ) {
            self.id = id
            self.sourceDescription = sourceDescription
            self.anchorView = anchorView
            self.isEnabled = isEnabled
            self.config = config
            self.setPressing = setPressing
            self.activate = activate
        }
    }

    struct ResolvedSource {
        let id: AnyHashable
        let sourceDescription: String
        let frame: CGRect
        let config: CustomContextMenuConfig
        let scrollView: UIScrollView?
    }

    @ObservationIgnored
    private var sources: [AnyHashable: SourceRecord] = [:]

    func registerOrUpdate(
        id: AnyHashable,
        sourceDescription: String,
        anchorView: UIView,
        isEnabled: Bool,
        config: CustomContextMenuConfig,
        setPressing: @escaping @MainActor (Bool) -> Void,
        activate: @escaping @MainActor (CGRect) -> Void
    ) {
        cleanupStaleSources()
        sources[id] = SourceRecord(
            id: id,
            sourceDescription: sourceDescription,
            anchorView: anchorView,
            isEnabled: isEnabled,
            config: config,
            setPressing: setPressing,
            activate: activate
        )
    }

    func unregister(id: AnyHashable) {
        sources.removeValue(forKey: id)
    }

    func setPressing(_ isPressing: Bool, for id: AnyHashable) {
        cleanupStaleSources()
        sources[id]?.setPressing(isPressing)
    }

    func activateSource(_ id: AnyHashable, sourceFrame: CGRect) {
        cleanupStaleSources()
        sources[id]?.activate(sourceFrame)
    }

    func currentFrame(for id: AnyHashable) -> CGRect? {
        cleanupStaleSources()
        guard let anchorView = sources[id]?.anchorView else { return nil }
        let frame = anchorView.convert(anchorView.bounds, to: nil)
        return frame == .zero ? nil : frame
    }

    func resolvedSource(at pointInWindow: CGPoint) -> ResolvedSource? {
        cleanupStaleSources()

        var bestMatch: ResolvedSource?
        var smallestArea = CGFloat.greatestFiniteMagnitude

        for record in sources.values {
            guard record.isEnabled else { continue }
            guard let anchorView = record.anchorView else { continue }
            guard anchorView.window != nil else { continue }
            guard !anchorView.isHidden else { continue }
            guard anchorView.alpha > 0.01 else { continue }

            let frame = anchorView.convert(anchorView.bounds, to: nil)
            guard frame != .zero else { continue }
            guard frame.insetBy(dx: -2, dy: -2).contains(pointInWindow) else { continue }

            let area = frame.width * frame.height
            if area < smallestArea {
                smallestArea = area
                bestMatch = ResolvedSource(
                    id: record.id,
                    sourceDescription: record.sourceDescription,
                    frame: frame,
                    config: record.config,
                    scrollView: nearestScrollView(from: anchorView)
                )
            }
        }

        return bestMatch
    }

    private func cleanupStaleSources() {
        sources = sources.filter { _, record in
            record.anchorView != nil
        }
    }

    private func nearestScrollView(from view: UIView) -> UIScrollView? {
        var current: UIView? = view
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView {
                return scrollView
            }
            current = candidate.superview
        }
        return nil
    }
}

// MARK: - Host

/// Global overlay host that renders the active preview, background, and action card.
struct CustomContextMenuHost: View {
    @Environment(CustomContextMenuCoordinator.self) private var coordinator
    @Environment(CustomContextMenuSourceRegistry.self) private var sourceRegistry

    var body: some View {
        ZStack {
            CustomContextMenuTouchTrackerAttachment(
                sourceRegistry: sourceRegistry,
                menuCoordinator: coordinator
            )
            .allowsHitTesting(false)

            if let presentation = coordinator.presentation {
                CustomContextMenuOverlay(
                    presentation: presentation,
                    phase: coordinator.phase,
                    onDismiss: {
                        CustomContextMenuDebugConsole.log(
                            enabled: presentation.config.isLoggingEnabled,
                            sourceID: String(describing: presentation.sourceID),
                            event: "DismissBackgroundTap"
                        )
                        if presentation.config.isLoggingEnabled {
#if DEBUG
                            print("[CustomContextMenu][Dismiss] reason=backgroundTap")
#endif
                        }
                        coordinator.dismiss()
                    },
                    onSelect: { action in
                        coordinator.performAction(action.action)
                    }
                )
                .zIndex(100)
                .transition(.identity)
            }
        }
    }
}

private struct CustomContextMenuOverlay: View {
    let presentation: CustomContextMenuCoordinator.Presentation
    let phase: CustomContextMenuPhase
    let onDismiss: () -> Void
    let onSelect: (CustomContextMenuAction) -> Void

    @State private var backdropMaterialOpacity = 0.0
    @State private var backdropWashOpacity = 0.0
    @State private var previewScale: CGFloat = 1
    @State private var previewOffset: CGSize = .zero
    @State private var menuOpacity = 0.0
    @State private var menuScale: CGFloat = 1
    @State private var revealedActionIDs: Set<UUID> = []
    @State private var liftTask: Task<Void, Never>?
    
    private var sourceDescription: String {
        String(describing: presentation.sourceID)
    }

    private var menuRevealInitialScale: CGFloat {
        min(presentation.config.menuInitialScale, 0.16)
    }

    private var resolvedPreviewFrame: CGRect {
        presentation.sourceFrame.offsetBy(
            dx: presentation.layout.previewOffset.width,
            dy: presentation.layout.previewOffset.height
        )
    }

    private var menuRevealAnchor: UnitPoint {
        let menuFrame = presentation.layout.menuFrame
        let previewFrame = resolvedPreviewFrame
        let overlapMinX = max(menuFrame.minX, previewFrame.minX)
        let overlapMaxX = min(menuFrame.maxX, previewFrame.maxX)
        let overlapCenterX: CGFloat

        if overlapMaxX > overlapMinX {
            overlapCenterX = (overlapMinX + overlapMaxX) * 0.5
        } else {
            overlapCenterX = min(
                max(previewFrame.midX, menuFrame.minX),
                menuFrame.maxX
            )
        }

        let anchorX = min(
            max((overlapCenterX - menuFrame.minX) / max(menuFrame.width, 1), 0),
            1
        )

        return UnitPoint(x: anchorX, y: 0)
    }

    private var previewPushAnimation: Animation {
        let previewOffset = presentation.layout.previewOffset
        let hasPositionPush = abs(previewOffset.width) > 0.5 || abs(previewOffset.height) > 0.5
        return hasPositionPush ? .contextMenuPreviewPushSpring : .contextMenuLiftSpring
    }

    var body: some View {
        GeometryReader { proxy in
            let hostFrame = proxy.frame(in: .global)
            let localSourceFrame = CGRect(
                x: presentation.sourceFrame.minX - hostFrame.minX,
                y: presentation.sourceFrame.minY - hostFrame.minY,
                width: presentation.sourceFrame.width,
                height: presentation.sourceFrame.height
            )
            let localMenuFrame = CGRect(
                x: presentation.layout.menuFrame.minX - hostFrame.minX,
                y: presentation.layout.menuFrame.minY - hostFrame.minY,
                width: presentation.layout.menuFrame.width,
                height: presentation.layout.menuFrame.height
            )

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .opacity(backdropMaterialOpacity)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                Rectangle()
                    .fill(Color.black)
                    .ignoresSafeArea()
                    .opacity(presentation.config.backgroundDimOpacity * backdropWashOpacity)
                    .allowsHitTesting(false)

                presentation.preview
                    .frame(
                        width: localSourceFrame.width,
                        height: localSourceFrame.height,
                        alignment: .topLeading
                    )
                    .compositingGroup()
                    .scaleEffect(previewScale, anchor: .topLeading)
                    .position(
                        x: localSourceFrame.midX,
                        y: localSourceFrame.midY
                    )
                    .offset(
                        x: previewOffset.width,
                        y: previewOffset.height
                    )
                    .allowsHitTesting(false)

                CustomContextMenuMenuCard(
                    infoRows: presentation.infoRows,
                    actions: presentation.actions,
                    cornerRadius: presentation.config.menuCornerRadius,
                    revealedActionIDs: revealedActionIDs,
                    isInteractive: phase == .expanded
                    ,
                    showsChrome: true
                ) { action in
                    onSelect(action)
                }
                .fixedSize(horizontal: true, vertical: true)
                .frame(
                    width: localMenuFrame.width,
                    height: localMenuFrame.height,
                    alignment: .topLeading
                )
                .opacity(menuOpacity)
                .scaleEffect(menuScale, anchor: menuRevealAnchor)
                .offset(
                    x: localMenuFrame.minX,
                    y: localMenuFrame.minY
                )
                .allowsHitTesting(phase == .expanded)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            prepareInitialState()
            logTimeline("OverlayAppear", details: "phase=\(phase)")
            update(for: phase)
        }
        .onChange(of: phase) { _, newPhase in
            logTimeline("OverlayPhaseObserved", details: "phase=\(newPhase)")
            update(for: newPhase)
        }
        .onDisappear {
            logTimeline("OverlayDisappear")
            cancelAnimationTasks()
        }
    }

    private func prepareInitialState() {
        backdropMaterialOpacity = 0
        backdropWashOpacity = 0
        previewScale = presentation.config.pressScale
        previewOffset = .zero
        menuOpacity = 0
        menuScale = menuRevealInitialScale
        revealedActionIDs = []
    }

    private func update(for phase: CustomContextMenuPhase) {
        switch phase {
        case .idle, .pressing:
            break
        case .lifting:
            runLiftSequence()
        case .expanded:
            break
        case .dismissing:
            runDismissSequence()
        }
    }

    private func runLiftSequence() {
        cancelAnimationTasks()
        prepareInitialState()
        logTimeline(
            "LiftSequenceStart",
            details: "previewScaleFrom=\(fmt(presentation.config.pressScale)) previewScaleTo=\(fmt(presentation.config.finalPreviewScale)) previewOffset=(dx:\(fmt(presentation.layout.previewOffset.width)), dy:\(fmt(presentation.layout.previewOffset.height)))"
        )

        withAnimation(.easeOut(duration: 0.08)) {
            backdropMaterialOpacity = presentation.config.backdropMaterialMaxOpacity * 0.34
            backdropWashOpacity = 0.22
        }

        withAnimation(.contextMenuPreviewScaleBackSpring) {
            previewScale = presentation.config.finalPreviewScale
        }

        withAnimation(previewPushAnimation) {
            previewOffset = presentation.layout.previewOffset
        }

        liftTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(54))
            guard !Task.isCancelled else { return }
            logTimeline("BackdropIntensifyStart")

            withAnimation(.easeOut(duration: 0.14)) {
                backdropMaterialOpacity = presentation.config.backdropMaterialMaxOpacity
                backdropWashOpacity = 1
            }

            try? await Task.sleep(for: .seconds(presentation.config.menuRevealDelay))
            guard !Task.isCancelled else { return }
            logTimeline(
                "MenuRevealStart",
                details: "delay=\(String(format: "%.3f", presentation.config.menuRevealDelay)) anchorX=\(fmt(menuRevealAnchor.x))"
            )

            logTimeline(
                "MenuActionsRevealAll",
                details: "count=\(presentation.actions.count)"
            )

            withAnimation(.contextMenuMenuPopSpring) {
                menuOpacity = 1
                menuScale = 1
                revealedActionIDs = Set(presentation.actions.map(\.id))
            }
        }
    }

    private func runDismissSequence() {
        liftTask?.cancel()
        logTimeline(
            "DismissSequenceStart",
            details: "targetScale=\(fmt(menuRevealInitialScale)) anchorX=\(fmt(menuRevealAnchor.x))"
        )

        withAnimation(.contextMenuMenuPopSpring) {
            menuScale = menuRevealInitialScale
        }

        withAnimation(.easeOut(duration: 0.18)) {
            menuOpacity = 0
        }

        withAnimation(.easeOut(duration: 0.18)) {
            backdropMaterialOpacity = 0
            backdropWashOpacity = 0
        }

        withAnimation(previewPushAnimation) {
            previewOffset = .zero
        }
    }

    private func cancelAnimationTasks() {
        liftTask?.cancel()
    }

    private func logTimeline(_ event: String, details: String = "") {
        CustomContextMenuDebugConsole.log(
            enabled: presentation.config.isLoggingEnabled,
            sourceID: sourceDescription,
            event: event,
            details: details
        )
    }

    private func fmt(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}

private struct CustomContextMenuSourceAttachment: UIViewRepresentable {
    let id: AnyHashable
    let sourceDescription: String
    let isEnabled: Bool
    let config: CustomContextMenuConfig
    let sourceRegistry: CustomContextMenuSourceRegistry
    let onPressingChange: @MainActor (Bool) -> Void
    let onActivate: @MainActor (CGRect) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AttachmentView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncRegistration(with: uiView)
    }

    static func dismantleUIView(_ uiView: AttachmentView, coordinator: Coordinator) {
        coordinator.parent.sourceRegistry.unregister(id: coordinator.parent.id)
    }

    final class Coordinator {
        var parent: CustomContextMenuSourceAttachment

        init(parent: CustomContextMenuSourceAttachment) {
            self.parent = parent
        }

        func syncRegistration(with uiView: AttachmentView) {
            parent.sourceRegistry.registerOrUpdate(
                id: parent.id,
                sourceDescription: parent.sourceDescription,
                anchorView: uiView,
                isEnabled: parent.isEnabled,
                config: parent.config,
                setPressing: parent.onPressingChange,
                activate: parent.onActivate
            )
        }
    }

    final class AttachmentView: UIView {}
}

private struct CustomContextMenuTouchTrackerAttachment: UIViewRepresentable {
    let sourceRegistry: CustomContextMenuSourceRegistry
    let menuCoordinator: CustomContextMenuCoordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onWindowChanged = { window in
            context.coordinator.attachRecognizerIfNeeded(to: window)
        }
        return view
    }

    func updateUIView(_ uiView: TrackingView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attachRecognizerIfNeeded(to: uiView.window)
        context.coordinator.updateRecognizer()
    }

    static func dismantleUIView(_ uiView: TrackingView, coordinator: Coordinator) {
        coordinator.detachRecognizer()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CustomContextMenuTouchTrackerAttachment
        weak var attachedView: UIView?
        weak var recognizer: CustomContextMenuGlobalTouchRecognizer?

        init(parent: CustomContextMenuTouchTrackerAttachment) {
            self.parent = parent
        }

        func attachRecognizerIfNeeded(to view: UIView?) {
            guard attachedView !== view else { return }

            detachRecognizer()

            guard let view else { return }

            let recognizer = CustomContextMenuGlobalTouchRecognizer()
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = true
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false

            view.addGestureRecognizer(recognizer)
            attachedView = view
            self.recognizer = recognizer
            updateRecognizer()
        }

        func updateRecognizer() {
            recognizer?.sourceRegistry = parent.sourceRegistry
            recognizer?.menuCoordinator = parent.menuCoordinator
        }

        func detachRecognizer() {
            recognizer?.cancelFromOwner()
            if let recognizer {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            attachedView = nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if otherGestureRecognizer is UIPanGestureRecognizer {
                return true
            }

            let typeName = String(describing: type(of: otherGestureRecognizer))
            return typeName.contains("Scroll")
        }
    }

    final class TrackingView: UIView {
        var onWindowChanged: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChanged?(window)
        }
    }
}

private final class CustomContextMenuGlobalTouchRecognizer: UIGestureRecognizer {
    weak var sourceRegistry: CustomContextMenuSourceRegistry?
    weak var menuCoordinator: CustomContextMenuCoordinator?

    private let scrollCandidateVerticalDistance: CGFloat = 1.5

    private var activeSourceID: AnyHashable?
    private var activeSourceDescription: String?
    private var activeConfig: CustomContextMenuConfig?
    private weak var activeScrollView: UIScrollView?
    private var initialLocationInRecognizerView: CGPoint?
    private var latestLocationInWindow: CGPoint?
    private var didActivateIntent = false
    private var didTrigger = false
    private var intentTask: Task<Void, Never>?
    private var triggerTask: Task<Void, Never>?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible else {
            super.touchesBegan(touches, with: event)
            return
        }

        guard let touch = touches.first, touches.count == 1, let view else {
            state = .failed
            return
        }

        guard let sourceRegistry, let menuCoordinator, menuCoordinator.presentation == nil else {
            state = .failed
            return
        }

        let locationInWindow = touch.location(in: nil)
        guard let resolvedSource = sourceRegistry.resolvedSource(at: locationInWindow) else {
            state = .failed
            return
        }

        activeSourceID = resolvedSource.id
        activeSourceDescription = resolvedSource.sourceDescription
        activeConfig = resolvedSource.config
        activeScrollView = resolvedSource.scrollView
        initialLocationInRecognizerView = touch.location(in: view)
        latestLocationInWindow = locationInWindow

        CustomContextMenuDebugConsole.beginIfNeeded(
            enabled: resolvedSource.config.isLoggingEnabled,
            sourceID: resolvedSource.sourceDescription
        )
        CustomContextMenuDebugConsole.log(
            enabled: resolvedSource.config.isLoggingEnabled,
            sourceID: resolvedSource.sourceDescription,
            event: "TouchDownResolvedSource",
            details: "frame=(x:\(fmt(resolvedSource.frame.minX)), y:\(fmt(resolvedSource.frame.minY)), w:\(fmt(resolvedSource.frame.width)), h:\(fmt(resolvedSource.frame.height)))"
        )
        CustomContextMenuDebugConsole.log(
            enabled: resolvedSource.config.isLoggingEnabled,
            sourceID: resolvedSource.sourceDescription,
            event: "GestureTouchDown",
            details: "intentDelay=\(String(format: "%.3f", resolvedSource.config.pressIntentDelay)) totalTriggerAfter=\(String(format: "%.3f", resolvedSource.config.longPressDuration))"
        )
        CustomContextMenuDebugConsole.log(
            enabled: resolvedSource.config.isLoggingEnabled,
            sourceID: resolvedSource.sourceDescription,
            event: "PressTimerScheduled",
            details: "remainingDuration=\(String(format: "%.3f", max(0, resolvedSource.config.longPressDuration - resolvedSource.config.pressIntentDelay)))"
        )

        scheduleIntent()
        scheduleTrigger()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first,
              let initialLocationInRecognizerView,
              let view,
              let sourceID = activeSourceID,
              let config = activeConfig else {
            super.touchesMoved(touches, with: event)
            return
        }

        let locationInWindow = touch.location(in: nil)
        latestLocationInWindow = locationInWindow

        if !didTrigger, isScrollViewPanning {
            cancelTracking(reason: "scrollViewPanning")
            return
        }

        if !didTrigger,
           let currentFrame = sourceRegistry?.currentFrame(for: sourceID),
           !currentFrame.insetBy(dx: -2, dy: -2).contains(locationInWindow) {
            cancelTracking(reason: "leftSourceFrame")
            return
        }

        let location = touch.location(in: view)
        let distance = hypot(
            location.x - initialLocationInRecognizerView.x,
            location.y - initialLocationInRecognizerView.y
        )
        let horizontalDistance = abs(location.x - initialLocationInRecognizerView.x)
        let verticalDistance = abs(location.y - initialLocationInRecognizerView.y)

        if !didActivateIntent,
           activeScrollView != nil,
           verticalDistance > scrollCandidateVerticalDistance,
           verticalDistance > horizontalDistance {
            cancelTracking(
                reason: "scrollCandidate verticalDistance=\(String(format: "%.1f", verticalDistance))"
            )
            return
        }

        if !didActivateIntent, distance > config.pressIntentMovementTolerance {
            cancelTracking(reason: "movementExceededIntent distance=\(String(format: "%.1f", distance))")
            return
        }

        if !didTrigger, distance > config.allowableMovement {
            cancelTracking(reason: "movementExceeded distance=\(String(format: "%.1f", distance))")
            return
        }

        if didTrigger {
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if didTrigger {
            logActive("RecognizerTouchEndedAfterTrigger")
            logActive(
                "GestureTouchEndedAfterTrigger",
                details: "presentationActive=\(menuCoordinator?.presentation != nil)"
            )
            state = .ended
            cleanupTracking()
            return
        }

        cancelTracking(reason: "touchEndedBeforeTrigger")
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if didTrigger {
            state = .cancelled
            cleanupTracking()
            return
        }

        cancelTracking(reason: "gestureCancelled")
    }

    override func reset() {
        super.reset()
        cleanupTracking()
    }

    func cancelFromOwner() {
        if didTrigger {
            state = .cancelled
        }
        cleanupTracking()
    }

    private var isScrollViewPanning: Bool {
        guard let activeScrollView else { return false }
        let panState = activeScrollView.panGestureRecognizer.state
        return panState == .began || panState == .changed
    }

    private func scheduleIntent() {
        guard let config = activeConfig else { return }

        intentTask?.cancel()
        intentTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(config.pressIntentDelay))
            guard !Task.isCancelled else { return }
            guard state == .possible else { return }
            guard let sourceID = activeSourceID else { return }
            guard let currentFrame = sourceRegistry?.currentFrame(for: sourceID) else { return }
            guard let latestLocationInWindow else { return }
            guard currentFrame.insetBy(dx: -2, dy: -2).contains(latestLocationInWindow) else { return }
            guard !isScrollViewPanning else { return }

            didActivateIntent = true
            logActive("IntentRecognized")
            logActive(
                "PressIntentActivated",
                details: "targetScale=\(String(format: "%.2f", Double(config.pressScale))) intentDelay=\(String(format: "%.3f", config.pressIntentDelay)) totalTriggerAfter=\(String(format: "%.3f", config.longPressDuration))"
            )
            sourceRegistry?.setPressing(true, for: sourceID)
            menuCoordinator?.setIsPressing(
                true,
                sourceDescription: activeSourceDescription,
                config: config
            )
        }
    }

    private func scheduleTrigger() {
        guard let config = activeConfig else { return }

        triggerTask?.cancel()
        triggerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(config.longPressDuration))
            guard !Task.isCancelled else { return }
            guard state == .possible else { return }
            guard let sourceID = activeSourceID else { return }
            guard let currentFrame = sourceRegistry?.currentFrame(for: sourceID) else { return }
            guard let latestLocationInWindow else { return }
            guard currentFrame.insetBy(dx: -2, dy: -2).contains(latestLocationInWindow) else { return }
            guard !isScrollViewPanning else { return }

            didTrigger = true
            sourceRegistry?.setPressing(false, for: sourceID)
            menuCoordinator?.setIsPressing(
                false,
                sourceDescription: activeSourceDescription,
                config: config
            )

            logActive(
                "LongPressConfirmed",
                details: "frame=(x:\(fmt(currentFrame.minX)), y:\(fmt(currentFrame.minY)), w:\(fmt(currentFrame.width)), h:\(fmt(currentFrame.height)))"
            )
            logActive("PressTimerFired")
            logActive(
                "GestureLongPressSucceeded",
                details: "currentScale=\(String(format: "%.2f", Double(config.pressScale))) sourceFrame=(x:\(fmt(currentFrame.minX)), y:\(fmt(currentFrame.minY)), w:\(fmt(currentFrame.width)), h:\(fmt(currentFrame.height)))"
            )

            menuCoordinator?.lockScrollInteraction(
                on: activeScrollView,
                sourceDescription: activeSourceDescription,
                config: config
            )
            state = .began
            sourceRegistry?.activateSource(sourceID, sourceFrame: currentFrame)
        }
    }

    private func cancelTracking(reason: String) {
        guard let config = activeConfig else {
            state = .failed
            cleanupTracking()
            return
        }

        if let sourceID = activeSourceID {
            sourceRegistry?.setPressing(false, for: sourceID)
        }
        menuCoordinator?.setIsPressing(
            false,
            sourceDescription: activeSourceDescription,
            config: config
        )

        logActive("TrackingCancelled", details: "reason=\(reason)")
        if didActivateIntent || activeSourceID != nil {
            logActive("PressCancelled", details: "reason=\(reason)")
        }

        if !didTrigger, menuCoordinator?.presentation == nil {
            CustomContextMenuDebugConsole.end(
                enabled: config.isLoggingEnabled,
                sourceID: activeSourceDescription,
                reason: reason
            )
        }

        state = .failed
        cleanupTracking()
    }

    private func cleanupTracking() {
        intentTask?.cancel()
        triggerTask?.cancel()
        intentTask = nil
        triggerTask = nil
        activeSourceID = nil
        activeSourceDescription = nil
        activeConfig = nil
        activeScrollView = nil
        initialLocationInRecognizerView = nil
        latestLocationInWindow = nil
        didActivateIntent = false
        didTrigger = false
    }

    private func logActive(_ event: String, details: String = "") {
        guard let config = activeConfig else { return }
        CustomContextMenuDebugConsole.log(
            enabled: config.isLoggingEnabled,
            sourceID: activeSourceDescription,
            event: event,
            details: details
        )
    }

    private func fmt(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}

// MARK: - Modifier

/// View modifier that measures the source view and presents the custom context menu on long press.
private struct CustomContextMenuModifier<ID: Hashable, Preview: View>: ViewModifier {
    let id: ID
    let isEnabled: Bool
    let infoRows: [CustomContextMenuInfoRow]
    let actions: [CustomContextMenuAction]
    let config: CustomContextMenuConfig
    let preview: () -> Preview

    @Environment(CustomContextMenuCoordinator.self) private var coordinator
    @Environment(CustomContextMenuSourceRegistry.self) private var sourceRegistry
    @State private var measuredMenuSize: CGSize = .zero
    @State private var isPressing = false

    private var hiddenSourceOpacity: Double {
        coordinator.isSourceHidden(id) ? 0 : 1
    }

    private var menuSizeCacheKey: String {
        CustomContextMenuMenuSizeCache.key(for: actions, infoRows: infoRows)
    }

    private var resolvedMenuSize: CGSize {
        if measuredMenuSize != .zero {
            return measuredMenuSize
        }

        return CustomContextMenuMenuSizeCache.size(for: menuSizeCacheKey) ?? .zero
    }

    func body(content: Content) -> some View {
        content
            .opacity(hiddenSourceOpacity)
            .transaction { transaction in
                transaction.animation = nil
            }
            .scaleEffect(isPressing ? config.pressScale : 1, anchor: .topLeading)
            .background(alignment: .topLeading) {
                if resolvedMenuSize == .zero {
                    CustomContextMenuMenuMeasure(
                        infoRows: infoRows,
                        actions: actions
                    ) { newSize in
                        if shouldUpdateMenuSize(with: newSize) {
                            measuredMenuSize = newSize
                            CustomContextMenuMenuSizeCache.store(newSize, for: menuSizeCacheKey)
                        }
                    }
                    .hidden()
                    .allowsHitTesting(false)
                }
            }
            .background {
                CustomContextMenuSourceAttachment(
                    id: AnyHashable(id),
                    sourceDescription: String(describing: id),
                    isEnabled: isEnabled && !actions.isEmpty,
                    config: config,
                    sourceRegistry: sourceRegistry,
                    onPressingChange: { newValue in
                        if isPressing != newValue {
                            withAnimation(newValue ? .contextMenuPressIn : .contextMenuPressOut) {
                                isPressing = newValue
                            }
                        }
                    },
                    onActivate: presentMenu
                )
            }
            .onChange(of: coordinator.presentation?.id) { _, newPresentationID in
                if newPresentationID == nil {
                    CustomContextMenuDebugConsole.log(
                        enabled: config.isLoggingEnabled,
                        sourceID: String(describing: id),
                        event: "GestureObservedPresentationCleared"
                    )
                    isPressing = false
                }
            }
            .onChange(of: coordinator.phase) { _, newPhase in
                CustomContextMenuDebugConsole.log(
                    enabled: config.isLoggingEnabled,
                    sourceID: String(describing: id),
                    event: "GestureObservedPhase",
                    details: "phase=\(newPhase)"
                )
                if newPhase == .lifting || newPhase == .expanded || newPhase == .dismissing || newPhase == .idle {
                    isPressing = false
                }
            }
    }

    private func presentMenu(sourceGlobalFrame: CGRect) {
        guard isEnabled else { return }
        guard !actions.isEmpty else { return }
        guard sourceGlobalFrame != .zero else { return }
        CustomContextMenuDebugConsole.log(
            enabled: config.isLoggingEnabled,
            sourceID: String(describing: id),
            event: "ModifierPresentMenu",
            details: "actionsCount=\(actions.count)"
        )
        let triggerMessage = """
[CustomContextMenu][TriggerDebug]
sourceID=\(String(describing: id))
sourceFrame=(x:\(String(format: "%.1f", sourceGlobalFrame.minX)), y:\(String(format: "%.1f", sourceGlobalFrame.minY)), w:\(String(format: "%.1f", sourceGlobalFrame.width)), h:\(String(format: "%.1f", sourceGlobalFrame.height)))
measuredMenuSize=(w:\(String(format: "%.1f", resolvedMenuSize.width)), h:\(String(format: "%.1f", resolvedMenuSize.height)))
actionsCount=\(actions.count)
"""
        if config.isLoggingEnabled {
#if DEBUG
            print(triggerMessage)
#endif
        }
        coordinator.present(
            .init(
                sourceID: AnyHashable(id),
                sourceFrame: sourceGlobalFrame,
                preview: AnyView(preview()),
                infoRows: infoRows,
                actions: actions,
                measuredMenuSize: resolvedMenuSize,
                config: config
            )
        )
    }

    private func shouldUpdateMenuSize(with newSize: CGSize) -> Bool {
        abs(measuredMenuSize.width - newSize.width) > 0.5 ||
        abs(measuredMenuSize.height - newSize.height) > 0.5
    }
}

extension View {
    /// Attaches the reusable custom context-menu system to one source view.
    func customContextMenu<ID: Hashable, Preview: View>(
        id: ID,
        isEnabled: Bool = true,
        infoRows: [CustomContextMenuInfoRow] = [],
        actions: [CustomContextMenuAction],
        config: CustomContextMenuConfig = .init(),
        @ViewBuilder preview: @escaping () -> Preview
    ) -> some View {
        modifier(
            CustomContextMenuModifier(
                id: id,
                isEnabled: isEnabled,
                infoRows: infoRows,
                actions: actions,
                config: config,
                preview: preview
            )
        )
    }
}

// MARK: - Shared Card

/// The visible action card used by the custom context-menu host.
private struct CustomContextMenuMenuCard: View {
    let infoRows: [CustomContextMenuInfoRow]
    let actions: [CustomContextMenuAction]
    let cornerRadius: CGFloat
    let revealedActionIDs: Set<UUID>
    let isInteractive: Bool
    let showsChrome: Bool
    let onSelect: (CustomContextMenuAction) -> Void

    private var normalActions: [CustomContextMenuAction] {
        actions.filter { $0.role == .normal }
    }

    private var destructiveActions: [CustomContextMenuAction] {
        actions.filter { $0.role == .destructive }
    }

    private var shouldShowDivider: Bool {
        !normalActions.isEmpty &&
        !destructiveActions.isEmpty &&
        normalActions.allSatisfy { revealedActionIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !infoRows.isEmpty {
                infoSection

                if !actions.isEmpty {
                    Divider()
                        .overlay(Color.white.opacity(0.08))
                        .padding(.horizontal, 20)
                }
            }

            ForEach(normalActions) { action in
                row(for: action)
            }

            if !normalActions.isEmpty && !destructiveActions.isEmpty {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.horizontal, 20)
                    .opacity(shouldShowDivider ? 1 : 0)
                    .offset(y: shouldShowDivider ? 0 : 6)
                    .animation(.contextMenuMenuSpring, value: shouldShowDivider)
            }

            ForEach(destructiveActions) { action in
                row(for: action)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .modifier(
            CustomContextMenuCardChrome(
                cornerRadius: cornerRadius,
                isEnabled: showsChrome
            )
        )
        .allowsHitTesting(isInteractive)
    }

    private var infoSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(infoRows) { row in
                    infoChip(for: row)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 214, height: 58, alignment: .leading)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func infoChip(for row: CustomContextMenuInfoRow) -> some View {
        VStack(spacing: 2) {
            Text(row.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.56))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)

            Text(row.value)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 72)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    @ViewBuilder
    private func row(for action: CustomContextMenuAction) -> some View {
        let isRevealed = revealedActionIDs.contains(action.id)

        Button {
            debugLogSelection(for: action)
            emitSelectionHaptic(for: action.role)
            onSelect(action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 18, alignment: .center)

                Text(action.title)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(action.role == .destructive ? Color.red : Color.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isRevealed ? 1 : 0)
        .offset(x: isRevealed ? 0 : 5, y: isRevealed ? 0 : 12)
        .scaleEffect(isRevealed ? 1 : 0.95, anchor: .topLeading)
        .animation(.contextMenuMenuSpring, value: isRevealed)
    }

    private func emitSelectionHaptic(for role: CustomContextMenuActionRole) {
        switch role {
        case .normal:
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.prepare()
            generator.impactOccurred(intensity: 0.62)
        case .destructive:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.warning)
        }
    }

    private func debugLogSelection(for action: CustomContextMenuAction) {
#if DEBUG
        print("[CustomContextMenu][Action] title=\(action.title) role=\(action.role)")
#endif
    }
}

private struct CustomContextMenuCardChrome: ViewModifier {
    let cornerRadius: CGFloat
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        } else {
            content
        }
    }
}

/// Hidden measure surface that gives source views the real menu card size before presentation.
private struct CustomContextMenuMenuMeasure: View {
    let infoRows: [CustomContextMenuInfoRow]
    let actions: [CustomContextMenuAction]
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        CustomContextMenuMenuCard(
            infoRows: infoRows,
            actions: actions,
            cornerRadius: 32,
            revealedActionIDs: Set(actions.map(\.id)),
            isInteractive: false,
            showsChrome: false,
            onSelect: { _ in }
        )
        .background {
            Color.clear
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newSize in
                    onSizeChange(newSize)
                }
        }
    }
}

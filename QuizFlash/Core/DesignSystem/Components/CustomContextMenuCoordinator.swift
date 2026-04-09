//
//  CustomContextMenuCoordinator.swift
//  QuizFlash
//
//  Main-actor coordinator and source registry for the custom context-menu system.
//

import SwiftUI
import UIKit

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

        let layout = CustomContextMenuLayoutResolver.resolveLayout(
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
    func performAction(_ action: @escaping @MainActor @Sendable () -> Void) {
        dismiss(after: action)
    }

    /// Returns true while the given source view should remain visually hidden in-place.
    func isSourceHidden<ID: Hashable>(_ id: ID) -> Bool {
        presentation?.sourceID == AnyHashable(id)
    }

    private func dismiss(after action: (@MainActor @Sendable () -> Void)?) {
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
        CustomContextMenuLog.debug(message)
    }

    private static func fmt(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private static func emitRevealHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 1)
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
        let setPressing: @MainActor @Sendable (Bool) -> Void
        let activate: @MainActor @Sendable (CGRect) -> Void

        init(
            id: AnyHashable,
            sourceDescription: String,
            anchorView: UIView,
            isEnabled: Bool,
            config: CustomContextMenuConfig,
            setPressing: @escaping @MainActor @Sendable (Bool) -> Void,
            activate: @escaping @MainActor @Sendable (CGRect) -> Void
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
        setPressing: @escaping @MainActor @Sendable (Bool) -> Void,
        activate: @escaping @MainActor @Sendable (CGRect) -> Void
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

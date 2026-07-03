//
//  CustomContextMenuInteractions.swift
//  QuizFlash
//
//  UIKit attachment and gesture plumbing for the custom context-menu system.
//

import SwiftUI
import UIKit

/// Lightweight attachment view that registers one source surface with the global source registry.
struct CustomContextMenuSourceAttachment: UIViewRepresentable {
    let id: AnyHashable
    let sourceDescription: String
    let isEnabled: Bool
    let config: CustomContextMenuConfig
    let sourceRegistry: CustomContextMenuSourceRegistry
    let onPressingChange: @MainActor @Sendable (Bool) -> Void
    let onActivate: @MainActor @Sendable (CGRect) -> Void

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
            let onPressingChange = parent.onPressingChange
            let onActivate = parent.onActivate
            parent.sourceRegistry.registerOrUpdate(
                id: parent.id,
                sourceDescription: parent.sourceDescription,
                anchorView: uiView,
                isEnabled: parent.isEnabled,
                config: parent.config,
                setPressing: { isPressing in
                    onPressingChange(isPressing)
                },
                activate: { sourceFrame in
                    onActivate(sourceFrame)
                }
            )
        }
    }

    final class AttachmentView: UIView {}
}

/// Global tracking attachment that installs the shared long-press recognizer once per host window.
struct CustomContextMenuTouchTrackerAttachment: UIViewRepresentable {
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
        private weak var recognizer: CustomContextMenuGlobalTouchRecognizer?

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

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            !isNativeTextInputTouch(touch.view)
        }

        private func isNativeTextInputTouch(_ view: UIView?) -> Bool {
            var currentView = view
            while let view = currentView {
                if view is UITextView || view is UITextField {
                    return true
                }
                currentView = view.superview
            }
            return false
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

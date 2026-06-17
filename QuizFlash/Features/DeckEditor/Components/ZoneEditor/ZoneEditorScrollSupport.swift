//
//  ZoneEditorScrollSupport.swift
//  QuizFlash
//
//  Shared UIKit scroll helpers for zone-based editor surfaces.
//

import SwiftUI
import UIKit

@MainActor
final class ZoneEditorScrollDriver {
    private weak var scrollView: UIScrollView?
    private var pendingTopInset: CGFloat = 0
    private var pendingBottomInset: CGFloat = 0
    private var appliedTopInset: CGFloat = 0
    private var appliedBottomInset: CGFloat = 0
    private var offsetObservation: NSKeyValueObservation?
    private var contentInsetObservation: NSKeyValueObservation?
    private var contentSizeObservation: NSKeyValueObservation?
    private var boundsObservation: NSKeyValueObservation?
    private var lockedOffset: CGPoint?
    private var offsetLockTask: Task<Void, Never>?
    private var isRestoringLockedOffset = false
    private var onScrollOffsetChange: ((CGFloat) -> Void)?
    private var lastReportedScrollOffsetY: CGFloat?
    private var tapProbe: ZoneEditorTapProbe?
    private(set) var tapProbeStatus = "not-configured"
    private(set) var currentNormalizedOffsetY: CGFloat = 0
    private(set) var currentContentInsetBottom: CGFloat = 0
    private(set) var currentAdjustedContentInsetBottom: CGFloat = 0

    func attach(_ scrollView: UIScrollView?) {
        guard self.scrollView !== scrollView else { return }
        offsetObservation?.invalidate()
        contentInsetObservation?.invalidate()
        contentSizeObservation?.invalidate()
        boundsObservation?.invalidate()
        self.scrollView = scrollView
        guard let scrollView else {
            offsetObservation = nil
            contentInsetObservation = nil
            contentSizeObservation = nil
            boundsObservation = nil
            lockedOffset = nil
            return
        }
        observeScrollView(in: scrollView)
        recordScrollSnapshot("scroll-attach", in: scrollView, zoneID: nil)
        reportScrollOffset(in: scrollView, force: true)
        applyContentInsetsIfNeeded(reason: "attach")
    }

    func detach() {
        offsetObservation?.invalidate()
        offsetObservation = nil
        contentInsetObservation?.invalidate()
        contentInsetObservation = nil
        contentSizeObservation?.invalidate()
        contentSizeObservation = nil
        boundsObservation?.invalidate()
        boundsObservation = nil
        offsetLockTask?.cancel()
        offsetLockTask = nil
        lockedOffset = nil
        onScrollOffsetChange = nil
        lastReportedScrollOffsetY = nil
        currentNormalizedOffsetY = 0
        currentContentInsetBottom = 0
        currentAdjustedContentInsetBottom = 0
        tapProbe?.detach()
        tapProbe = nil
        tapProbeStatus = "detached"
        scrollView = nil
    }

    func setScrollOffsetHandler(_ handler: @escaping (CGFloat) -> Void) {
        onScrollOffsetChange = handler
        if let scrollView {
            reportScrollOffset(in: scrollView, force: true)
        }
    }

    @discardableResult
    func setTapProbeHandler(_ handler: ((ZoneEditorTapProbeSnapshot) -> Void)?) -> String {
        guard let scrollView else {
            tapProbeStatus = "no-scroll-view"
            return tapProbeStatus
        }

        guard let handler else {
            tapProbe?.detach()
            tapProbe = nil
            tapProbeStatus = "detached"
            return tapProbeStatus
        }

        if let tapProbe {
            tapProbe.onTap = handler
            tapProbe.attach(to: scrollView)
            tapProbeStatus = "reused-attached"
            return tapProbeStatus
        }

        let probe = ZoneEditorTapProbe()
        probe.onTap = handler
        probe.attach(to: scrollView)
        tapProbe = probe
        tapProbeStatus = "created-attached"
        return tapProbeStatus
    }

    func setTopInset(_ inset: CGFloat, reason: String = "set-top") {
        let resolvedInset = max(inset, 0)
        let currentInset = scrollView?.contentInset.top ?? 0
        guard abs(pendingTopInset - resolvedInset) > 0.5
                || abs(currentInset - resolvedInset) > 0.5
        else { return }

        pendingTopInset = resolvedInset
        applyContentInsetsIfNeeded(reason: reason)
    }

    func setBottomInset(_ inset: CGFloat, reason: String = "set-bottom") {
        let resolvedInset = max(inset, 0)
        guard abs(pendingBottomInset - resolvedInset) > 0.5
                || abs((scrollView?.contentInset.bottom ?? 0) - resolvedInset) > 0.5
        else {
            if let scrollView {
                ZoneEditorDebugStore.shared.recordScrollDecision(
                    "scroll-inset-set-skip",
                    zoneID: nil,
                    details: "reason=\(reason) requested=\(debugValue(resolvedInset)) \(scrollSnapshotDetails(in: scrollView))"
                )
            }
            return
        }

        pendingBottomInset = resolvedInset
        if let scrollView {
            ZoneEditorDebugStore.shared.recordScrollDecision(
                "scroll-inset-set-request",
                zoneID: nil,
                details: "reason=\(reason) requested=\(debugValue(resolvedInset)) \(scrollSnapshotDetails(in: scrollView))"
            )
        }
        applyContentInsetsIfNeeded(reason: reason)
    }

    func resetBottomInset(reason: String = "reset-bottom") {
        setBottomInset(0, reason: reason)
    }

    @discardableResult
    func ensureBottomInsetAllowsWindowRectScroll(
        windowRect: CGRect,
        bottomChromeTopY: CGFloat?,
        keyboardHeight: CGFloat,
        bottomAccessoryHeight: CGFloat,
        bottomBuffer: CGFloat,
        minimumBottomInset: CGFloat,
        zoneID: UUID?
    ) -> CGFloat {
        guard let scrollView,
              scrollView.window != nil,
              scrollView.bounds.height > 0
        else {
            ZoneEditorDebugStore.shared.recordScrollDecision(
                "scroll-inset-skip",
                zoneID: zoneID,
                details: "reason=no-scroll-view rect=\(debugRect(windowRect)) minimum=\(debugValue(minimumBottomInset))"
            )
            return pendingBottomInset
        }

        scrollView.layoutIfNeeded()
        captureInsetDebugState(in: scrollView)

        let currentY = scrollView.contentOffset.y
        let visibleBottomY = visibleBottomWindowY(
            in: scrollView,
            bottomChromeTopY: bottomChromeTopY,
            keyboardHeight: keyboardHeight,
            bottomAccessoryHeight: bottomAccessoryHeight,
            bottomBuffer: bottomBuffer
        )
        let overlap = windowRect.maxY - visibleBottomY
        guard overlap > 0 else {
            ZoneEditorDebugStore.shared.recordScrollDecision(
                "scroll-inset-skip",
                zoneID: zoneID,
                details: "reason=visible rect=\(debugRect(windowRect)) visibleBottom=\(debugValue(visibleBottomY)) overlap=\(debugValue(overlap)) current=\(debugValue(currentY)) inset=\(debugInsets(scrollView.adjustedContentInset)) pendingBottom=\(debugValue(pendingBottomInset))"
            )
            return pendingBottomInset
        }

        let desiredTargetY = currentY + overlap
        let contentScrollableHeight = scrollView.contentSize.height - scrollView.bounds.height
        let systemBottomAdjustment = scrollView.adjustedContentInset.bottom - scrollView.contentInset.bottom
        let requiredContentInset = max(
            minimumBottomInset,
            desiredTargetY - contentScrollableHeight - systemBottomAdjustment
        )
        let resolvedBottomInset = max(pendingBottomInset, requiredContentInset, 0)

        ZoneEditorDebugStore.shared.recordScrollDecision(
            "scroll-inset-resolve",
            zoneID: zoneID,
            details: "rect=\(debugRect(windowRect)) visibleBottom=\(debugValue(visibleBottomY)) overlap=\(debugValue(overlap)) current=\(debugValue(currentY)) desiredTarget=\(debugValue(desiredTargetY)) scrollable=\(debugValue(contentScrollableHeight)) systemBottom=\(debugValue(systemBottomAdjustment)) required=\(debugValue(requiredContentInset)) resolved=\(debugValue(resolvedBottomInset)) currentInset=\(debugInsets(scrollView.contentInset)) adjusted=\(debugInsets(scrollView.adjustedContentInset))"
        )

        setBottomInset(resolvedBottomInset, reason: "ensure-window-rect")
        captureInsetDebugState(in: scrollView)
        return resolvedBottomInset
    }

    func resetToTop(duration: TimeInterval = 0) {
        guard let scrollView else { return }
        lockedOffset = nil
        let minOffsetY = -scrollView.adjustedContentInset.top
        guard abs(scrollView.contentOffset.y - minOffsetY) > 0.5 else { return }
        guard duration > 0.02 else {
            scrollView.layer.removeAllAnimations()
            UIView.performWithoutAnimation {
                scrollView.setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: minOffsetY),
                    animated: false
                )
                scrollView.layoutIfNeeded()
            }
            reportScrollOffset(in: scrollView, force: true)
            return
        }

        clearOffsetLock()
        setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: minOffsetY),
            in: scrollView,
            duration: duration,
            options: [.curveEaseOut],
            zoneID: nil
        )
        reportScrollOffset(in: scrollView, force: true)
    }

    func restoreNormalizedOffset(_ normalizedOffsetY: CGFloat) {
        guard let scrollView else { return }
        clearOffsetLock()
        scrollView.layer.removeAllAnimations()

        let targetY = clampedOffsetY(
            normalizedOffsetY - scrollView.adjustedContentInset.top,
            in: scrollView
        )
        guard abs(scrollView.contentOffset.y - targetY) > 0.5 else {
            reportScrollOffset(in: scrollView, force: true)
            return
        }

        UIView.performWithoutAnimation {
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: targetY),
                animated: false
            )
            scrollView.layoutIfNeeded()
        }
        reportScrollOffset(in: scrollView, force: true)
    }

    func preserveCurrentOffsetDuringNonUserFocus(
        duration: Duration = .milliseconds(850)
    ) {
        guard let scrollView else { return }

        if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
            clearOffsetLock()
            return
        }

        if lockedOffset == nil {
            lockedOffset = scrollView.contentOffset
        }

        restoreLockedOffsetIfNeeded(in: scrollView)

        offsetLockTask?.cancel()
        offsetLockTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self.clearOffsetLock()
        }
    }

    func releaseOffsetLock() {
        clearOffsetLock()
    }

    @discardableResult
    func scrollWindowRectAboveBottomChromeIfNeeded(
        windowRect: CGRect,
        bottomChromeTopY: CGFloat?,
        keyboardHeight: CGFloat,
        bottomAccessoryHeight: CGFloat,
        bottomBuffer: CGFloat,
        animationDuration: TimeInterval,
        animationOptions: UIView.AnimationOptions,
        zoneID: UUID?
    ) -> Bool {
        guard let scrollView,
              scrollView.window != nil,
              scrollView.bounds.height > 0,
              scrollView.contentSize.height
                + scrollView.adjustedContentInset.top
                + scrollView.adjustedContentInset.bottom > scrollView.bounds.height
        else {
            ZoneEditorDebugStore.shared.recordScrollDecision(
                "scroll-skip",
                zoneID: zoneID,
                details: "reason=not-scrollable rect=\(debugRect(windowRect)) keyboard=\(debugValue(keyboardHeight)) accessory=\(debugValue(bottomAccessoryHeight)) buffer=\(debugValue(bottomBuffer))"
            )
            return false
        }

        scrollView.layoutIfNeeded()

        let currentY = scrollView.contentOffset.y
        let visibleBottomY = visibleBottomWindowY(
            in: scrollView,
            bottomChromeTopY: bottomChromeTopY,
            keyboardHeight: keyboardHeight,
            bottomAccessoryHeight: bottomAccessoryHeight,
            bottomBuffer: bottomBuffer
        )
        let overlap = windowRect.maxY - visibleBottomY
        guard overlap > 0 else {
            ZoneEditorDebugStore.shared.recordScrollDecision(
                "scroll-skip",
                zoneID: zoneID,
                details: "reason=visible rect=\(debugRect(windowRect)) visibleBottom=\(debugValue(visibleBottomY)) overlap=\(debugValue(overlap)) offset=\(debugValue(currentY)) inset=\(debugInsets(scrollView.adjustedContentInset)) content=\(debugSize(scrollView.contentSize)) bounds=\(debugSize(scrollView.bounds.size))"
            )
            return false
        }

        let targetY = clampedOffsetY(currentY + overlap, in: scrollView)
        guard abs(targetY - currentY) > 0.5 else {
            ZoneEditorDebugStore.shared.recordScrollDecision(
                "scroll-skip",
                zoneID: zoneID,
                details: "reason=clamped rect=\(debugRect(windowRect)) visibleBottom=\(debugValue(visibleBottomY)) overlap=\(debugValue(overlap)) current=\(debugValue(currentY)) target=\(debugValue(targetY)) inset=\(debugInsets(scrollView.adjustedContentInset)) content=\(debugSize(scrollView.contentSize)) bounds=\(debugSize(scrollView.bounds.size))"
            )
            return false
        }

        clearOffsetLock()
        ZoneEditorDebugStore.shared.recordScrollDecision(
            "scroll-apply",
            zoneID: zoneID,
            details: "rect=\(debugRect(windowRect)) visibleBottom=\(debugValue(visibleBottomY)) overlap=\(debugValue(overlap)) current=\(debugValue(currentY)) target=\(debugValue(targetY)) chromeTop=\(debugOptionalValue(bottomChromeTopY)) keyboard=\(debugValue(keyboardHeight)) accessory=\(debugValue(bottomAccessoryHeight)) buffer=\(debugValue(bottomBuffer)) inset=\(debugInsets(scrollView.adjustedContentInset)) content=\(debugSize(scrollView.contentSize)) bounds=\(debugSize(scrollView.bounds.size))"
        )
        setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: targetY),
            in: scrollView,
            duration: animationDuration,
            options: animationOptions,
            zoneID: zoneID
        )
        return true
    }

    @discardableResult
    func scrollContentRectAboveBottomChromeIfNeeded(
        contentRect: CGRect,
        contentTopOffset: CGFloat,
        bottomChromeTopY: CGFloat?,
        keyboardHeight: CGFloat,
        bottomAccessoryHeight: CGFloat,
        bottomBuffer: CGFloat,
        animationDuration: TimeInterval,
        animationOptions: UIView.AnimationOptions,
        zoneID: UUID?
    ) -> Bool {
        guard let scrollView, scrollView.window != nil else {
            ZoneEditorDebugStore.shared.recordScrollDecision(
                "scroll-skip",
                zoneID: zoneID,
                details: "reason=no-scroll-view contentRect=\(debugRect(contentRect))"
            )
            return false
        }

        scrollView.layoutIfNeeded()
        let contentY = contentRect.maxY + contentTopOffset
        let boundsY = contentY - scrollView.contentOffset.y
        let bottomPoint = CGPoint(x: scrollView.bounds.midX, y: boundsY)
        let bottomPointInWindow = scrollView.convert(bottomPoint, to: nil)
        let windowRect = CGRect(
            x: bottomPointInWindow.x,
            y: bottomPointInWindow.y - max(contentRect.height, 1),
            width: max(contentRect.width, 1),
            height: max(contentRect.height, 1)
        )

        ZoneEditorDebugStore.shared.recordScrollDecision(
            "scroll-frame-candidate",
            zoneID: zoneID,
            details: "contentRect=\(debugRect(contentRect)) topOffset=\(debugValue(contentTopOffset)) windowRect=\(debugRect(windowRect)) offset=\(debugValue(scrollView.contentOffset.y))"
        )

        return scrollWindowRectAboveBottomChromeIfNeeded(
            windowRect: windowRect,
            bottomChromeTopY: bottomChromeTopY,
            keyboardHeight: keyboardHeight,
            bottomAccessoryHeight: bottomAccessoryHeight,
            bottomBuffer: bottomBuffer,
            animationDuration: animationDuration,
            animationOptions: animationOptions,
            zoneID: zoneID
        )
    }

    private func setContentOffset(
        _ offset: CGPoint,
        in scrollView: UIScrollView,
        duration: TimeInterval,
        options: UIView.AnimationOptions,
        zoneID: UUID?
    ) {
        scrollView.layer.removeAllAnimations()
        recordScrollSnapshot(
            "scroll-offset-request",
            in: scrollView,
            zoneID: zoneID,
            extra: "requested=\(debugPoint(offset)) duration=\(debugValue(duration)) options=\(debugAnimationOptions(options))"
        )
        guard duration > 0.02 else {
            scrollView.setContentOffset(offset, animated: false)
            recordScrollSnapshot("scroll-offset-applied-immediate", in: scrollView, zoneID: zoneID)
            return
        }

        let resolvedOptions: UIView.AnimationOptions = [
            options,
            .beginFromCurrentState,
            .allowUserInteraction
        ]
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: resolvedOptions
        ) {
            scrollView.setContentOffset(offset, animated: false)
            self.recordScrollSnapshot("scroll-offset-animation-body", in: scrollView, zoneID: zoneID)
        } completion: { _ in
            Task { @MainActor [weak scrollView] in
                guard let scrollView else { return }
                self.recordScrollSnapshot("scroll-offset-animation-complete", in: scrollView, zoneID: zoneID)
            }
        }
        scheduleScrollSnapshots(after: [0.016, 0.08, 0.18, 0.32], scrollView: scrollView, zoneID: zoneID)
    }

    private func observeScrollView(in scrollView: UIScrollView) {
        offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self, weak scrollView] _, _ in
            Task { @MainActor [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                self.handleObservedOffset(in: scrollView)
            }
        }
        contentInsetObservation = scrollView.observe(\.contentInset, options: [.old, .new]) { [weak self, weak scrollView] _, change in
            Task { @MainActor [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                self.captureInsetDebugState(in: scrollView)
                self.recordScrollSnapshot(
                    "scroll-content-inset-change",
                    in: scrollView,
                    zoneID: nil,
                    extra: "old=\(change.oldValue.map(self.debugInsets) ?? "nil") new=\(change.newValue.map(self.debugInsets) ?? "nil") pending=\(self.debugValue(self.pendingBottomInset)) applied=\(self.debugValue(self.appliedBottomInset))"
                )
            }
        }
        contentSizeObservation = scrollView.observe(\.contentSize, options: [.old, .new]) { [weak self, weak scrollView] _, change in
            Task { @MainActor [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                self.recordScrollSnapshot(
                    "scroll-content-size-change",
                    in: scrollView,
                    zoneID: nil,
                    extra: "old=\(change.oldValue.map(self.debugSize) ?? "nil") new=\(change.newValue.map(self.debugSize) ?? "nil")"
                )
            }
        }
        boundsObservation = scrollView.observe(\.bounds, options: [.old, .new]) { [weak self, weak scrollView] _, change in
            Task { @MainActor [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                self.recordScrollSnapshot(
                    "scroll-bounds-change",
                    in: scrollView,
                    zoneID: nil,
                    extra: "old=\(change.oldValue.map(self.debugRect) ?? "nil") new=\(change.newValue.map(self.debugRect) ?? "nil")"
                )
            }
        }
    }

    private func handleObservedOffset(in scrollView: UIScrollView) {
        reportScrollOffset(in: scrollView)
        guard !isRestoringLockedOffset else { return }

        guard lockedOffset != nil else { return }

        if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
            clearOffsetLock()
            return
        }

        restoreLockedOffsetIfNeeded(in: scrollView)
    }

    private func reportScrollOffset(in scrollView: UIScrollView, force: Bool = false) {
        let normalizedOffsetY = max(0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
        currentNormalizedOffsetY = normalizedOffsetY
        captureInsetDebugState(in: scrollView)
        guard let onScrollOffsetChange else { return }
        if !force,
           let lastReportedScrollOffsetY,
           abs(lastReportedScrollOffsetY - normalizedOffsetY) < 2 {
            return
        }

        lastReportedScrollOffsetY = normalizedOffsetY
        onScrollOffsetChange(normalizedOffsetY)
    }

    private func restoreLockedOffsetIfNeeded(in scrollView: UIScrollView) {
        guard let lockedOffset else { return }

        let targetOffset = CGPoint(
            x: lockedOffset.x,
            y: clampedOffsetY(lockedOffset.y, in: scrollView)
        )
        guard abs(scrollView.contentOffset.x - targetOffset.x) > 0.5
                || abs(scrollView.contentOffset.y - targetOffset.y) > 0.5 else {
            return
        }

        isRestoringLockedOffset = true
        UIView.performWithoutAnimation {
            scrollView.layer.removeAllAnimations()
            scrollView.setContentOffset(targetOffset, animated: false)
            scrollView.layoutIfNeeded()
        }
        isRestoringLockedOffset = false
    }

    private func clearOffsetLock() {
        lockedOffset = nil
        offsetLockTask?.cancel()
        offsetLockTask = nil
    }

    private func applyContentInsetsIfNeeded(reason: String) {
        guard let scrollView else { return }
        guard abs(appliedTopInset - pendingTopInset) > 0.5
                || abs(scrollView.contentInset.top - pendingTopInset) > 0.5
                || abs(appliedBottomInset - pendingBottomInset) > 0.5
                || abs(scrollView.contentInset.bottom - pendingBottomInset) > 0.5
        else {
            recordScrollSnapshot(
                "scroll-inset-apply-skip",
                in: scrollView,
                zoneID: nil,
                extra: "reason=\(reason)"
            )
            return
        }

        let oldMinOffsetY = -scrollView.adjustedContentInset.top
        let shouldKeepPinnedToTop = abs(scrollView.contentOffset.y - oldMinOffsetY) <= 1
            || scrollView.contentOffset.y < oldMinOffsetY
        recordScrollSnapshot(
            "scroll-inset-apply-start",
            in: scrollView,
            zoneID: nil,
            extra: "reason=\(reason) pending=\(debugValue(pendingTopInset))/\(debugValue(pendingBottomInset)) keepTop=\(shouldKeepPinnedToTop ? 1 : 0)"
        )

        appliedTopInset = pendingTopInset
        appliedBottomInset = pendingBottomInset
        var contentInset = scrollView.contentInset
        contentInset.top = pendingTopInset
        contentInset.bottom = pendingBottomInset
        var verticalIndicatorInsets = scrollView.verticalScrollIndicatorInsets
        verticalIndicatorInsets.top = pendingTopInset
        verticalIndicatorInsets.bottom = pendingBottomInset

        UIView.performWithoutAnimation {
            scrollView.contentInset = contentInset
            scrollView.verticalScrollIndicatorInsets = verticalIndicatorInsets
            scrollView.layoutIfNeeded()
            captureInsetDebugState(in: scrollView)
            recordScrollSnapshot(
                "scroll-inset-apply-after-set",
                in: scrollView,
                zoneID: nil,
                extra: "reason=\(reason)"
            )

            let newMinOffsetY = -scrollView.adjustedContentInset.top
            if shouldKeepPinnedToTop || scrollView.contentOffset.y < newMinOffsetY {
                scrollView.setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: newMinOffsetY),
                    animated: false
                )
            }
        }
        captureInsetDebugState(in: scrollView)
        recordScrollSnapshot(
            "scroll-inset-apply-end",
            in: scrollView,
            zoneID: nil,
            extra: "reason=\(reason)"
        )
    }

    private func captureInsetDebugState(in scrollView: UIScrollView) {
        currentContentInsetBottom = scrollView.contentInset.bottom
        currentAdjustedContentInsetBottom = scrollView.adjustedContentInset.bottom
    }

    private func visibleBottomWindowY(
        in scrollView: UIScrollView,
        bottomChromeTopY: CGFloat?,
        keyboardHeight: CGFloat,
        bottomAccessoryHeight: CGFloat,
        bottomBuffer: CGFloat
    ) -> CGFloat {
        let viewportBottomY = scrollView.convert(
            CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.maxY),
            to: nil
        ).y - bottomBuffer

        let fallbackChromeTopY: CGFloat?
        if keyboardHeight > 0 || bottomAccessoryHeight > 0 {
            fallbackChromeTopY = (scrollView.window?.bounds.maxY ?? UIScreen.main.bounds.maxY)
                - keyboardHeight
                - max(bottomAccessoryHeight, 0)
        } else {
            fallbackChromeTopY = nil
        }

        let chromeTopY: CGFloat?
        if let bottomChromeTopY, let fallbackChromeTopY {
            chromeTopY = min(bottomChromeTopY, fallbackChromeTopY)
        } else {
            chromeTopY = bottomChromeTopY ?? fallbackChromeTopY
        }

        guard let chromeTopY else { return viewportBottomY }
        return min(viewportBottomY, chromeTopY - bottomBuffer)
    }

    private func clampedOffsetY(_ offsetY: CGFloat, in scrollView: UIScrollView) -> CGFloat {
        let minOffsetY = -scrollView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        return min(max(offsetY, minOffsetY), maxOffsetY)
    }

    private func scheduleScrollSnapshots(after delays: [TimeInterval], scrollView: UIScrollView, zoneID: UUID?) {
        for delay in delays {
            Task { @MainActor [weak scrollView] in
                try? await Task.sleep(for: .seconds(delay))
                guard let scrollView else { return }
                self.recordScrollSnapshot(
                    "scroll-offset-after-\(Int(delay * 1000))ms",
                    in: scrollView,
                    zoneID: zoneID
                )
            }
        }
    }

    private func recordScrollSnapshot(
        _ stage: String,
        in scrollView: UIScrollView,
        zoneID: UUID?,
        extra: String = ""
    ) {
        ZoneEditorDebugStore.shared.recordScrollDecision(
            stage,
            zoneID: zoneID,
            details: "\(extra.isEmpty ? "" : "\(extra) ")\(scrollSnapshotDetails(in: scrollView))"
        )
    }

    private func scrollSnapshotDetails(in scrollView: UIScrollView) -> String {
        let minOffsetY = -scrollView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        let animations = scrollView.layer.animationKeys()?.joined(separator: "|") ?? "none"
        return "id=\(debugObjectID(scrollView)) offset=\(debugPoint(scrollView.contentOffset)) normalized=\(debugValue(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)) min=\(debugValue(minOffsetY)) max=\(debugValue(maxOffsetY)) contentInset=\(debugInsets(scrollView.contentInset)) adjusted=\(debugInsets(scrollView.adjustedContentInset)) indicator=\(debugInsets(scrollView.verticalScrollIndicatorInsets)) pending=\(debugValue(pendingTopInset))/\(debugValue(pendingBottomInset)) applied=\(debugValue(appliedTopInset))/\(debugValue(appliedBottomInset)) content=\(debugSize(scrollView.contentSize)) bounds=\(debugRect(scrollView.bounds)) tracking=\(scrollView.isTracking ? 1 : 0) dragging=\(scrollView.isDragging ? 1 : 0) decel=\(scrollView.isDecelerating ? 1 : 0) window=\(scrollView.window == nil ? 0 : 1) anim=\(animations)"
    }

    private func debugRect(_ rect: CGRect) -> String {
        "\(debugValue(rect.minX)),\(debugValue(rect.minY)),\(debugValue(rect.width))x\(debugValue(rect.height))"
    }

    private func debugSize(_ size: CGSize) -> String {
        "\(debugValue(size.width))x\(debugValue(size.height))"
    }

    private func debugPoint(_ point: CGPoint) -> String {
        "\(debugValue(point.x)),\(debugValue(point.y))"
    }

    private func debugInsets(_ insets: UIEdgeInsets) -> String {
        "\(debugValue(insets.top)),\(debugValue(insets.left)),\(debugValue(insets.bottom)),\(debugValue(insets.right))"
    }

    private func debugOptionalValue(_ value: CGFloat?) -> String {
        value.map(debugValue) ?? "nil"
    }

    private func debugValue(_ value: CGFloat) -> String {
        guard value.isFinite else { return value.description }
        return String(format: "%.1f", Double(value))
    }

    private func debugValue(_ value: TimeInterval) -> String {
        guard value.isFinite else { return value.description }
        return String(format: "%.3f", value)
    }

    private func debugObjectID(_ object: AnyObject) -> String {
        String(describing: ObjectIdentifier(object))
    }

    private func debugAnimationOptions(_ options: UIView.AnimationOptions) -> String {
        String(options.rawValue)
    }
}

struct ZoneEditorTapProbeSnapshot {
    let contentPoint: CGPoint
    let windowPoint: CGPoint
    let hitViewName: String
    let hitSuperviewName: String
}

private final class ZoneEditorTapProbe: NSObject, UIGestureRecognizerDelegate {
    var onTap: ((ZoneEditorTapProbeSnapshot) -> Void)?

    private weak var scrollView: UIScrollView?
    private lazy var recognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        return recognizer
    }()

    func attach(to scrollView: UIScrollView) {
        guard self.scrollView !== scrollView else { return }
        detach()
        self.scrollView = scrollView
        scrollView.addGestureRecognizer(recognizer)
    }

    func detach() {
        if let scrollView {
            scrollView.removeGestureRecognizer(recognizer)
        }
        scrollView = nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc
    private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let scrollView else { return }
        let contentPoint = recognizer.location(in: scrollView)
        let windowPoint = scrollView.convert(contentPoint, to: nil)
        let hitView = scrollView.window?.hitTest(windowPoint, with: nil)

        onTap?(
            ZoneEditorTapProbeSnapshot(
                contentPoint: contentPoint,
                windowPoint: windowPoint,
                hitViewName: hitView.map { String(describing: type(of: $0)) } ?? "nil",
                hitSuperviewName: hitView?.superview.map { String(describing: type(of: $0)) } ?? "nil"
            )
        )
    }
}

struct ZoneEditorWindowTouchSnapshot {
    let phase: String
    let windowPoint: CGPoint
    let viewportPoint: CGPoint
    let isTapLike: Bool
    let viewportDescription: String
    let hitViewName: String
    let hitViewDescription: String
    let hitViewChain: String
    let gestureLines: [String]
    let gestureCount: Int
}

struct ZoneEditorWindowTouchProbe: UIViewRepresentable {
    let onSnapshot: (ZoneEditorWindowTouchSnapshot) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSnapshot: onSnapshot)
    }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.onSnapshot = onSnapshot
        uiView.coordinator = context.coordinator
        uiView.attachSoon()
    }

    static func dismantleUIView(_ uiView: ProbeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachSoon()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            coordinator?.updateViewport(from: self)
        }

        func attachSoon() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window else { return }
                coordinator?.attach(to: window)
                coordinator?.updateViewport(from: self)
            }
        }
    }

    final class Coordinator: NSObject {
        var onSnapshot: (ZoneEditorWindowTouchSnapshot) -> Void

        private weak var window: UIWindow?
        private var viewportFrame: CGRect = .zero
        private lazy var recognizer = ZoneEditorPassiveTouchRecognizer { [weak self] phase, point, isTapLike in
            self?.record(phase: phase, windowPoint: point, isTapLike: isTapLike)
        }

        init(onSnapshot: @escaping (ZoneEditorWindowTouchSnapshot) -> Void) {
            self.onSnapshot = onSnapshot
        }

        func attach(to window: UIWindow) {
            guard self.window !== window else { return }
            detach()
            self.window = window
            window.addGestureRecognizer(recognizer)
        }

        func detach() {
            if let window {
                window.removeGestureRecognizer(recognizer)
            }
            window = nil
        }

        func updateViewport(from view: UIView) {
            guard let window = view.window else { return }
            viewportFrame = view.convert(view.bounds, to: window)
        }

        private func record(phase: String, windowPoint: CGPoint, isTapLike: Bool) {
            guard window != nil, viewportFrame.contains(windowPoint) else { return }
            publishSnapshot(phase: "\(phase)/now", windowPoint: windowPoint, isTapLike: isTapLike)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                self?.publishSnapshot(phase: "\(phase)/60ms", windowPoint: windowPoint, isTapLike: isTapLike)
            }
        }

        private func publishSnapshot(phase: String, windowPoint: CGPoint, isTapLike: Bool) {
            guard let window else { return }
            let hitView = window.hitTest(windowPoint, with: nil)
            let chain = viewChain(startingAt: hitView)
            let gestures = gestureDescriptions(startingAt: hitView)
            let localPoint = hitView.map { $0.convert(windowPoint, from: window) } ?? .zero
            let hitFrame = hitView.map { $0.convert($0.bounds, to: window) } ?? .zero
            let viewportPoint = CGPoint(
                x: windowPoint.x - viewportFrame.minX,
                y: windowPoint.y - viewportFrame.minY
            )
            let gestureLines = gestures.isEmpty
                ? ["G none"]
                : gestures.enumerated().map { index, description in
                    "G\(index) \(description)"
                }

            onSnapshot(
                ZoneEditorWindowTouchSnapshot(
                    phase: phase,
                    windowPoint: windowPoint,
                    viewportPoint: viewportPoint,
                    isTapLike: isTapLike,
                    viewportDescription: rectDescription(viewportFrame),
                    hitViewName: hitView.map { shortTypeName($0) } ?? "nil",
                    hitViewDescription: "\(hitView.map { shortTypeName($0) } ?? "nil") local=\(Int(localPoint.x)),\(Int(localPoint.y)) frame=\(rectDescription(hitFrame))",
                    hitViewChain: chain.isEmpty ? "nil" : chain.joined(separator: ">"),
                    gestureLines: gestureLines,
                    gestureCount: gestures.count
                )
            )
        }

        private func viewChain(startingAt view: UIView?) -> [String] {
            var result: [String] = []
            var current = view
            while let view = current, result.count < 8 {
                let flags = "\(view.isUserInteractionEnabled ? "I" : "-")\(view.isHidden ? "H" : "-")"
                result.append("\(shortTypeName(view))[\(flags),a\(String(format: "%.1f", view.alpha))]")
                current = view.superview
            }
            return result
        }

        private func gestureDescriptions(startingAt view: UIView?) -> [String] {
            var result: [String] = []
            var current = view
            while let view = current {
                for gesture in view.gestureRecognizers ?? [] {
                    let state = gestureStateName(gesture.state)
                    let flags = "\(gesture.isEnabled ? "E" : "-")\(gesture.cancelsTouchesInView ? "C" : "-")"
                    result.append("\(shortTypeName(view))/\(shortTypeName(gesture)) \(state) \(flags)")
                }
                current = view.superview
            }
            return result
        }

        private func rectDescription(_ rect: CGRect) -> String {
            "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width))x\(Int(rect.height))"
        }

        private func shortTypeName(_ value: AnyObject) -> String {
            String(describing: type(of: value))
                .replacingOccurrences(of: "_TtGC7SwiftUI", with: "SwiftUI.")
        }

        private func gestureStateName(_ state: UIGestureRecognizer.State) -> String {
            switch state {
            case .possible: "possible"
            case .began: "began"
            case .changed: "changed"
            case .ended: "ended"
            case .cancelled: "cancelled"
            case .failed: "failed"
            @unknown default: "unknown"
            }
        }
    }
}

private final class ZoneEditorPassiveTouchRecognizer: UIGestureRecognizer {
    private let onFinished: (String, CGPoint, Bool) -> Void
    private var initialPoint: CGPoint?
    private var maxMovement: CGFloat = 0
    private var initialHitName = "nil"
    private static let tapMovementTolerance: CGFloat = 8

    init(onFinished: @escaping (String, CGPoint, Bool) -> Void) {
        self.onFinished = onFinished
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else { return }
        initialPoint = touch.location(in: view)
        maxMovement = 0
        initialHitName = touch.view.map { String(describing: type(of: $0)) } ?? "nil"
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first,
              let view,
              let initialPoint else { return }

        let point = touch.location(in: view)
        let dx = point.x - initialPoint.x
        let dy = point.y - initialPoint.y
        maxMovement = max(maxMovement, sqrt((dx * dx) + (dy * dy)))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else {
            state = .failed
            return
        }
        let point = touch.location(in: view)
        if let initialPoint {
            let dx = point.x - initialPoint.x
            let dy = point.y - initialPoint.y
            maxMovement = max(maxMovement, sqrt((dx * dx) + (dy * dy)))
        }
        onFinished(
            "ended/\(initialHitName)",
            point,
            maxMovement <= Self.tapMovementTolerance
        )
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if let point = initialPoint {
            onFinished("cancelled/\(initialHitName)", point, false)
        }
        state = .failed
    }

    override func reset() {
        initialPoint = nil
        maxMovement = 0
        initialHitName = "nil"
        super.reset()
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }
}

struct ZoneEditorScrollViewLocator: UIViewRepresentable {
    var onResolve: (UIScrollView?) -> Void

    func makeUIView(context: Context) -> ResolverView {
        let view = ResolverView()
        view.onResolve = onResolve
        return view
    }

    func updateUIView(_ uiView: ResolverView, context: Context) {
        uiView.onResolve = onResolve
        uiView.resolveSoon()
    }

    final class ResolverView: UIView {
        var onResolve: ((UIScrollView?) -> Void)?
        private weak var resolvedScrollView: UIScrollView?
        private var isResolveScheduled = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = false
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            resolveSoon()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            resolveSoon()
        }

        func resolveSoon() {
            guard !isResolveScheduled else { return }
            isResolveScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isResolveScheduled = false
                let scrollView = self.resolveScrollView()
                guard self.resolvedScrollView !== scrollView else { return }
                self.resolvedScrollView = scrollView
                self.onResolve?(scrollView)
            }
        }

        private func resolveScrollView() -> UIScrollView? {
            if let scrollView = nearestAncestorScrollView() {
                return scrollView
            }

            let resolverFrame = convert(bounds, to: nil)
            var view = superview
            while let candidate = view {
                let scrollViews = candidate.descendantScrollViews()
                if let bestMatch = scrollViews.max(by: { lhs, rhs in
                    lhs.convert(lhs.bounds, to: nil).intersection(resolverFrame).area
                        < rhs.convert(rhs.bounds, to: nil).intersection(resolverFrame).area
                }) {
                    let matchFrame = bestMatch.convert(bestMatch.bounds, to: nil)
                    if matchFrame.intersects(resolverFrame) || resolverFrame.isEmpty {
                        return bestMatch
                    }
                }
                view = candidate.superview
            }

            return nil
        }

        private func nearestAncestorScrollView() -> UIScrollView? {
            var view = superview
            while let candidate = view {
                if let scrollView = candidate as? UIScrollView {
                    return scrollView
                }
                view = candidate.superview
            }
            return nil
        }
    }
}

private extension UIView {
    func descendantScrollViews() -> [UIScrollView] {
        var result: [UIScrollView] = []
        for subview in subviews {
            if let scrollView = subview as? UIScrollView {
                result.append(scrollView)
            }
            result.append(contentsOf: subview.descendantScrollViews())
        }
        return result
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}

//
//  ZoneEditorCanvas.swift
//  QuizFlash
//
//  Reusable card canvas for zone-based authoring surfaces.
//

import SwiftUI
import UIKit

// MARK: - Zone Editor Canvas Tap Context

/// Card-local tap information used by owners to create zones semantically.
struct ZoneEditorCanvasTapContext {
    let location: CGPoint
    let contentSize: CGSize
    let zoneFrames: [ZoneEditorResolvedZoneFrame]
}

// MARK: - Zone Editor Canvas

/// A reusable editing canvas that renders a zone tree on the authoring surface.
struct ZoneEditorCanvas: View {
    @Bindable var content: ZoneCardContent
    @Binding var selectedPath: ZonePath?
    @Binding var previewDirection: AddDirection?

    let highlightContext: HighlightContext?
    let fontScale: CGFloat
    let verticalAlignmentFallback: ZoneVerticalAlignment
    let topContentInset: CGFloat
    let bottomAccessoryHeight: CGFloat
    let bottomAccessoryTopY: CGFloat?
    let scrollResetToken: Int
    let onScrollOffsetChange: (CGFloat) -> Void
    let onEmptySpaceTap: (ZoneEditorCanvasTapContext) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(DevelopmentPreferences.self) private var developmentPreferences
    @Environment(KeyboardMonitor.self) private var keyboardMonitor

    @State private var zoneFrames: [ZoneEditorResolvedZoneFrame] = []
    @State private var scheduledBottomChromeScrollTask: Task<Void, Never>?
    @State private var activeCaretPathID: String?
    @State private var activeCaretWindowRect: CGRect?
    @State private var lastKeyboardVisibleHeight: CGFloat = 0
    @State private var lastTapDebugLine: String = ""
    @State private var debugStore = ZoneEditorDebugStore.shared
    @State private var scrollDriver = ZoneEditorScrollDriver()

    private var focusManager: ZoneFocusManager { ZoneFocusManager.shared }

    private static let coordinateSpaceName = "ZoneEditorCanvasContent"

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var editorCardHorizontalPadding: CGFloat { isCompact ? 20 : 28 }
    private var editorCardVerticalPadding: CGFloat { isCompact ? 20 : 24 }

    var body: some View {
        GeometryReader { geometry in
            let horizontalInset: CGFloat = isCompact ? 12 : 24
            let maxEditorWidth: CGFloat = isCompact ? .infinity : 620
            let proposedWidth = max(geometry.size.width - (horizontalInset * 2), 1)
            let cardWidth = min(proposedWidth, maxEditorWidth)
            let editorViewportHeight = max(geometry.size.height - (UIConstants.Spacing.small * 2), 1)
            let contentWidth = max(cardWidth - (editorCardHorizontalPadding * 2), 1)
            let contentHeight = max(editorViewportHeight - (editorCardVerticalPadding * 2), 1)
            let scrollBottomAvoidanceInset = keyboardMonitor.isVisible
                ? max(keyboardMonitor.visibleHeight + activeBottomChromeClearance, 160)
                : 0
            let idleBottomCreationInset = max(editorViewportHeight * 0.45, 260)
            let bottomCreationTapInset = keyboardMonitor.isVisible
                ? scrollBottomAvoidanceInset
                : idleBottomCreationInset

            ScrollViewReader { _ in
                ScrollView(.vertical, showsIndicators: false) {
                    zoneContentSurface(
                        contentWidth: contentWidth,
                        contentHeight: contentHeight,
                        bottomCreationTapInset: bottomCreationTapInset
                    )
                    .padding(.horizontal, editorCardHorizontalPadding)
                    .padding(.top, editorCardVerticalPadding + topContentInset)
                    .padding(.bottom, editorCardVerticalPadding)
                    .frame(width: cardWidth, alignment: .topLeading)
                    .frame(minHeight: editorViewportHeight + topContentInset + bottomCreationTapInset, alignment: .topLeading)
                }
                .background {
                    ZoneEditorScrollViewLocator { scrollView in
                        scrollDriver.attach(scrollView)
                        scrollDriver.setTopInset(0)
                        scrollDriver.resetBottomInset()
                        scrollDriver.setScrollOffsetHandler(onScrollOffsetChange)
                    }
                }
                .scrollDismissesKeyboard(.never)
                .frame(width: cardWidth, height: editorViewportHeight, alignment: .topLeading)
                .overlay(alignment: .topLeading) {
                    debugOverlay
                        .padding(.leading, editorCardHorizontalPadding)
                        .padding(.top, topContentInset + 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, horizontalInset)
                .padding(.top, UIConstants.Spacing.small)
                .padding(.bottom, UIConstants.Spacing.small)
                .onChange(of: selectedPath) { _, newPath in
                    if newPath == nil {
                        cancelCaretAvoidanceScroll()
                        clearActiveCaretGeometry()
                    } else {
                        scrollDriver.preserveCurrentOffsetDuringNonUserFocus()
                        if keyboardMonitor.isVisible {
                            scheduleCaretAvoidanceScroll(delay: .milliseconds(16))
                        }
                    }
                    if activeCaretPathID != newPath?.id {
                        clearActiveCaretGeometry()
                    }
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: editorViewportHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onChange(of: keyboardMonitor.visibleHeight) { _, newHeight in
                    let oldHeight = lastKeyboardVisibleHeight
                    lastKeyboardVisibleHeight = newHeight
                    scrollDriver.preserveCurrentOffsetDuringNonUserFocus()
                    scrollDriver.resetBottomInset()

                    if newHeight <= 1, !keyboardMonitor.isVisible {
                        cancelCaretAvoidanceScroll()
                    } else if abs(newHeight - oldHeight) > 1 || shouldMaintainKeyboardAvoidance {
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(24))
                    }
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: editorViewportHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onChange(of: keyboardMonitor.isVisible) { _, isVisible in
                    lastKeyboardVisibleHeight = keyboardMonitor.visibleHeight
                    scrollDriver.resetBottomInset()
                    if isVisible {
                        scrollDriver.preserveCurrentOffsetDuringNonUserFocus()
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(24))
                    } else {
                        cancelCaretAvoidanceScroll()
                        if selectedPath == nil {
                            scrollDriver.resetToTop()
                        }
                    }
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: editorViewportHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onChange(of: focusManager.focusedZoneID) { _, focusedID in
                    if focusedID != nil {
                        scrollDriver.preserveCurrentOffsetDuringNonUserFocus()
                    }
                    if let focusedID,
                       let selectedPath,
                       content.zone(at: selectedPath)?.id == focusedID,
                       !keyboardMonitor.isVisible {
                        clearActiveCaretGeometry()
                    } else if shouldMaintainKeyboardAvoidance {
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(24))
                    }
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: editorViewportHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onChange(of: focusManager.pendingFocusZoneID) { _, _ in
                    scrollDriver.preserveCurrentOffsetDuringNonUserFocus()
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: editorViewportHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onChange(of: zoneFrames) { _, _ in
                    if shouldMaintainKeyboardAvoidance {
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(48))
                    }
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: editorViewportHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onChange(of: bottomAccessoryTopY) { _, _ in
                    scrollDriver.resetBottomInset()
                    if shouldMaintainKeyboardAvoidance {
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(24))
                    }
                }
                .onChange(of: bottomAccessoryHeight) { _, _ in
                    scrollDriver.resetBottomInset()
                    if shouldMaintainKeyboardAvoidance {
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(24))
                    }
                }
                .onChange(of: scrollResetToken) { _, _ in
                    cancelCaretAvoidanceScroll()
                    clearActiveCaretGeometry()
                    scrollDriver.resetBottomInset()
                    scrollDriver.resetToTop()
                }
                .onAppear {
                    scrollDriver.resetBottomInset()
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: editorViewportHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: .zoneEditorCaretMoved)) { notification in
                    guard let selectedPath,
                          notification.userInfo?[ZoneEditorCaretScrollNotification.pathIDKey] as? String == selectedPath.id else {
                        return
                    }

                    guard let caretRectInWindow = caretWindowRect(from: notification) else {
                        if shouldMaintainKeyboardAvoidance {
                            scheduleCaretAvoidanceScroll(delay: .milliseconds(16))
                        }
                        return
                    }

                    activeCaretPathID = selectedPath.id
                    activeCaretWindowRect = caretRectInWindow

                    if shouldMaintainKeyboardAvoidance {
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(16))
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .zoneEditorZoneTapped)) { notification in
                    guard let selectedPath,
                          notification.userInfo?[ZoneEditorCaretScrollNotification.pathIDKey] as? String == selectedPath.id else {
                        return
                    }

                    if keyboardMonitor.isVisible {
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(16))
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .zoneEditorWillFocusTextView)) { _ in
                    scrollDriver.preserveCurrentOffsetDuringNonUserFocus()
                }
                .onDisappear {
                    scheduledBottomChromeScrollTask?.cancel()
                    scheduledBottomChromeScrollTask = nil
                    scrollDriver.detach()
                }
            }
        }
    }

    private func zoneContentSurface(
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        bottomCreationTapInset: CGFloat
    ) -> some View {
        let tappableContentSize = CGSize(
            width: contentWidth,
            height: contentHeight + bottomCreationTapInset
        )

        return VStack(alignment: .leading, spacing: 0) {
            ZoneEditorView(
                content: content,
                path: .root,
                selectedPath: $selectedPath,
                highlightContext: highlightContext,
                fontScale: fontScale,
                availableWidth: contentWidth,
                maxEditableZoneHeight: contentHeight,
                previewDirection: $previewDirection
            )
            .frame(width: contentWidth, alignment: .topLeading)

            Color.clear
                .frame(width: contentWidth, height: contentHeight + bottomCreationTapInset)
                .contentShape(Rectangle())
                .gesture(emptySpaceTapGesture(contentSize: tappableContentSize))
        }
        .frame(width: contentWidth, alignment: .topLeading)
        .coordinateSpace(name: Self.coordinateSpaceName)
        .overlayPreferenceValue(ZoneEditorZoneBoundsPreferenceKey.self) { bounds in
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ZoneEditorResolvedZoneFramePreferenceKey.self,
                    value: bounds.map {
                        ZoneEditorResolvedZoneFrame(
                            path: $0.path,
                            zoneID: $0.zoneID,
                            frame: proxy[$0.bounds]
                        )
                    }
                )
            }
        }
        .onPreferenceChange(ZoneEditorResolvedZoneFramePreferenceKey.self) { frames in
            zoneFrames = frames
        }
    }

    private func emptySpaceTapGesture(contentSize: CGSize) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .named(Self.coordinateSpaceName))
            .onEnded { value in
                handleEmptySpaceTap(
                    location: value.location,
                    contentSize: contentSize
                )
            }
    }

    private func handleEmptySpaceTap(location: CGPoint, contentSize: CGSize) {
        guard !zoneFrames.contains(where: { $0.frame.contains(location) }) else {
            lastTapDebugLine = "tap zone/select"
            ZoneEditorDebugStore.shared.recordTap(lastTapDebugLine)
            return
        }

        lastTapDebugLine = "tap empty x=\(Int(location.x)) y=\(Int(location.y))"
        ZoneEditorDebugStore.shared.recordTap(lastTapDebugLine)
        onEmptySpaceTap(
            ZoneEditorCanvasTapContext(
                location: location,
                contentSize: contentSize,
                zoneFrames: zoneFrames
            )
        )
    }

    @discardableResult
    private func scrollFocusedEditingContentAboveBottomChromeIfNeeded() -> Bool {
        guard shouldMaintainKeyboardAvoidance else { return false }

        if hasActiveCaretGeometryForSelection {
            return scrollActiveCaretAboveBottomChromeIfNeeded()
        }

        return false
    }

    @discardableResult
    private func scrollActiveCaretAboveBottomChromeIfNeeded() -> Bool {
        guard activeCaretPathID == selectedPath?.id,
              keyboardMonitor.isVisible,
              isKeyboardAvoidanceChromeReady
        else { return false }

        guard let caretWindowRect = activeCaretWindowRect else { return false }

        let didScroll = scrollDriver.scrollWindowRectAboveBottomChromeIfNeeded(
            windowRect: caretWindowRect,
            bottomChromeTopY: bottomAccessoryTopY,
            keyboardHeight: keyboardMonitor.visibleHeight,
            bottomAccessoryHeight: bottomAccessoryHeight,
            bottomBuffer: caretBottomChromeBuffer,
            animationDuration: caretScrollAnimationDuration,
            animationOptions: keyboardMonitor.animationOptions
        )
        if didScroll {
            activeCaretWindowRect = nil
        }
        return didScroll
    }

    private func scheduleCaretAvoidanceScroll(
        delay: Duration = .milliseconds(120)
    ) {
        scheduledBottomChromeScrollTask?.cancel()
        guard shouldMaintainKeyboardAvoidance else { return }

        scheduledBottomChromeScrollTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, shouldMaintainKeyboardAvoidance else { return }

            let didScroll = scrollFocusedEditingContentAboveBottomChromeIfNeeded()
            if !didScroll, hasActiveCaretGeometryForSelection {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled, shouldMaintainKeyboardAvoidance else { return }
                _ = scrollFocusedEditingContentAboveBottomChromeIfNeeded()
            }
        }
    }

    private var shouldMaintainKeyboardAvoidance: Bool {
        guard keyboardMonitor.isVisible,
              let selectedPath,
              let focusedZoneID = focusManager.focusedZoneID else {
            return false
        }

        return content.zone(at: selectedPath)?.id == focusedZoneID
    }

    private var hasActiveCaretGeometryForSelection: Bool {
        activeCaretPathID == selectedPath?.id
            && activeCaretWindowRect != nil
    }

    private func cancelCaretAvoidanceScroll() {
        scheduledBottomChromeScrollTask?.cancel()
        scheduledBottomChromeScrollTask = nil
    }

    private var isKeyboardAvoidanceChromeReady: Bool {
        keyboardMonitor.isVisible
    }

    private func clearActiveCaretGeometry() {
        activeCaretPathID = nil
        activeCaretWindowRect = nil
    }

    private func caretWindowRect(from notification: Notification) -> CGRect? {
        guard let value = notification.userInfo?[ZoneEditorCaretScrollNotification.caretRectInWindowKey] else {
            return nil
        }

        if let rectValue = value as? NSValue {
            return rectValue.cgRectValue
        }

        return value as? CGRect
    }

    private var activeBottomChromeClearance: CGFloat {
        max(bottomAccessoryHeight, 0) + (keyboardMonitor.isVisible ? caretBottomChromeBuffer + 80 : 48)
    }

    private var caretBottomChromeBuffer: CGFloat {
        88
    }

    private var caretScrollAnimationDuration: TimeInterval {
        guard keyboardMonitor.isVisible else { return 0.16 }
        return min(max(keyboardMonitor.animationDuration, 0.12), 0.28)
    }


    @ViewBuilder
    private var debugOverlay: some View {
        if showsDebugTools {
            VStack(alignment: .leading, spacing: 3) {
                Button {
                    developmentPreferences.zoneEditorDebugHUDEnabled.toggle()
                } label: {
                    Text(developmentPreferences.zoneEditorDebugHUDEnabled ? "DBG ON" : "DBG")
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(developmentPreferences.zoneEditorDebugHUDEnabled ? .black : .orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            developmentPreferences.zoneEditorDebugHUDEnabled ? Color.orange : Color.black.opacity(0.62),
                            in: Capsule(style: .continuous)
                        )
                }
                .buttonStyle(.plain)

                if developmentPreferences.zoneEditorDebugHUDEnabled {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedDebugLine)
                        Text(lastTapDebugLine.isEmpty ? "tap idle" : lastTapDebugLine)
                        if let selectedFrame {
                            Text("rect \(Int(selectedFrame.width))x\(Int(selectedFrame.height)) @ \(Int(selectedFrame.minX)),\(Int(selectedFrame.minY))")
                        }
                        ForEach(Array(debugStore.hudLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                        }
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(6)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: UIConstants.Radius.small))
                    .allowsHitTesting(false)
                } else if showsGridDebugOverlay {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedDebugLine)
                        Text(lastTapDebugLine.isEmpty ? "tap idle" : lastTapDebugLine)
                        if let selectedFrame {
                            Text("rect \(Int(selectedFrame.width))x\(Int(selectedFrame.height)) @ \(Int(selectedFrame.minX)),\(Int(selectedFrame.minY))")
                        }
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(.orange)
                    .padding(UIConstants.Spacing.tiny)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: UIConstants.Radius.small))
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private var selectedDebugLine: String {
        guard let selectedPath, let zone = content.zone(at: selectedPath) else {
            return "selected nil"
        }

        return "selected \(selectedPath.id) size=\(zone.sizeMode.rawValue) block=\(zone.blockAlignment.rawValue) text=\(zone.textAlignment.rawValue)"
    }

    private var selectedFrame: CGRect? {
        guard let selectedPath else { return nil }
        return zoneFrames.first { $0.path == selectedPath }?.frame
    }

    private func updateCanvasDebug(cardSize: CGSize, contentSize: CGSize) {
        debugStore.updateCanvas(
            cardSize: cardSize,
            contentSize: contentSize,
            selectedFrame: selectedFrame,
            keyboardVisible: keyboardMonitor.isVisible,
            keyboardHeight: keyboardMonitor.visibleHeight
        )
        debugStore.updateFocusManager(
            focusedZoneID: focusManager.focusedZoneID,
            pendingZoneID: focusManager.pendingFocusZoneID,
            retainKeyboard: focusManager.shouldRetainKeyboard
        )
    }

    private var showsDebugTools: Bool {
        AppFeatures.current.showsVisualDebugOverlays
    }

    private var showsGridDebugOverlay: Bool {
        AppFeatures.current.showsVisualDebugOverlays
            && developmentPreferences.flashcardGridTextLayoutDebugEnabled
    }

}

// MARK: - Scroll Driver

@MainActor
private final class ZoneEditorScrollDriver {
    private weak var scrollView: UIScrollView?
    private var pendingTopInset: CGFloat = 0
    private var pendingBottomInset: CGFloat = 0
    private var appliedTopInset: CGFloat = 0
    private var appliedBottomInset: CGFloat = 0
    private var offsetObservation: NSKeyValueObservation?
    private var lockedOffset: CGPoint?
    private var offsetLockTask: Task<Void, Never>?
    private var isRestoringLockedOffset = false
    private var onScrollOffsetChange: ((CGFloat) -> Void)?
    private var lastReportedScrollOffsetY: CGFloat?

    func attach(_ scrollView: UIScrollView?) {
        guard self.scrollView !== scrollView else { return }
        offsetObservation?.invalidate()
        self.scrollView = scrollView
        guard let scrollView else {
            offsetObservation = nil
            lockedOffset = nil
            return
        }
        observeOffset(in: scrollView)
        reportScrollOffset(in: scrollView, force: true)
        applyContentInsetsIfNeeded()
    }

    func detach() {
        offsetObservation?.invalidate()
        offsetObservation = nil
        offsetLockTask?.cancel()
        offsetLockTask = nil
        lockedOffset = nil
        onScrollOffsetChange = nil
        lastReportedScrollOffsetY = nil
        scrollView = nil
    }

    func setScrollOffsetHandler(_ handler: @escaping (CGFloat) -> Void) {
        onScrollOffsetChange = handler
        if let scrollView {
            reportScrollOffset(in: scrollView, force: true)
        }
    }

    func setTopInset(_ inset: CGFloat) {
        let resolvedInset = max(inset, 0)
        let currentInset = scrollView?.contentInset.top ?? 0
        guard abs(pendingTopInset - resolvedInset) > 0.5
                || abs(currentInset - resolvedInset) > 0.5
        else { return }

        pendingTopInset = resolvedInset
        applyContentInsetsIfNeeded()
    }

    func resetBottomInset() {
        guard abs(pendingBottomInset) > 0.5
                || abs(scrollView?.contentInset.bottom ?? 0) > 0.5
        else { return }

        pendingBottomInset = 0
        applyContentInsetsIfNeeded()
    }

    func resetToTop() {
        guard let scrollView else { return }
        lockedOffset = nil
        scrollView.layer.removeAllAnimations()
        let minOffsetY = -scrollView.adjustedContentInset.top
        guard abs(scrollView.contentOffset.y - minOffsetY) > 0.5 else { return }
        UIView.performWithoutAnimation {
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: minOffsetY),
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

    @discardableResult
    func scrollWindowRectAboveBottomChromeIfNeeded(
        windowRect: CGRect,
        bottomChromeTopY: CGFloat?,
        keyboardHeight: CGFloat,
        bottomAccessoryHeight: CGFloat,
        bottomBuffer: CGFloat,
        animationDuration: TimeInterval,
        animationOptions: UIView.AnimationOptions
    ) -> Bool {
        guard let scrollView,
              scrollView.window != nil,
              scrollView.bounds.height > 0,
              scrollView.contentSize.height
                + scrollView.adjustedContentInset.top
                + scrollView.adjustedContentInset.bottom > scrollView.bounds.height
        else { return false }

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
        guard overlap > 0 else { return false }

        let targetY = clampedOffsetY(currentY + overlap, in: scrollView)
        guard abs(targetY - currentY) > 0.5 else { return false }

        clearOffsetLock()
        setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: targetY),
            in: scrollView,
            duration: animationDuration,
            options: animationOptions
        )
        return true
    }

    private func setContentOffset(
        _ offset: CGPoint,
        in scrollView: UIScrollView,
        duration: TimeInterval,
        options: UIView.AnimationOptions
    ) {
        scrollView.layer.removeAllAnimations()
        guard duration > 0.02 else {
            scrollView.setContentOffset(offset, animated: false)
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
        }
    }

    private func observeOffset(in scrollView: UIScrollView) {
        offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self, weak scrollView] _, _ in
            Task { @MainActor [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                self.handleObservedOffset(in: scrollView)
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
        guard let onScrollOffsetChange else { return }
        let normalizedOffsetY = max(0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
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

    private func applyContentInsetsIfNeeded() {
        guard let scrollView else { return }
        guard abs(appliedTopInset - pendingTopInset) > 0.5
                || abs(scrollView.contentInset.top - pendingTopInset) > 0.5
                || abs(appliedBottomInset - pendingBottomInset) > 0.5
                || abs(scrollView.contentInset.bottom - pendingBottomInset) > 0.5
        else { return }

        let oldMinOffsetY = -scrollView.adjustedContentInset.top
        let shouldKeepPinnedToTop = abs(scrollView.contentOffset.y - oldMinOffsetY) <= 1
            || scrollView.contentOffset.y < oldMinOffsetY

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

            let newMinOffsetY = -scrollView.adjustedContentInset.top
            if shouldKeepPinnedToTop || scrollView.contentOffset.y < newMinOffsetY {
                scrollView.setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: newMinOffsetY),
                    animated: false
                )
            }
        }
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
}

private struct ZoneEditorScrollViewLocator: UIViewRepresentable {
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
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
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

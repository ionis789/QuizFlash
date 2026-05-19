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

/// A reusable editing canvas that renders a zone tree on a real flashcard surface.
struct ZoneEditorCanvas: View {
    @Bindable var content: ZoneCardContent
    @Binding var selectedPath: ZonePath?
    @Binding var previewDirection: AddDirection?

    let highlightContext: HighlightContext?
    let fontScale: CGFloat
    let verticalAlignmentFallback: ZoneVerticalAlignment
    let bottomAccessoryHeight: CGFloat
    let bottomAccessoryTopY: CGFloat?
    let onEmptySpaceTap: (ZoneEditorCanvasTapContext) -> Void

    @Environment(\.colorScheme) private var colorScheme
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
    private static let playModeCardAspectRatio: CGFloat = 369.0 / 613.0

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var cardCornerRadius: CGFloat { isCompact ? 42 : 52 }
    private var editorCardHorizontalPadding: CGFloat { isCompact ? 20 : 28 }
    private var editorCardVerticalPadding: CGFloat { isCompact ? 20 : 24 }

    var body: some View {
        GeometryReader { geometry in
            let horizontalInset: CGFloat = isCompact ? 12 : 24
            let maxEditorWidth: CGFloat = isCompact ? .infinity : 620
            let proposedWidth = max(geometry.size.width - (horizontalInset * 2), 1)
            let cardWidth = min(proposedWidth, maxEditorWidth)
            let cardHeight = cardWidth / Self.playModeCardAspectRatio
            let contentWidth = max(cardWidth - (editorCardHorizontalPadding * 2), 1)
            let contentHeight = max(cardHeight - (editorCardVerticalPadding * 2), 1)
            let contentFrameAlignment: Alignment = .top
            let scrollBottomAvoidanceInset = keyboardMonitor.isVisible
                ? max(keyboardMonitor.visibleHeight + activeBottomChromeClearance, 160)
                : activeBottomChromeClearance

            ScrollViewReader { _ in
                ScrollView(.vertical, showsIndicators: false) {
                    zoneContentSurface(
                        contentWidth: contentWidth,
                        contentHeight: contentHeight,
                        contentFrameAlignment: contentFrameAlignment
                    )
                    .padding(.horizontal, editorCardHorizontalPadding)
                    .padding(.top, editorCardVerticalPadding)
                    .padding(.bottom, editorCardVerticalPadding + scrollBottomAvoidanceInset)
                    .frame(width: cardWidth, alignment: .topLeading)
                    .frame(minHeight: cardHeight + scrollBottomAvoidanceInset, alignment: .topLeading)
                }
                .background {
                    ZoneEditorScrollViewLocator { scrollView in
                        scrollDriver.attach(scrollView)
                        scrollDriver.resetBottomInset()
                    }
                }
                .scrollDismissesKeyboard(.never)
                .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
                .background(cardSurface)
                .overlay(cardBorder)
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    debugOverlay
                        .padding(editorCardHorizontalPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, horizontalInset)
                .padding(.top, UIConstants.Spacing.small)
                .padding(.bottom, UIConstants.Spacing.small)
                .onChange(of: selectedPath) { _, newPath in
                    if newPath == nil {
                        cancelCaretAvoidanceScroll()
                        clearActiveCaretGeometry()
                    } else if keyboardMonitor.isVisible {
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(16))
                    }
                    if activeCaretPathID != newPath?.id {
                        clearActiveCaretGeometry()
                    }
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: cardHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onChange(of: keyboardMonitor.visibleHeight) { _, newHeight in
                    let oldHeight = lastKeyboardVisibleHeight
                    lastKeyboardVisibleHeight = newHeight
                    scrollDriver.resetBottomInset()

                    if newHeight <= 1, !keyboardMonitor.isVisible {
                        cancelCaretAvoidanceScroll()
                    } else if abs(newHeight - oldHeight) > 1 || shouldMaintainKeyboardAvoidance {
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(24))
                    }
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: cardHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onChange(of: keyboardMonitor.isVisible) { _, isVisible in
                    lastKeyboardVisibleHeight = keyboardMonitor.visibleHeight
                    scrollDriver.resetBottomInset()
                    if isVisible {
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(24))
                    } else {
                        cancelCaretAvoidanceScroll()
                    }
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: cardHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onChange(of: focusManager.focusedZoneID) { _, focusedID in
                    if let focusedID,
                       let selectedPath,
                       content.zone(at: selectedPath)?.id == focusedID,
                       !keyboardMonitor.isVisible {
                        clearActiveCaretGeometry()
                    } else if shouldMaintainKeyboardAvoidance {
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(24))
                    }
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: cardHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onChange(of: focusManager.pendingFocusZoneID) { _, _ in
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: cardHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onChange(of: zoneFrames) { _, _ in
                    if shouldMaintainKeyboardAvoidance {
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(48))
                    }
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: cardHeight),
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
                .onAppear {
                    scrollDriver.resetBottomInset()
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: cardHeight),
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
        contentFrameAlignment: Alignment
    ) -> some View {
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
        .frame(minHeight: contentHeight, alignment: contentFrameAlignment)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(coordinateSpace: .named(Self.coordinateSpaceName))
                        .onEnded { value in
                            handleEmptySpaceTap(
                                location: value.location,
                                contentSize: CGSize(width: contentWidth, height: contentHeight)
                            )
                        }
                )
        }
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

    private func handleEmptySpaceTap(location: CGPoint, contentSize: CGSize) {
        guard !zoneFrames.contains(where: { $0.frame.insetBy(dx: -6, dy: -6).contains(location) }) else {
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
        40
    }

    private var caretScrollAnimationDuration: TimeInterval {
        guard keyboardMonitor.isVisible else { return 0.16 }
        return min(max(keyboardMonitor.animationDuration, 0.12), 0.28)
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            .fill(cardBackground)
            .shadow(color: shadowColor, radius: 12, y: 6)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            .stroke(borderColor, lineWidth: 1)
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

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(red: 0.068, green: 0.068, blue: 0.068))
            : AnyShapeStyle(Color(red: 0.92, green: 0.92, blue: 0.91))
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.42) : Color.black.opacity(0.12)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.08)
    }
}

// MARK: - Scroll Driver

@MainActor
private final class ZoneEditorScrollDriver {
    private weak var scrollView: UIScrollView?
    private var pendingBottomInset: CGFloat = 0
    private var appliedBottomInset: CGFloat = 0

    func attach(_ scrollView: UIScrollView?) {
        guard self.scrollView !== scrollView else { return }
        self.scrollView = scrollView
        applyBottomInsetIfNeeded()
    }

    func detach() {
        scrollView = nil
    }

    func resetBottomInset() {
        guard abs(pendingBottomInset) > 0.5
                || abs(scrollView?.contentInset.bottom ?? 0) > 0.5
        else { return }

        pendingBottomInset = 0
        applyBottomInsetIfNeeded()
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

    private func applyBottomInsetIfNeeded() {
        guard let scrollView else { return }
        guard abs(appliedBottomInset - pendingBottomInset) > 0.5
                || abs(scrollView.contentInset.bottom - pendingBottomInset) > 0.5
        else { return }

        appliedBottomInset = pendingBottomInset
        var contentInset = scrollView.contentInset
        contentInset.bottom = pendingBottomInset
        var verticalIndicatorInsets = scrollView.verticalScrollIndicatorInsets
        verticalIndicatorInsets.bottom = pendingBottomInset

        UIView.performWithoutAnimation {
            scrollView.contentInset = contentInset
            scrollView.verticalScrollIndicatorInsets = verticalIndicatorInsets
            scrollView.layoutIfNeeded()
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

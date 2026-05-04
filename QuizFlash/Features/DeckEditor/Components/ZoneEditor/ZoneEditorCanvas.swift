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
    let onEmptySpaceTap: (ZoneEditorCanvasTapContext) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(DevelopmentPreferences.self) private var developmentPreferences
    @Environment(KeyboardMonitor.self) private var keyboardMonitor

    @State private var zoneFrames: [ZoneEditorResolvedZoneFrame] = []
    @State private var scheduledScrollTask: Task<Void, Never>?
    @State private var scheduledResizeScrollTask: Task<Void, Never>?
    @State private var lastTapDebugLine: String = ""
    @State private var debugStore = ZoneEditorDebugStore.shared
    @State private var resizeScrollDriver = ZoneResizeAutoscrollDriver()

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
            let estimatedContentSize = FlashcardGridContentEstimator.estimatedSize(
                for: content.rootZone,
                fontScale: fontScale,
                availableWidth: contentWidth
            )
            let contentFitsVertically = estimatedContentSize.height <= contentHeight
            let resolvedVerticalAlignment = content.rootZone.verticalAlignment.resolved(
                fallback: verticalAlignmentFallback
            )
            let contentFrameAlignment: Alignment = contentFitsVertically
                ? frameAlignment(for: resolvedVerticalAlignment)
                : .top
            let keyboardAvoidanceInset = keyboardMonitor.isVisible
                ? max(keyboardMonitor.visibleHeight + UIConstants.Spacing.extraLarge, 160)
                : 0

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    zoneContentSurface(
                        contentWidth: contentWidth,
                        contentHeight: contentHeight,
                        contentFrameAlignment: contentFrameAlignment
                    )
                    .padding(.horizontal, editorCardHorizontalPadding)
                    .padding(.top, editorCardVerticalPadding)
                    .padding(.bottom, editorCardVerticalPadding + keyboardAvoidanceInset)
                    .frame(width: cardWidth, alignment: .topLeading)
                    .frame(minHeight: cardHeight + keyboardAvoidanceInset, alignment: .topLeading)
                }
                .background {
                    ZoneEditorScrollViewLocator { scrollView in
                        resizeScrollDriver.attach(scrollView)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
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
                    scheduleSelectionScroll(to: newPath, in: proxy)
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: cardHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onChange(of: keyboardMonitor.visibleHeight) { _, _ in
                    scheduleSelectionScroll(to: selectedPath, in: proxy)
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: cardHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onChange(of: keyboardMonitor.isVisible) { _, _ in
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: cardHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onChange(of: focusManager.focusedZoneID) { _, _ in
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
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: cardHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onAppear {
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

                    let rawAnchor = notification.userInfo?[ZoneEditorCaretScrollNotification.anchorYKey]
                    let requestedAnchorY: CGFloat
                    if let number = rawAnchor as? NSNumber {
                        requestedAnchorY = CGFloat(number.doubleValue)
                    } else if let value = rawAnchor as? CGFloat {
                        requestedAnchorY = value
                    } else if let value = rawAnchor as? Double {
                        requestedAnchorY = CGFloat(value)
                    } else {
                        requestedAnchorY = 0.5
                    }
                    let anchorY = min(max(requestedAnchorY, 0.08), 0.92)
                    scheduleSelectionScroll(
                        to: selectedPath,
                        in: proxy,
                        anchor: UnitPoint(x: 0.5, y: keyboardMonitor.isVisible ? anchorY : 0.5)
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: .zoneEditorResizeHandleMoved)) { notification in
                    guard let selectedPath,
                          notification.userInfo?[ZoneEditorResizeScrollNotification.pathIDKey] as? String == selectedPath.id else {
                        return
                    }

                    let rawAnchor = notification.userInfo?[ZoneEditorResizeScrollNotification.anchorYKey]
                    let requestedAnchorY: CGFloat
                    if let number = rawAnchor as? NSNumber {
                        requestedAnchorY = CGFloat(number.doubleValue)
                    } else if let value = rawAnchor as? CGFloat {
                        requestedAnchorY = value
                    } else if let value = rawAnchor as? Double {
                        requestedAnchorY = CGFloat(value)
                    } else {
                        requestedAnchorY = 0.86
                    }

                    let rawDeltaY = notification.userInfo?[ZoneEditorResizeScrollNotification.deltaYKey]
                    let deltaY: CGFloat
                    if let number = rawDeltaY as? NSNumber {
                        deltaY = CGFloat(number.doubleValue)
                    } else if let value = rawDeltaY as? CGFloat {
                        deltaY = value
                    } else if let value = rawDeltaY as? Double {
                        deltaY = CGFloat(value)
                    } else {
                        deltaY = 0
                    }

                    if resizeScrollDriver.scrollForResize(deltaY: deltaY) {
                        return
                    }

                    scheduleResizeScroll(
                        to: selectedPath,
                        in: proxy,
                        anchor: UnitPoint(x: 0.5, y: min(max(requestedAnchorY, 0.08), 0.94))
                    )
                }
                .onDisappear {
                    scheduledScrollTask?.cancel()
                    scheduledScrollTask = nil
                    scheduledResizeScrollTask?.cancel()
                    scheduledResizeScrollTask = nil
                    resizeScrollDriver.detach()
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

    private func frameAlignment(for verticalAlignment: ZoneVerticalAlignment) -> Alignment {
        switch verticalAlignment {
        case .auto, .center:
            return .center
        case .top:
            return .top
        case .bottom:
            return .bottom
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

    private func scheduleSelectionScroll(
        to path: ZonePath?,
        in proxy: ScrollViewProxy,
        anchor: UnitPoint? = nil
    ) {
        scheduledScrollTask?.cancel()
        guard let path else { return }

        scheduledScrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            let resolvedAnchor = anchor ?? (keyboardMonitor.isVisible ? .top : .center)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                proxy.scrollTo(path.id, anchor: resolvedAnchor)
            }
        }
    }

    private func scheduleResizeScroll(
        to path: ZonePath?,
        in proxy: ScrollViewProxy,
        anchor: UnitPoint
    ) {
        scheduledResizeScrollTask?.cancel()
        guard let path else { return }

        scheduledResizeScrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(18))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.14)) {
                proxy.scrollTo(path.id, anchor: anchor)
            }
        }
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

// MARK: - Resize Autoscroll

@MainActor
private final class ZoneResizeAutoscrollDriver {
    private weak var scrollView: UIScrollView?
    private var lastScrollTime: TimeInterval = 0

    func attach(_ scrollView: UIScrollView?) {
        guard self.scrollView !== scrollView else { return }
        self.scrollView = scrollView
        lastScrollTime = 0
    }

    func detach() {
        scrollView = nil
        lastScrollTime = 0
    }

    func scrollForResize(deltaY: CGFloat) -> Bool {
        guard let scrollView,
              scrollView.bounds.height > 0,
              abs(deltaY) >= 0.5
        else {
            return false
        }

        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastScrollTime >= 1.0 / 45.0 else {
            return true
        }

        let currentY = scrollView.contentOffset.y
        let direction: CGFloat = deltaY > 0 ? 1 : -1
        let distance = min(max(abs(deltaY) * 0.45, 5), 24)
        let minOffsetY = -scrollView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        let targetY = min(max(currentY + direction * distance, minOffsetY), maxOffsetY)

        guard abs(targetY - currentY) > 0.25 else {
            return true
        }

        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: targetY),
            animated: false
        )
        lastScrollTime = now
        return true
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
                let scrollView = self.nearestAncestorScrollView()
                guard self.resolvedScrollView !== scrollView else { return }
                self.resolvedScrollView = scrollView
                self.onResolve?(scrollView)
            }
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

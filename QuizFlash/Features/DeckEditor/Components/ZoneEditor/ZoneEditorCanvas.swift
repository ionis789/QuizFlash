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

private enum ZoneAlignmentDirection {
    case left
    case right
}

private struct ZoneAlignmentMenuState: Equatable {
    let target: ZoneAlignmentTargetRef
    let tappedPath: ZonePath
    var frame: CGRect
    var anchor: CGPoint
    var movementWidth: CGFloat
    var currentAlignment: ZoneBlockAlignment

    var id: String {
        "\(target.path.id)-\(target.kind.debugName)"
    }
}

private final class ZoneAlignmentFrameGate {
    var isFrozen = false
    var pendingFrames: [ZoneEditorResolvedZoneFrame]?
}

private struct ZoneAlignmentGroupContext {
    let parentPath: ZonePath
    let parentZone: ZoneModel
    let childPath: ZonePath
    let childFrame: CGRect
    let siblingFrames: [ZoneEditorResolvedZoneFrame]
}

private nonisolated struct ZoneEditorLayoutStartGeometry: Equatable, Sendable {
    let screenFrame: CGRect
    let contentFrame: CGRect
}

private struct ZoneEditorLayoutDebugSnapshot: Equatable {
    let mode: String
    var screenY: CGFloat
    var contentY: CGFloat
    var scrollY: CGFloat
    var frame: CGRect
    var topInset: CGFloat
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    var path: String
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
    let scrollRestorationRequest: ZoneEditorScrollRestorationRequest?
    let rendersRichText: Bool
    let showsDebugOverlays: Bool
    let onScrollOffsetChange: (CGFloat) -> Void
    let onEmptySpaceTap: (ZoneEditorCanvasTapContext) -> Void
    let onScrollRestorationApplied: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(DevelopmentPreferences.self) private var developmentPreferences
    @Environment(KeyboardMonitor.self) private var keyboardMonitor

    @State private var zoneFrames: [ZoneEditorResolvedZoneFrame] = []
    @State private var scheduledBottomChromeScrollTask: Task<Void, Never>?
    @State private var activeCaretPathID: String?
    @State private var activeCaretWindowRect: CGRect?
    @State private var lastKeyboardVisibleHeight: CGFloat = 0
    @State private var lastTapDebugLine: String = ""
    private let debugStore = ZoneEditorDebugStore.shared
    @State private var scrollDriver = ZoneEditorScrollDriver()
    @State private var alignmentMenuState: ZoneAlignmentMenuState?
    @State private var alignmentWiggleTarget: ZoneAlignmentTargetRef?
    @State private var alignmentWiggleOffset: CGFloat = 0
    @State private var alignmentWiggleTask: Task<Void, Never>?
    @State private var alignmentFrameUpdateTask: Task<Void, Never>?
    @State private var alignmentFrameGate = ZoneAlignmentFrameGate()
    @State private var renderMeasuredContentSize: CGSize = .zero
    @State private var pendingScrollRestorationRequest: ZoneEditorScrollRestorationRequest?
    @State private var viewportScreenFrame: CGRect = .zero
    @State private var rawLayoutDebugSnapshot: ZoneEditorLayoutDebugSnapshot?
    @State private var renderLayoutDebugSnapshot: ZoneEditorLayoutDebugSnapshot?
    @State private var lastLayoutDebugSnapshotTime: CFTimeInterval = 0
    @State private var windowTouchDebugLines: [String] = []

    private var focusManager: ZoneFocusManager { ZoneFocusManager.shared }

    private static let coordinateSpaceName = "ZoneEditorCanvasContent"
    private static let alignmentTolerance: CGFloat = 1
    private static let alignmentMenuSize = CGSize(width: 104, height: 44)
    private static let renderHitSlop: CGFloat = 8

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var renderScreenHorizontalPadding: CGFloat {
        isCompact
            ? FlashcardPlayLayoutTuning.screenToCardHorizontalPaddingCompact
            : FlashcardPlayLayoutTuning.screenToCardHorizontalPaddingRegular
    }
    private var contentHorizontalPadding: CGFloat {
        isCompact
            ? FlashcardPlayLayoutTuning.cardToContentHorizontalPaddingCompact
            : FlashcardPlayLayoutTuning.cardToContentHorizontalPaddingRegular
    }
    private var contentVerticalPadding: CGFloat {
        isCompact
            ? FlashcardPlayLayoutTuning.cardToContentVerticalPaddingCompact
            : FlashcardPlayLayoutTuning.cardToContentVerticalPaddingRegular
    }

    init(
        content: ZoneCardContent,
        selectedPath: Binding<ZonePath?>,
        previewDirection: Binding<AddDirection?>,
        highlightContext: HighlightContext?,
        fontScale: CGFloat,
        verticalAlignmentFallback: ZoneVerticalAlignment,
        topContentInset: CGFloat,
        bottomAccessoryHeight: CGFloat,
        bottomAccessoryTopY: CGFloat?,
        scrollResetToken: Int,
        scrollRestorationRequest: ZoneEditorScrollRestorationRequest? = nil,
        rendersRichText: Bool = false,
        showsDebugOverlays: Bool = true,
        onScrollOffsetChange: @escaping (CGFloat) -> Void,
        onEmptySpaceTap: @escaping (ZoneEditorCanvasTapContext) -> Void,
        onScrollRestorationApplied: @escaping () -> Void = {}
    ) {
        self.content = content
        self._selectedPath = selectedPath
        self._previewDirection = previewDirection
        self.highlightContext = highlightContext
        self.fontScale = fontScale
        self.verticalAlignmentFallback = verticalAlignmentFallback
        self.topContentInset = topContentInset
        self.bottomAccessoryHeight = bottomAccessoryHeight
        self.bottomAccessoryTopY = bottomAccessoryTopY
        self.scrollResetToken = scrollResetToken
        self.scrollRestorationRequest = scrollRestorationRequest
        self.rendersRichText = rendersRichText
        self.showsDebugOverlays = showsDebugOverlays
        self.onScrollOffsetChange = onScrollOffsetChange
        self.onEmptySpaceTap = onEmptySpaceTap
        self.onScrollRestorationApplied = onScrollRestorationApplied
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalInset: CGFloat = renderScreenHorizontalPadding
            let maxEditorWidth: CGFloat = isCompact ? .infinity : 620
            let proposedWidth = max(geometry.size.width - (horizontalInset * 2), 1)
            let cardWidth = min(proposedWidth, maxEditorWidth)
            let editorViewportHeight = max(geometry.size.height - (UIConstants.Spacing.small * 2), 1)
            let surfaceHorizontalPadding = contentHorizontalPadding
            let surfaceVerticalPadding = contentVerticalPadding
            let contentWidth = max(cardWidth - (surfaceHorizontalPadding * 2), 1)
            let contentHeight = max(editorViewportHeight - (surfaceVerticalPadding * 2), 1)
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
                    .padding(.horizontal, surfaceHorizontalPadding)
                    .padding(.top, surfaceVerticalPadding + topContentInset)
                    .padding(.bottom, surfaceVerticalPadding)
                    .frame(width: cardWidth, alignment: .topLeading)
                    .frame(minHeight: editorViewportHeight + topContentInset + bottomCreationTapInset, alignment: .topLeading)
                }
                .background {
                    ZoneEditorScrollViewLocator { scrollView in
                        scrollDriver.attach(scrollView)
                        scrollDriver.setTopInset(0)
                        scrollDriver.resetBottomInset()
                        scrollDriver.setScrollOffsetHandler(handleScrollOffsetChange)
                    configureTapProbe()
                    }
                }
                .scrollDismissesKeyboard(.never)
                .frame(width: cardWidth, height: editorViewportHeight, alignment: .topLeading)
                .background(windowTouchProbeBackground)
                .overlay(alignment: .topLeading) {
                    viewportDebugOverlay
                }
                .overlay(alignment: .bottomLeading) {
                    debugOverlay
                        .padding(.leading, contentHorizontalPadding)
                        .padding(.bottom, 72)
                }
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { newFrame in
                    viewportScreenFrame = newFrame
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, horizontalInset)
                .padding(.top, UIConstants.Spacing.small)
                .padding(.bottom, UIConstants.Spacing.small)
                .onChange(of: selectedPath) { _, newPath in
                    if newPath == nil {
                        cancelCaretAvoidanceScroll()
                        clearActiveCaretGeometry()
                        dismissAlignmentMenu()
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
                    attemptPendingScrollRestoration(
                        cardWidth: cardWidth,
                        editorViewportHeight: editorViewportHeight,
                        contentWidth: contentWidth,
                        contentHeight: contentHeight
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
                    dismissAlignmentMenu()
                    scrollDriver.resetBottomInset()
                    scrollDriver.resetToTop()
                }
                .onChange(of: scrollRestorationRequest) { _, request in
                    pendingScrollRestorationRequest = request
                    attemptPendingScrollRestoration(
                        cardWidth: cardWidth,
                        editorViewportHeight: editorViewportHeight,
                        contentWidth: contentWidth,
                        contentHeight: contentHeight
                    )
                }
                .onChange(of: rendersRichText) { _, isRendered in
                    dismissAlignmentMenu()
                    thawFrameUpdates()
                    scrollDriver.preserveCurrentOffsetDuringNonUserFocus(duration: .milliseconds(1200))
                    if !isRendered {
                        zoneFrames = []
                    }
                    renderMeasuredContentSize = .zero
                    attemptPendingScrollRestoration(
                        cardWidth: cardWidth,
                        editorViewportHeight: editorViewportHeight,
                        contentWidth: contentWidth,
                        contentHeight: contentHeight
                    )
                }
                .onChange(of: renderMeasuredContentSize) { _, _ in
                    attemptPendingScrollRestoration(
                        cardWidth: cardWidth,
                        editorViewportHeight: editorViewportHeight,
                        contentWidth: contentWidth,
                        contentHeight: contentHeight
                    )
                }
                .onAppear {
                    scrollDriver.resetBottomInset()
                    pendingScrollRestorationRequest = scrollRestorationRequest
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: editorViewportHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                    attemptPendingScrollRestoration(
                        cardWidth: cardWidth,
                        editorViewportHeight: editorViewportHeight,
                        contentWidth: contentWidth,
                        contentHeight: contentHeight
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

                    handleZoneTapNotification(notification, contentWidth: contentWidth)

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
                    alignmentWiggleTask?.cancel()
                    alignmentWiggleTask = nil
                    thawFrameUpdates()
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
        let layout = contentLayoutMetrics(
            contentSize: CGSize(width: contentWidth, height: contentHeight)
        )
        let tappableContentSize = CGSize(
            width: contentWidth,
            height: contentHeight + bottomCreationTapInset
        )

        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if rendersRichText {
                    renderContentView(
                        containerSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                    .overlay(alignment: .topLeading) {
                        layoutStartMarker(
                            mode: "RENDER",
                            layout: layout,
                            horizontalPadding: contentHorizontalPadding,
                            verticalPadding: contentVerticalPadding
                        )
                        .offset(y: layout.contentTopInset)
                    }
                } else {
                    ZoneEditorView(
                        content: content,
                        path: .root,
                        selectedPath: $selectedPath,
                        highlightContext: highlightContext,
                        fontScale: fontScale,
                        availableWidth: contentWidth,
                        maxEditableZoneHeight: contentHeight,
                        rendersRichText: false,
                        alignmentFeedback: .inactive,
                        previewDirection: $previewDirection
                    )
                    .frame(width: contentWidth, alignment: .topLeading)
                    .padding(.top, layout.contentTopInset)
                    .padding(.bottom, layout.contentBottomInset)
                    .overlay(alignment: .topLeading) {
                        layoutStartMarker(
                            mode: "RAW",
                            layout: layout,
                            horizontalPadding: contentHorizontalPadding,
                            verticalPadding: contentVerticalPadding
                        )
                        .offset(y: layout.contentTopInset)
                    }
                }
            }
            .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .simultaneousGesture(
                emptySpaceTapGesture(contentSize: tappableContentSize),
                including: rendersRichText ? .none : .all
            )
            .overlay {
                usefulSurfaceDebugOutline
            }

            Color.clear
                .frame(width: contentWidth, height: contentHeight + bottomCreationTapInset)
                .contentShape(Rectangle())
                .gesture(emptySpaceTapGesture(contentSize: tappableContentSize))
        }
        .frame(width: contentWidth, alignment: .topLeading)
        .coordinateSpace(name: Self.coordinateSpaceName)
        .coordinateSpace(name: ZoneContentRenderCoordinateSpace.name)
        .overlayPreferenceValue(ZoneEditorZoneBoundsPreferenceKey.self) { bounds in
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ZoneEditorResolvedZoneFramePreferenceKey.self,
                    value: rendersRichText ? [] : bounds.map {
                        ZoneEditorResolvedZoneFrame(
                            path: $0.path,
                            zoneID: $0.zoneID,
                            frame: proxy[$0.bounds]
                        )
                    }
                )
            }
        }
        .overlayPreferenceValue(ZoneContentRenderBlockBoundsPreferenceKey.self) { bounds in
            Color.clear.preference(
                key: ZoneEditorResolvedZoneFramePreferenceKey.self,
                value: rendersRichText ? bounds.compactMap { bound in
                    guard let path = findPath(for: bound.zoneID, in: content.rootZone) else {
                        return nil
                    }

                    return ZoneEditorResolvedZoneFrame(
                        path: path,
                        zoneID: bound.zoneID,
                        frame: bound.frame
                    )
                } : []
            )
        }
        .onPreferenceChange(ZoneEditorResolvedZoneFramePreferenceKey.self) { frames in
            handleResolvedZoneFrames(frames, contentWidth: contentWidth)
        }
        .overlay(alignment: .topLeading) {
            renderHitTargetOverlay(contentWidth: contentWidth)
        }
        .overlay(alignment: .topLeading) {
            alignmentOverlay(contentWidth: contentWidth)
        }
    }

    private func renderContentView(contentWidth: CGFloat) -> some View {
        let faceVerticalAlignment: ZoneVerticalAlignment = .top

        let availableContentWidth = max(contentWidth, 1)
        let estimatedContentSize = ZoneContentEstimator.estimatedSize(
            for: content.rootZone,
            fontScale: fontScale,
            availableWidth: availableContentWidth
        )
        let layout = ZoneContentLayout(
            containerSize: CGSize(width: contentWidth, height: 1),
            horizontalPadding: 0,
            verticalPadding: 0,
            estimatedContentSize: estimatedContentSize,
            measuredContentSize: renderMeasuredContentSize,
            verticalAlignment: faceVerticalAlignment
        )

        return renderContentView(layout: layout, faceVerticalAlignment: faceVerticalAlignment)
    }

    private func renderContentView(containerSize: CGSize) -> some View {
        let faceVerticalAlignment: ZoneVerticalAlignment = .top
        let availableContentWidth = max(containerSize.width, 1)
        let estimatedContentSize = ZoneContentEstimator.estimatedSize(
            for: content.rootZone,
            fontScale: fontScale,
            availableWidth: availableContentWidth
        )
        let layout = ZoneContentLayout(
            containerSize: containerSize,
            horizontalPadding: 0,
            verticalPadding: 0,
            estimatedContentSize: estimatedContentSize,
            measuredContentSize: renderMeasuredContentSize,
            verticalAlignment: faceVerticalAlignment
        )

        return renderContentView(layout: layout, faceVerticalAlignment: faceVerticalAlignment)
    }

    private func renderContentView(
        layout: ZoneContentLayout,
        faceVerticalAlignment: ZoneVerticalAlignment
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if showsGridDebugOverlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        Color.cyan.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.6, dash: [7, 5])
                    )
                    .frame(
                        width: layout.debugAvailableFrame.width,
                        height: layout.debugAvailableFrame.height,
                        alignment: .topLeading
                    )
                    .padding(.leading, layout.horizontalPadding)
                    .padding(.top, layout.verticalPadding)
                    .allowsHitTesting(false)
            }

            ZoneContentRenderView(
                zone: content.rootZone,
                fontScale: fontScale,
                availableWidth: layout.availableContentWidth,
                centersLeafBlocks: faceVerticalAlignment == .center,
                showsDebugGuides: showsGridDebugOverlay,
                alignmentFeedback: alignmentFeedback,
                collectsDebugMetrics: false,
                leafTapBehavior: .all,
                onZoneTap: { zoneID in
                    handleRenderedZoneTap(zoneID, contentWidth: layout.containerSize.width)
                }
            )
            .frame(width: layout.availableContentWidth, alignment: .topLeading)
            .onGeometryChange(for: CGSize.self) { proxy in
                CGSize(
                    width: ceil(proxy.size.width),
                    height: ceil(proxy.size.height)
                )
            } action: { newSize in
                guard newSize.width > 0, newSize.height > 0 else { return }
                let oldSize = renderMeasuredContentSize
                if abs(oldSize.width - newSize.width) > 0.5
                    || abs(oldSize.height - newSize.height) > 0.5 {
                    renderMeasuredContentSize = newSize
                }
            }
            .padding(.top, layout.verticalPadding + layout.contentTopInset)
            .padding(.leading, layout.horizontalPadding)
            .padding(.bottom, layout.verticalPadding + layout.contentBottomInset)
        }
        .frame(
            width: layout.containerSize.width,
            height: layout.scrollContentHeight,
            alignment: .topLeading
        )
        .contentShape(Rectangle())
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
        if alignmentMenuState != nil {
            dismissAlignmentMenu()
            lastTapDebugLine = "tap dismiss alignment menu"
            ZoneEditorDebugStore.shared.recordTap(lastTapDebugLine)
            return
        }

        if rendersRichText {
            lastTapDebugLine = "render tap empty x=\(Int(location.x)) y=\(Int(location.y))"
            ZoneEditorDebugStore.shared.recordTap(lastTapDebugLine)
            selectedPath = nil
            return
        }

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

    private func handleRenderedZoneTap(_ zoneID: UUID, contentWidth: CGFloat) {
        guard rendersRichText,
              let path = findPath(for: zoneID, in: content.rootZone) else {
            lastTapDebugLine = "render leaf tap unresolved zone=\(zoneID.uuidString.prefix(6))"
            ZoneEditorDebugStore.shared.recordTap(lastTapDebugLine)
            return
        }

        selectedPath = path
        focusManager.forceReleaseKeyboard()
        ZoneController.shared.forceReleaseKeyboard()
        ZoneController.shared.updateFocusedZone(nil)
        lastTapDebugLine = "render leaf tap path=\(path.id) zone=\(zoneID.uuidString.prefix(6))"
        ZoneEditorDebugStore.shared.recordTap(lastTapDebugLine)
        presentAlignmentMenu(for: path, contentWidth: contentWidth)
    }

    @ViewBuilder
    private func renderHitTargetOverlay(contentWidth: CGFloat) -> some View {
        if rendersRichText {
            ZStack(alignment: .topLeading) {
                ForEach(zoneFrames, id: \.zoneID) { resolvedFrame in
                    Color.clear
                        .frame(
                            width: max(resolvedFrame.frame.width, 1),
                            height: max(resolvedFrame.frame.height, 1)
                        )
                        .contentShape(Rectangle())
                        .position(x: resolvedFrame.frame.midX, y: resolvedFrame.frame.midY)
                        .onTapGesture {
                            handleRenderedZoneTap(resolvedFrame.zoneID, contentWidth: contentWidth)
                        }
                }
            }
            .allowsHitTesting(true)
        }
    }

    private func nearestFrameDebug(to location: CGPoint) -> String {
        guard let nearest = zoneFrames.min(by: {
            distance(from: $0.frame, to: location) < distance(from: $1.frame, to: location)
        }) else {
            return "nil"
        }

        return "\(nearest.path.id):\(Int(distance(from: nearest.frame, to: location)))"
    }

    private func distance(from frame: CGRect, to point: CGPoint) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return sqrt((dx * dx) + (dy * dy))
    }

    private var alignmentFeedback: ZoneAlignmentFeedback {
        ZoneAlignmentFeedback(
            highlightedTarget: alignmentMenuState?.target,
            wiggleTarget: alignmentWiggleTarget,
            wiggleOffset: alignmentWiggleOffset
        )
    }

    private func handleZoneTapNotification(_ notification: Notification, contentWidth: CGFloat) {
        guard rendersRichText else { return }

        let pathID = notification.userInfo?[ZoneEditorCaretScrollNotification.pathIDKey] as? String
        let tappedPath = pathID
            .flatMap { pathID in zoneFrames.first(where: { $0.path.id == pathID })?.path }
            ?? selectedPath

        guard let tappedPath,
              content.zone(at: tappedPath) != nil else {
            return
        }

        if rendersRichText {
            focusManager.forceReleaseKeyboard()
            ZoneController.shared.forceReleaseKeyboard()
            ZoneController.shared.updateFocusedZone(nil)
        }

        presentAlignmentMenu(for: tappedPath, contentWidth: contentWidth)
    }

    private func presentAlignmentMenu(for tappedPath: ZonePath, contentWidth: CGFloat) {
        guard let state = resolvedAlignmentMenuState(for: tappedPath, contentWidth: contentWidth, frames: zoneFrames) else {
            ZoneEditorDebugStore.shared.recordAlignment("align resolve failed tapped=\(tappedPath.id)")
            return
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            alignmentMenuState = state
        }
        ZoneEditorDebugStore.shared.recordAlignment(debugSummary(for: state, action: "present"))
    }

    private func refreshAlignmentMenu(contentWidth: CGFloat, frames: [ZoneEditorResolvedZoneFrame]) {
        guard let currentState = alignmentMenuState,
              let refreshedState = resolvedAlignmentMenuState(
                for: currentState.tappedPath,
                contentWidth: contentWidth,
                frames: frames
              ) else {
            if alignmentMenuState != nil {
                dismissAlignmentMenu()
            }
            return
        }

        if refreshedState != currentState {
            alignmentMenuState = refreshedState
        }
    }

    private func dismissAlignmentMenu() {
        guard alignmentMenuState != nil else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            alignmentMenuState = nil
        }
        alignmentWiggleTask?.cancel()
        alignmentWiggleTask = nil
        alignmentWiggleTarget = nil
        alignmentWiggleOffset = 0
        thawFrameUpdates()
    }

    @ViewBuilder
    private func alignmentOverlay(contentWidth: CGFloat) -> some View {
        if let menuState = alignmentMenuState {
            alignmentMenu(for: menuState, contentWidth: contentWidth)
                .zIndex(4)
        }
    }

    private func handleResolvedZoneFrames(
        _ frames: [ZoneEditorResolvedZoneFrame],
        contentWidth: CGFloat
    ) {
        guard rendersRichText else {
            commitResolvedZoneFrames(frames, contentWidth: contentWidth, refreshMenu: false)
            return
        }

        guard !alignmentFrameGate.isFrozen else {
            alignmentFrameGate.pendingFrames = frames
            return
        }

        commitResolvedZoneFrames(
            frames,
            contentWidth: contentWidth,
            refreshMenu: alignmentMenuState != nil && alignmentWiggleTarget == nil
        )
    }

    private func commitResolvedZoneFrames(
        _ frames: [ZoneEditorResolvedZoneFrame],
        contentWidth: CGFloat,
        refreshMenu: Bool
    ) {
        guard !resolvedFramesMatch(zoneFrames, frames) else { return }

        zoneFrames = frames
        if refreshMenu {
            refreshAlignmentMenu(contentWidth: contentWidth, frames: frames)
        }
    }

    private func resolvedFramesMatch(
        _ lhs: [ZoneEditorResolvedZoneFrame],
        _ rhs: [ZoneEditorResolvedZoneFrame]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }

        for (left, right) in zip(lhs, rhs) {
            guard left.path == right.path,
                  left.zoneID == right.zoneID,
                  framesMatch(left.frame, right.frame) else {
                return false
            }
        }

        return true
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.5
            && abs(lhs.minY - rhs.minY) < 0.5
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
    }

    private func freezeFrameUpdatesDuringAlignment() {
        alignmentFrameUpdateTask?.cancel()
        alignmentFrameGate.isFrozen = true
        alignmentFrameGate.pendingFrames = nil

        alignmentFrameUpdateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }

            alignmentFrameGate.isFrozen = false
            if let pendingFrames = alignmentFrameGate.pendingFrames {
                alignmentFrameGate.pendingFrames = nil
                commitResolvedZoneFrames(
                    pendingFrames,
                    contentWidth: 0,
                    refreshMenu: false
                )
            }
        }
    }

    private func thawFrameUpdates() {
        alignmentFrameUpdateTask?.cancel()
        alignmentFrameUpdateTask = nil
        alignmentFrameGate.isFrozen = false
        alignmentFrameGate.pendingFrames = nil
    }

    private func alignmentMenu(for menuState: ZoneAlignmentMenuState, contentWidth: CGFloat) -> some View {
        let menuWidth = Self.alignmentMenuSize.width
        let menuHeight = Self.alignmentMenuSize.height
        let x = clampedMenuX(anchorX: menuState.anchor.x, menuWidth: menuWidth, contentWidth: contentWidth)
        let y = max(menuState.anchor.y + 8, 0)

        return HStack(spacing: 4) {
            alignmentMenuButton(systemName: "chevron.left") {
                performAlignmentAction(.left)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 18)
                .allowsHitTesting(false)

            alignmentMenuButton(systemName: "chevron.right") {
                performAlignmentAction(.right)
            }
        }
        .frame(width: menuWidth, height: menuHeight)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
        .offset(x: x, y: y)
        .transition(.scale(scale: 0.82, anchor: .top).combined(with: .opacity))
        .zIndex(4)
    }

    private func alignmentMenuButton(
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func resolvedAlignmentMenuState(
        for tappedPath: ZonePath,
        contentWidth: CGFloat,
        frames: [ZoneEditorResolvedZoneFrame]
    ) -> ZoneAlignmentMenuState? {
        guard let target = resolveAlignmentTarget(for: tappedPath, contentWidth: contentWidth, frames: frames) else {
            return nil
        }

        return ZoneAlignmentMenuState(
            target: target.targetRef,
            tappedPath: tappedPath,
            frame: target.frame,
            anchor: CGPoint(x: target.frame.midX, y: target.frame.maxY),
            movementWidth: target.movementWidth,
            currentAlignment: target.currentAlignment
        )
    }

    private func resolveAlignmentTarget(
        for tappedPath: ZonePath,
        contentWidth: CGFloat,
        frames: [ZoneEditorResolvedZoneFrame]
    ) -> (
        targetRef: ZoneAlignmentTargetRef,
        frame: CGRect,
        movementWidth: CGFloat,
        currentAlignment: ZoneBlockAlignment
    )? {
        guard let tappedZone = content.zone(at: tappedPath) else { return nil }
        guard let leafFrame = frame(for: tappedPath, in: frames) else { return nil }

        if let singleZoneGroupTarget = singleZoneGroupTarget(
            for: tappedPath,
            contentWidth: contentWidth,
            frames: frames
        ) {
            return singleZoneGroupTarget
        }

        if let groupContext = resolvedGroupMoveContext(
            for: tappedPath,
            frames: frames
        ) {
            let parentPath = groupContext.parentPath
            let parentZone = groupContext.parentZone
            let childPath = groupContext.childPath
            let childFrame = groupContext.childFrame
            let siblingFrames = groupContext.siblingFrames
            let widestSiblingWidth = siblingFrames.map(\.frame.width).max() ?? childFrame.width
            let selectedIsWidest = childFrame.width >= widestSiblingWidth - Self.alignmentTolerance

            if selectedIsWidest {
                let groupFrame = union(of: siblingFrames.map(\.frame)) ?? childFrame
                let movementWidth = availableAlignmentWidth(for: parentPath, contentWidth: contentWidth, frames: frames)
                return (
                    targetRef: ZoneAlignmentTargetRef(path: parentPath, kind: .group),
                    frame: groupFrame,
                    movementWidth: movementWidth,
                    currentAlignment: resolvedAlignment(for: parentZone, kind: .group)
                )
            }

            let childTargetZone = content.zone(at: childPath)
            let childTargetKind: ZoneAlignmentTargetKind = childTargetZone?.isLeaf == false ? .group : .leaf
            let movementWidth = availableAlignmentWidth(for: childPath, contentWidth: contentWidth, frames: frames)
            return (
                targetRef: ZoneAlignmentTargetRef(path: childPath, kind: childTargetKind),
                frame: childFrame,
                movementWidth: movementWidth,
                currentAlignment: resolvedAlignment(for: childTargetZone ?? tappedZone, kind: childTargetKind)
            )
        }

        if let childContext = nearestAlignmentGroupContext(
            for: tappedPath,
            frames: frames
        ) {
            let childPath = childContext.childPath
            let childFrame = childContext.childFrame
            let childTargetZone = content.zone(at: childPath)
            let childTargetKind: ZoneAlignmentTargetKind = childTargetZone?.isLeaf == false ? .group : .leaf
            let movementWidth = availableAlignmentWidth(for: childPath, contentWidth: contentWidth, frames: frames)
            return (
                targetRef: ZoneAlignmentTargetRef(path: childPath, kind: childTargetKind),
                frame: childFrame,
                movementWidth: movementWidth,
                currentAlignment: resolvedAlignment(for: childTargetZone ?? tappedZone, kind: childTargetKind)
            )
        }

        let movementWidth = availableAlignmentWidth(for: tappedPath, contentWidth: contentWidth, frames: frames)
        return (
            targetRef: ZoneAlignmentTargetRef(path: tappedPath, kind: .leaf),
            frame: leafFrame,
            movementWidth: movementWidth,
            currentAlignment: resolvedAlignment(for: tappedZone, kind: .leaf)
        )
    }

    private func singleZoneGroupTarget(
        for tappedPath: ZonePath,
        contentWidth: CGFloat,
        frames: [ZoneEditorResolvedZoneFrame]
    ) -> (
        targetRef: ZoneAlignmentTargetRef,
        frame: CGRect,
        movementWidth: CGFloat,
        currentAlignment: ZoneBlockAlignment
    )? {
        let rootZone = content.rootZone
        guard !rootZone.isLeaf,
              rootZone.direction == .vertical,
              rootZone.leafCount == 1,
              content.zone(at: tappedPath)?.isLeaf == true,
              let rootFrame = frame(forSubtree: .root, in: frames) else {
            return nil
        }

        return (
            targetRef: ZoneAlignmentTargetRef(path: .root, kind: .group),
            frame: rootFrame,
            movementWidth: contentWidth,
            currentAlignment: resolvedAlignment(for: rootZone, kind: .group)
        )
    }

    private func resolvedGroupMoveContext(
        for tappedPath: ZonePath,
        frames: [ZoneEditorResolvedZoneFrame]
    ) -> ZoneAlignmentGroupContext? {
        var promotedContext: ZoneAlignmentGroupContext?

        for context in alignmentGroupContexts(for: tappedPath, frames: frames) {
            guard childIsWidestInGroup(context) else {
                break
            }

            promotedContext = context
        }

        return promotedContext
    }

    private func childIsWidestInGroup(_ context: ZoneAlignmentGroupContext) -> Bool {
        let widestSiblingWidth = context.siblingFrames.map(\.frame.width).max() ?? context.childFrame.width
        return context.childFrame.width >= widestSiblingWidth - Self.alignmentTolerance
    }

    private func nearestAlignmentGroupContext(
        for tappedPath: ZonePath,
        frames: [ZoneEditorResolvedZoneFrame]
    ) -> ZoneAlignmentGroupContext? {
        alignmentGroupContexts(for: tappedPath, frames: frames).first
    }

    private func alignmentGroupContexts(
        for tappedPath: ZonePath,
        frames: [ZoneEditorResolvedZoneFrame]
    ) -> [ZoneAlignmentGroupContext] {
        var contexts: [ZoneAlignmentGroupContext] = []
        var candidatePath = tappedPath.parent

        while let parentPath = candidatePath {
            defer { candidatePath = parentPath.parent }

            guard let parentZone = content.zone(at: parentPath),
                  parentZone.direction == .vertical,
                  let siblings = parentZone.children,
                  siblings.count > 1,
                  let childPath = directChildPath(of: tappedPath, relativeTo: parentPath),
                  let childFrame = frame(forSubtree: childPath, in: frames) else {
                continue
            }

            let siblingFrames = siblingFrames(
                in: frames,
                under: parentPath,
                directChildCount: siblings.count
            )
            guard siblingFrames.count > 1 else {
                continue
            }

            contexts.append(
                ZoneAlignmentGroupContext(
                    parentPath: parentPath,
                    parentZone: parentZone,
                    childPath: childPath,
                    childFrame: childFrame,
                    siblingFrames: siblingFrames
                )
            )
        }

        return contexts
    }

    private func resolvedAlignment(for zone: ZoneModel, kind: ZoneAlignmentTargetKind) -> ZoneBlockAlignment {
        if zone.blockAlignment != .auto {
            return zone.blockAlignment
        }

        switch kind {
        case .group:
            return .center
        case .leaf:
            return content.rootZone.leafCount == 1 ? .center : .leading
        }
    }

    private func availableAlignmentWidth(
        for path: ZonePath,
        contentWidth: CGFloat,
        frames: [ZoneEditorResolvedZoneFrame]
    ) -> CGFloat {
        guard let parentPath = path.parent else {
            return contentWidth
        }

        if let parentFrame = frame(forSubtree: parentPath, in: frames) {
            return max(parentFrame.width, 1)
        }

        return contentWidth
    }

    private func frame(for path: ZonePath, in frames: [ZoneEditorResolvedZoneFrame]) -> CGRect? {
        frames.first { $0.path == path }?.frame
    }

    private func frame(forSubtree path: ZonePath, in frames: [ZoneEditorResolvedZoneFrame]) -> CGRect? {
        union(of: frames.compactMap { frame in
            frame.path.indices.starts(with: path.indices) ? frame.frame : nil
        })
    }

    private func siblingFrames(
        in frames: [ZoneEditorResolvedZoneFrame],
        under parentPath: ZonePath,
        directChildCount: Int
    ) -> [ZoneEditorResolvedZoneFrame] {
        let directChildPaths = (0..<directChildCount).map { parentPath.appending($0) }

        return directChildPaths.compactMap { childPath in
            guard let childFrame = frame(forSubtree: childPath, in: frames) else { return nil }
            return ZoneEditorResolvedZoneFrame(path: childPath, zoneID: content.zone(at: childPath)?.id ?? UUID(), frame: childFrame)
        }
    }

    private func directChildPath(of path: ZonePath, relativeTo parentPath: ZonePath) -> ZonePath? {
        guard path.indices.count > parentPath.indices.count else { return nil }
        let nextIndex = path.indices[parentPath.indices.count]
        return parentPath.appending(nextIndex)
    }

    private func findPath(
        for id: UUID,
        in zone: ZoneModel,
        currentIndices: [Int] = []
    ) -> ZonePath? {
        if zone.id == id { return ZonePath(indices: currentIndices) }
        guard let children = zone.children else { return nil }

        for (index, child) in children.enumerated() {
            if let found = findPath(for: id, in: child, currentIndices: currentIndices + [index]) {
                return found
            }
        }

        return nil
    }

    private func union(of frames: [CGRect]) -> CGRect? {
        guard var first = frames.first else { return nil }
        for frame in frames.dropFirst() {
            first = first.union(frame)
        }
        return first
    }

    private func currentFrame(for target: ZoneAlignmentTargetRef) -> CGRect? {
        switch target.kind {
        case .leaf:
            return frame(for: target.path, in: zoneFrames)
        case .group:
            return frame(forSubtree: target.path, in: zoneFrames)
        }
    }

    private func clampedMenuX(anchorX: CGFloat, menuWidth: CGFloat, contentWidth: CGFloat) -> CGFloat {
        let sidePadding: CGFloat = 6
        let maxX = max(contentWidth - menuWidth - sidePadding, sidePadding)
        return min(max(anchorX - (menuWidth / 2), sidePadding), maxX)
    }

    private func debugSummary(for state: ZoneAlignmentMenuState, action: String) -> String {
        "align \(action) path=\(state.target.path.id) kind=\(state.target.kind.debugName) frame=\(Int(state.frame.width))x\(Int(state.frame.height))@\(Int(state.frame.minX)),\(Int(state.frame.minY)) cur=\(state.currentAlignment.rawValue) moveW=\(Int(state.movementWidth))"
    }

    private func performAlignmentAction(_ direction: ZoneAlignmentDirection) {
        guard let menuState = alignmentMenuState else { return }

        let nextAlignment = nextAlignment(
            from: menuState.currentAlignment,
            direction: direction
        )
        let canMove = menuState.frame.width < menuState.movementWidth - Self.alignmentTolerance

        guard canMove, let nextAlignment else {
            triggerAlignmentWiggle(for: menuState.target)
            ZoneEditorDebugStore.shared.recordAlignment(
                debugSummary(for: menuState, action: "wiggle \(direction)")
            )
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            return
        }

        freezeFrameUpdatesDuringAlignment()

        withAnimation(.easeOut(duration: 0.22)) {
            content.updateZone(at: menuState.target.path) { zone in
                zone.blockAlignment = nextAlignment
            }
        }

        if var updatedMenuState = alignmentMenuState {
            updatedMenuState.currentAlignment = nextAlignment
            alignmentMenuState = updatedMenuState
        }
        ZoneEditorDebugStore.shared.recordAlignment(
            debugSummary(
                for: ZoneAlignmentMenuState(
                    target: menuState.target,
                    tappedPath: menuState.tappedPath,
                    frame: menuState.frame,
                    anchor: menuState.anchor,
                    movementWidth: menuState.movementWidth,
                    currentAlignment: nextAlignment
                ),
                action: "set \(direction)"
            )
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func nextAlignment(
        from currentAlignment: ZoneBlockAlignment,
        direction: ZoneAlignmentDirection
    ) -> ZoneBlockAlignment? {
        let order: [ZoneBlockAlignment] = [.leading, .center, .trailing]
        guard let currentIndex = order.firstIndex(of: currentAlignment == .auto ? .leading : currentAlignment) else {
            return nil
        }

        switch direction {
        case .left:
            guard currentIndex > 0 else { return nil }
            return order[currentIndex - 1]
        case .right:
            guard currentIndex < order.count - 1 else { return nil }
            return order[currentIndex + 1]
        }
    }

    private func triggerAlignmentWiggle(for target: ZoneAlignmentTargetRef) {
        alignmentWiggleTask?.cancel()
        alignmentWiggleTarget = target
        alignmentWiggleOffset = 0

        let offsets: [CGFloat] = [0, -6, 5, -3, 2, 0]
        alignmentWiggleTask = Task { @MainActor in
            for offset in offsets {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.045)) {
                    alignmentWiggleOffset = offset
                }
                try? await Task.sleep(for: .milliseconds(40))
            }
            guard !Task.isCancelled else { return }
            alignmentWiggleTarget = nil
            alignmentWiggleOffset = 0
        }
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

    private func layoutStartMarker(
        mode: String,
        layout: ZoneContentLayout,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat
    ) -> some View {
        Color.clear
            .frame(height: 1)
            .onGeometryChange(for: ZoneEditorLayoutStartGeometry.self) { proxy in
                ZoneEditorLayoutStartGeometry(
                    screenFrame: proxy.frame(in: .global),
                    contentFrame: proxy.frame(in: .named(Self.coordinateSpaceName))
                )
            } action: { geometry in
                guard showsDebugTools else { return }
                let now = CACurrentMediaTime()
                guard now - lastLayoutDebugSnapshotTime >= 0.12 else { return }
                lastLayoutDebugSnapshotTime = now

                let snapshot = ZoneEditorLayoutDebugSnapshot(
                    mode: mode,
                    screenY: geometry.screenFrame.minY,
                    contentY: geometry.contentFrame.minY,
                    scrollY: scrollDriver.currentNormalizedOffsetY,
                    frame: selectedFrame ?? geometry.contentFrame,
                    topInset: layout.contentTopInset,
                    horizontalPadding: horizontalPadding,
                    verticalPadding: verticalPadding,
                    path: selectedPath?.id ?? "nil"
                )

                if mode == "RAW" {
                    rawLayoutDebugSnapshot = snapshot
                } else {
                    renderLayoutDebugSnapshot = snapshot
                }
            }
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var usefulSurfaceDebugOutline: some View {
        if showsDebugTools {
            Rectangle()
                .stroke(
                    Color.red,
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var viewportDebugOverlay: some View {
        if showsDebugTools {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                    )

                layoutDebugLine(snapshot: rawLayoutDebugSnapshot, color: .green)
                layoutDebugLine(snapshot: renderLayoutDebugSnapshot, color: .pink)

                VStack(alignment: .leading, spacing: 3) {
                    layoutDebugSummary(snapshot: rawLayoutDebugSnapshot, color: .green)
                    layoutDebugSummary(snapshot: renderLayoutDebugSnapshot, color: .pink)
                }
                .padding(4)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func layoutDebugLine(
        snapshot: ZoneEditorLayoutDebugSnapshot?,
        color: Color
    ) -> some View {
        if let snapshot, viewportScreenFrame.height > 0 {
            Rectangle()
                .fill(color)
                .frame(height: 2)
                .offset(y: snapshot.screenY - viewportScreenFrame.minY)
        }
    }

    @ViewBuilder
    private func layoutDebugSummary(
        snapshot: ZoneEditorLayoutDebugSnapshot?,
        color: Color
    ) -> some View {
        if let snapshot {
            Text(layoutDebugText(snapshot))
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 3))
        }
    }

    private func layoutDebugText(_ snapshot: ZoneEditorLayoutDebugSnapshot) -> String {
        let frame = snapshot.frame
        return "\(snapshot.mode) screenY=\(debugNumber(snapshot.screenY)) contentY=\(debugNumber(snapshot.contentY)) scrollY=\(debugNumber(snapshot.scrollY))\nframe=(\(debugNumber(frame.minX)),\(debugNumber(frame.minY)),\(debugNumber(frame.width)),\(debugNumber(frame.height))) topInset=\(debugNumber(snapshot.topInset)) padding=(\(debugNumber(snapshot.horizontalPadding)),\(debugNumber(snapshot.verticalPadding))) path=\(snapshot.path)"
    }

    private func debugNumber(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    private func handleScrollOffsetChange(_ offsetY: CGFloat) {
        onScrollOffsetChange(offsetY)
    }

    private func handleUIKitTapProbe(_ snapshot: ZoneEditorTapProbeSnapshot) {
        let localPoint = snapshot.contentPoint
        let candidateFrames = zoneFrames
            .filter { $0.frame.insetBy(dx: -Self.renderHitSlop, dy: -Self.renderHitSlop).contains(localPoint) }
        let matchedPath = candidateFrames
            .min { ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height) }?
            .path.id ?? "nil"
        let line = "probe tap content=\(Int(localPoint.x)),\(Int(localPoint.y)) window=\(Int(snapshot.windowPoint.x)),\(Int(snapshot.windowPoint.y)) scroll=\(Int(scrollDriver.currentNormalizedOffsetY)) hit=\(snapshot.hitViewName) super=\(snapshot.hitSuperviewName) frames=\(zoneFrames.count) match=\(matchedPath) swift=\(lastTapDebugLine)"
        lastTapDebugLine = line
        ZoneEditorDebugStore.shared.recordTap(line)
    }

    private func configureTapProbe() {
        guard rendersRichText && showsDebugTools else {
            scrollDriver.setTapProbeHandler(nil)
            return
        }

        scrollDriver.setTapProbeHandler(handleUIKitTapProbe)
    }

    private func handleWindowTouchProbe(_ snapshot: ZoneEditorWindowTouchSnapshot) {
        let selected = selectedPath?.id ?? "nil"
        let rootID = content.rootZone.id.uuidString.prefix(6)
        windowTouchDebugLines = [
            "WIN \(snapshot.phase) p=\(Int(snapshot.windowPoint.x)),\(Int(snapshot.windowPoint.y)) viewport=\(snapshot.viewportDescription)",
            "HIT \(snapshot.hitViewDescription)",
            "CHAIN \(snapshot.hitViewChain)",
            "CANVAS render=\(rendersRichText ? 1 : 0) root=\(rootID) selected=\(selected) frames=\(zoneFrames.count) scroll=\(Int(scrollDriver.currentNormalizedOffsetY))"
        ] + snapshot.gestureLines
        ZoneEditorDebugStore.shared.recordTap(
            "window \(snapshot.phase) hit=\(snapshot.hitViewName) gestures=\(snapshot.gestureCount)"
        )
    }

    private var windowTouchProbeBackground: AnyView {
        guard rendersRichText && showsDebugTools else {
            return AnyView(Color.clear)
        }

        return AnyView(
            ZoneEditorWindowTouchProbe { snapshot in
                handleWindowTouchProbe(snapshot)
            }
        )
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
                        ForEach(Array(windowTouchDebugLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                        }
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

    private func attemptPendingScrollRestoration(
        cardWidth: CGFloat,
        editorViewportHeight: CGFloat,
        contentWidth: CGFloat,
        contentHeight: CGFloat
    ) {
        guard let request = pendingScrollRestorationRequest ?? scrollRestorationRequest else { return }
        guard request.targetRenderedMode == rendersRichText else { return }

        let layout = contentLayoutMetrics(
            contentSize: CGSize(width: contentWidth, height: contentHeight)
        )
        guard isStableForScrollRestoration(layout: layout) else { return }

        scrollDriver.restoreNormalizedOffset(request.normalizedOffsetY)
        pendingScrollRestorationRequest = nil
        updateCanvasDebug(
            cardSize: CGSize(width: cardWidth, height: editorViewportHeight),
            contentSize: CGSize(width: contentWidth, height: contentHeight)
        )
        onScrollRestorationApplied()
    }

    private func isStableForScrollRestoration(layout: ZoneContentLayout) -> Bool {
        guard !zoneFrames.isEmpty else { return false }
        guard layout.contentBodyHeight > 0, layout.scrollContentHeight > 0 else { return false }
        guard rendersRichText else { return true }
        return renderMeasuredContentSize.width > 0 && renderMeasuredContentSize.height > 0
    }

    private func contentLayoutMetrics(contentSize: CGSize) -> ZoneContentLayout {
        let measuredContentSize = measuredContentBodySize(contentWidth: contentSize.width)
        let estimatedContentSize = ZoneContentEstimator.estimatedSize(
            for: content.rootZone,
            fontScale: fontScale,
            availableWidth: max(contentSize.width, 1)
        )

        return ZoneContentLayout(
            containerSize: contentSize,
            horizontalPadding: 0,
            verticalPadding: 0,
            estimatedContentSize: estimatedContentSize,
            measuredContentSize: measuredContentSize,
            verticalAlignment: .top
        )
    }

    private func measuredContentBodySize(contentWidth: CGFloat) -> CGSize {
        if rendersRichText {
            return renderMeasuredContentSize
        }

        let frameMinY = zoneFrames.map { $0.frame.minY }.min() ?? 0
        guard let maxFrameY = zoneFrames.map({ $0.frame.maxY }).max(), maxFrameY > frameMinY else {
            return .zero
        }

        return CGSize(width: max(contentWidth, 1), height: ceil(maxFrameY - frameMinY))
    }

    private func updateCanvasDebug(cardSize: CGSize, contentSize: CGSize) {
        let layout = contentLayoutMetrics(contentSize: contentSize)
        debugStore.updateCanvas(
            cardSize: cardSize,
            contentSize: contentSize,
            scrollOffsetY: scrollDriver.currentNormalizedOffsetY,
            contentTopInset: layout.contentTopInset,
            contentBodyHeight: layout.contentBodyHeight,
            scrollContentHeight: layout.scrollContentHeight,
            selectedPathID: selectedPath?.id,
            selectedFrame: selectedFrame,
            resolvedFrameCount: zoneFrames.count,
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
        AppFeatures.current.showsVisualDebugOverlays && showsDebugOverlays
    }

    private var showsGridDebugOverlay: Bool {
        AppFeatures.current.showsVisualDebugOverlays
            && showsDebugOverlays
            && developmentPreferences.zoneContentLayoutDebugEnabled
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
    private var tapProbe: ZoneEditorTapProbe?
    private(set) var currentNormalizedOffsetY: CGFloat = 0

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
        currentNormalizedOffsetY = 0
        tapProbe?.detach()
        tapProbe = nil
        scrollView = nil
    }

    func setScrollOffsetHandler(_ handler: @escaping (CGFloat) -> Void) {
        onScrollOffsetChange = handler
        if let scrollView {
            reportScrollOffset(in: scrollView, force: true)
        }
    }

    func setTapProbeHandler(_ handler: ((ZoneEditorTapProbeSnapshot) -> Void)?) {
        guard let scrollView else { return }

        guard let handler else {
            tapProbe?.detach()
            tapProbe = nil
            return
        }

        if let tapProbe {
            tapProbe.onTap = handler
            tapProbe.attach(to: scrollView)
            return
        }

        let probe = ZoneEditorTapProbe()
        probe.onTap = handler
        probe.attach(to: scrollView)
        tapProbe = probe
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
        currentNormalizedOffsetY = normalizedOffsetY
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

private struct ZoneEditorTapProbeSnapshot {
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

private struct ZoneEditorWindowTouchSnapshot {
    let phase: String
    let windowPoint: CGPoint
    let viewportDescription: String
    let hitViewName: String
    let hitViewDescription: String
    let hitViewChain: String
    let gestureLines: [String]
    let gestureCount: Int
}

private struct ZoneEditorWindowTouchProbe: UIViewRepresentable {
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
        private lazy var recognizer = ZoneEditorPassiveTouchRecognizer { [weak self] phase, point in
            self?.record(phase: phase, windowPoint: point)
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

        private func record(phase: String, windowPoint: CGPoint) {
            guard let window, viewportFrame.contains(windowPoint) else { return }
            publishSnapshot(phase: "\(phase)/now", windowPoint: windowPoint)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                self?.publishSnapshot(phase: "\(phase)/60ms", windowPoint: windowPoint)
            }
        }

        private func publishSnapshot(phase: String, windowPoint: CGPoint) {
            guard let window else { return }
            let hitView = window.hitTest(windowPoint, with: nil)
            let chain = viewChain(startingAt: hitView)
            let gestures = gestureDescriptions(startingAt: hitView)
            let localPoint = hitView.map { $0.convert(windowPoint, from: window) } ?? .zero
            let hitFrame = hitView.map { $0.convert($0.bounds, to: window) } ?? .zero
            let gestureLines = gestures.isEmpty
                ? ["G none"]
                : gestures.enumerated().map { index, description in
                    "G\(index) \(description)"
                }

            onSnapshot(
                ZoneEditorWindowTouchSnapshot(
                    phase: phase,
                    windowPoint: windowPoint,
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
    private let onFinished: (String, CGPoint) -> Void
    private var initialPoint: CGPoint?
    private var initialHitName = "nil"

    init(onFinished: @escaping (String, CGPoint) -> Void) {
        self.onFinished = onFinished
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else { return }
        initialPoint = touch.location(in: view)
        initialHitName = touch.view.map { String(describing: type(of: $0)) } ?? "nil"
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else {
            state = .failed
            return
        }
        let point = touch.location(in: view)
        onFinished("ended/\(initialHitName)", point)
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if let point = initialPoint {
            onFinished("cancelled/\(initialHitName)", point)
        }
        state = .failed
    }

    override func reset() {
        initialPoint = nil
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

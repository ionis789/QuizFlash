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

private struct ZoneEditorRenderScreenZoneFramePreferenceKey: PreferenceKey {
    static var defaultValue: [ZoneEditorResolvedZoneFrame] { [] }

    static func reduce(
        value: inout [ZoneEditorResolvedZoneFrame],
        nextValue: () -> [ZoneEditorResolvedZoneFrame]
    ) {
        value.append(contentsOf: nextValue())
    }
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
    let showsZoneHeightGuides: Bool
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
    @State private var renderScreenZoneFrames: [ZoneEditorResolvedZoneFrame] = []
    @State private var renderLeafDebugSnapshots: [ZoneContentLeafLayoutDebugSnapshot] = []
    @State private var pendingScrollRestorationRequest: ZoneEditorScrollRestorationRequest?
    @State private var viewportScreenFrame: CGRect = .zero
    @State private var rawLayoutDebugSnapshot: ZoneEditorLayoutDebugSnapshot?
    @State private var renderLayoutDebugSnapshot: ZoneEditorLayoutDebugSnapshot?
    @State private var lastLayoutDebugSnapshotTime: CFTimeInterval = 0
    @State private var windowTouchDebugLines: [String] = []
    @State private var interactionTrace: [String] = []
    @State private var interactionTraceIndex = 0
    @State private var lastAlignmentMenuInteractionTime: CFTimeInterval = 0

    private var focusManager: ZoneFocusManager { ZoneFocusManager.shared }

    private static let coordinateSpaceName = "ZoneEditorCanvasContent"
    private static let alignmentTolerance: CGFloat = 1
    private static let alignmentMenuSize = CGSize(width: 104, height: 44)
    private static let alignmentMenuVerticalSpacing: CGFloat = 28
    private static let renderLeafHorizontalHitSlop: CGFloat = 32
    private static let renderLeafVerticalHitSlop: CGFloat = 10

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var screenToCardHorizontalPadding: CGFloat {
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
        showsZoneHeightGuides: Bool = false,
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
        self.showsZoneHeightGuides = showsZoneHeightGuides
        self.showsDebugOverlays = showsDebugOverlays
        self.onScrollOffsetChange = onScrollOffsetChange
        self.onEmptySpaceTap = onEmptySpaceTap
        self.onScrollRestorationApplied = onScrollRestorationApplied
    }

    var body: some View {
        GeometryReader { geometry in
            let externalHorizontalPadding = screenToCardHorizontalPadding
            let cardWidth = max(geometry.size.width - (externalHorizontalPadding * 2), 1)
            let editorViewportHeight = max(geometry.size.height - (UIConstants.Spacing.small * 2), 1)
            let surfaceHorizontalPadding = contentHorizontalPadding
            let surfaceVerticalPadding = contentVerticalPadding
            let contentWidth = max(cardWidth - (surfaceHorizontalPadding * 2), 1)
            let contentViewportHeight = max(
                editorViewportHeight - topContentInset - (surfaceVerticalPadding * 2),
                1
            )
            let contentHeight = contentViewportHeight
            let rawBottomAccessoryInset = bottomAccessoryHeight > 0
                ? max(bottomAccessoryHeight, 0)
                : 0
            let rawContentGrowthInset = max(editorViewportHeight * 0.45, 260)
            let rawKeyboardCreationInset = keyboardMonitor.isVisible
                ? max(keyboardMonitor.visibleHeight, 0) + max(bottomAccessoryHeight, 0) + caretBottomChromeBuffer
                : max(rawBottomAccessoryInset, rawContentGrowthInset)
            let renderRequestedBottomScrollInset = dynamicBottomScrollInset > 0
                ? dynamicBottomScrollInset
                : rawContentGrowthInset
            let requestedBottomScrollInset = rendersRichText
                ? renderRequestedBottomScrollInset
                : rawKeyboardCreationInset
            let bottomScrollInset = contentNeedsBottomScrollInset(
                contentWidth: contentWidth,
                contentHeight: contentHeight,
                contentTopOffset: surfaceVerticalPadding + topContentInset,
                requestedBottomScrollInset: requestedBottomScrollInset
            ) ? requestedBottomScrollInset : 0
            let minimumScrollContentHeight = editorViewportHeight

            ScrollViewReader { _ in
                ScrollView(.vertical, showsIndicators: false) {
                    zoneContentSurface(
                        contentWidth: contentWidth,
                        contentHeight: contentHeight,
                        bottomScrollInset: bottomScrollInset
                    )
                    .padding(.horizontal, surfaceHorizontalPadding)
                    .padding(.top, surfaceVerticalPadding + topContentInset)
                    .padding(.bottom, surfaceVerticalPadding)
                    .frame(width: cardWidth, alignment: .topLeading)
                    .frame(minHeight: minimumScrollContentHeight, alignment: .topLeading)
                }
                .background {
                    ZoneEditorScrollViewLocator { scrollView in
                        scrollDriver.attach(scrollView)
                        scrollDriver.setTopInset(0)
                        if rendersRichText {
                            refreshBottomScrollInset()
                        } else {
                            scrollDriver.resetBottomInset()
                        }
                        if let scrollRestorationRequest,
                           scrollRestorationRequest.targetRenderedMode == rendersRichText {
                            scrollDriver.restoreNormalizedOffset(scrollRestorationRequest.normalizedOffsetY)
                        }
                        scrollDriver.setScrollOffsetHandler(handleScrollOffsetChange)
                        configureTapProbe()
                    }
                }
                .scrollDismissesKeyboard(.never)
                .scrollClipDisabled()
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
                .padding(.horizontal, externalHorizontalPadding)
                .padding(.top, UIConstants.Spacing.small)
                .padding(.bottom, UIConstants.Spacing.small)
                .onChange(of: selectedPath) { _, newPath in
                    if activeCaretPathID != newPath?.id {
                        clearActiveCaretGeometry()
                    }
                    if newPath == nil {
                        cancelCaretAvoidanceScroll()
                        dismissAlignmentMenu()
                    } else {
                        let selectedZone = newPath.flatMap { content.zone(at: $0) }
                        if selectedZone?.isEditorMediaLeaf == true {
                            cancelCaretAvoidanceScroll()
                            clearActiveCaretGeometry()
                            focusManager.suppressFocusRequests(for: 0.9)
                            ZoneController.shared.forceReleaseKeyboard()
                            ZoneController.shared.updateFocusedZone(nil)
                            debugStore.recordLayoutEvent(
                                "media-select",
                                zoneID: selectedZone?.id,
                                pathID: newPath?.id,
                                details: "source=selectedPath mode=\(rendersRichText ? "render" : "raw")"
                            )
                        } else if !rendersRichText {
                            scrollDriver.preserveCurrentOffsetDuringNonUserFocus()
                        }
                        if keyboardMonitor.isVisible, selectedZone?.isEditorMediaLeaf != true {
                            scheduleCaretAvoidanceScroll(delay: .milliseconds(16))
                        }
                    }
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: editorViewportHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                }
                .onChange(of: keyboardMonitor.visibleHeight) { _, newHeight in
                    let oldHeight = lastKeyboardVisibleHeight
                    lastKeyboardVisibleHeight = newHeight
                    recordKeyboardStateFlow(
                        "keyboard.height-change.start",
                        details: "old=\(debugNumber(oldHeight)) new=\(debugNumber(newHeight))"
                    )
                    if rendersRichText {
                        refreshBottomScrollInset(
                            animationDuration: newHeight <= 1 && !keyboardMonitor.isVisible
                                ? keyboardDismissScrollAnimationDuration
                                : 0,
                            animationOptions: keyboardMonitor.animationOptions
                        )
                    } else {
                        scrollDriver.preserveCurrentOffsetDuringNonUserFocus()
                        if newHeight <= 1, !keyboardMonitor.isVisible {
                            scrollDriver.resetBottomInset(
                                animationDuration: keyboardDismissScrollAnimationDuration,
                                animationOptions: keyboardMonitor.animationOptions
                            )
                        } else {
                            scrollDriver.resetBottomInset()
                        }
                    }

                    if newHeight <= 1, !keyboardMonitor.isVisible {
                        cancelCaretAvoidanceScroll()
                        scrollDriver.smoothClampOffsetIfNeeded(
                            duration: keyboardDismissScrollAnimationDuration,
                            options: keyboardMonitor.animationOptions
                        )
                        clearRawTextSelectionAfterKeyboardDismissIfIdle(reason: "height-change")
                    } else if abs(newHeight - oldHeight) > 1 || shouldMaintainKeyboardAvoidance {
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(24))
                    }
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: editorViewportHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                    recordKeyboardStateFlow(
                        "keyboard.height-change.end",
                        details: "old=\(debugNumber(oldHeight)) new=\(debugNumber(newHeight))"
                    )
                }
                .onChange(of: keyboardMonitor.isVisible) { _, isVisible in
                    recordKeyboardStateFlow(
                        "keyboard.visible-change.start",
                        details: "visible=\(isVisible ? 1 : 0)"
                    )
                    lastKeyboardVisibleHeight = keyboardMonitor.visibleHeight
                    if rendersRichText {
                        refreshBottomScrollInset(
                            animationDuration: isVisible ? 0 : keyboardDismissScrollAnimationDuration,
                            animationOptions: keyboardMonitor.animationOptions
                        )
                    } else {
                        scrollDriver.resetBottomInset(
                            animationDuration: isVisible ? 0 : keyboardDismissScrollAnimationDuration,
                            animationOptions: keyboardMonitor.animationOptions
                        )
                    }
                    if isVisible {
                        if !rendersRichText {
                            scrollDriver.preserveCurrentOffsetDuringNonUserFocus()
                        }
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(24))
                    } else {
                        cancelCaretAvoidanceScroll()
                        scrollDriver.smoothClampOffsetIfNeeded(
                            duration: keyboardDismissScrollAnimationDuration,
                            options: keyboardMonitor.animationOptions
                        )
                        clearRawTextSelectionAfterKeyboardDismissIfIdle(reason: "visible-change")
                    }
                    updateCanvasDebug(
                        cardSize: CGSize(width: cardWidth, height: editorViewportHeight),
                        contentSize: CGSize(width: contentWidth, height: contentHeight)
                    )
                    recordKeyboardStateFlow(
                        "keyboard.visible-change.end",
                        details: "visible=\(isVisible ? 1 : 0)"
                    )
                }
                .onChange(of: focusManager.focusedZoneID) { _, focusedID in
                    if !rendersRichText, focusedID != nil {
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
                    if !rendersRichText {
                        scrollDriver.preserveCurrentOffsetDuringNonUserFocus()
                    }
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
                    if rendersRichText {
                        refreshBottomScrollInset()
                    } else {
                        scrollDriver.resetBottomInset()
                    }
                    if shouldMaintainKeyboardAvoidance {
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(24))
                    }
                }
                .onChange(of: bottomAccessoryHeight) { _, _ in
                    if rendersRichText {
                        refreshBottomScrollInset()
                    } else {
                        scrollDriver.resetBottomInset()
                    }
                    if shouldMaintainKeyboardAvoidance {
                        scheduleCaretAvoidanceScroll(delay: .milliseconds(24))
                    }
                }
                .onChange(of: scrollResetToken) { _, _ in
                    cancelCaretAvoidanceScroll()
                    clearActiveCaretGeometry()
                    dismissAlignmentMenu()
                    if rendersRichText {
                        refreshBottomScrollInset()
                    } else {
                        scrollDriver.resetBottomInset()
                    }
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
                    if rendersRichText {
                        refreshBottomScrollInset()
                    } else {
                        scrollDriver.resetBottomInset()
                    }
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

                    let source = caretScrollSource(from: notification)
                    guard source != .rejectedTextEdit else {
                        cancelCaretAvoidanceScroll()
                        clearActiveCaretGeometry()
                        debugStore.recordScrollDecision(
                            "scroll-skip-rejected-text-edit",
                            zoneID: selectedZone?.id,
                            details: "source=\(source.rawValue) path=\(selectedPath.id)"
                        )
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
                    if rendersRichText {
                        scrollDriver.releaseOffsetLock()
                    } else {
                        scrollDriver.preserveCurrentOffsetDuringNonUserFocus()
                    }
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
        bottomScrollInset: CGFloat
    ) -> some View {
        let layout = contentLayoutMetrics(
            contentSize: CGSize(width: contentWidth, height: contentHeight)
        )
        let tappableContentSize = CGSize(
            width: contentWidth,
            height: contentHeight + bottomScrollInset
        )
        let surfaceHeight = max(contentHeight, layout.scrollContentHeight)

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
                        showsZoneHeightGuides: showsZoneHeightGuides,
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
            .frame(width: contentWidth, height: surfaceHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .simultaneousGesture(
                emptySpaceTapGesture(contentSize: tappableContentSize),
                including: rendersRichText ? .none : .all
            )
            .overlay {
                usefulSurfaceDebugOutline
            }

            if rendersRichText {
                Color.clear
                    .frame(width: contentWidth, height: bottomScrollInset)
                    .animation(bottomScrollInsetAnimation, value: bottomScrollInset)
                    .allowsHitTesting(false)
            } else {
                Color.clear
                    .frame(width: contentWidth, height: bottomScrollInset)
                    .animation(bottomScrollInsetAnimation, value: bottomScrollInset)
                    .contentShape(Rectangle())
                    .gesture(emptySpaceTapGesture(contentSize: tappableContentSize))
            }
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
        .overlayPreferenceValue(ZoneContentRenderBlockBoundsPreferenceKey.self) { bounds in
            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                Color.clear.preference(
                    key: ZoneEditorRenderScreenZoneFramePreferenceKey.self,
                    value: rendersRichText ? bounds.compactMap { bound in
                        guard let path = findPath(for: bound.zoneID, in: content.rootZone) else {
                            return nil
                        }

                        return ZoneEditorResolvedZoneFrame(
                            path: path,
                            zoneID: bound.zoneID,
                            frame: bound.frame.offsetBy(dx: origin.x, dy: origin.y)
                        )
                    } : []
                )
            }
        }
        .onPreferenceChange(ZoneEditorResolvedZoneFramePreferenceKey.self) { frames in
            handleResolvedZoneFrames(frames, contentWidth: contentWidth)
        }
        .onPreferenceChange(ZoneEditorRenderScreenZoneFramePreferenceKey.self) { frames in
            commitRenderScreenZoneFrames(frames)
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
                showsDebugGuides: true,
                debugGuideStyle: .editorRender,
                alignmentFeedback: alignmentFeedback,
                collectsDebugMetrics: showsDebugTools,
                leafTapBehavior: .all,
                onZoneTap: { zoneID in
                    handleRenderedZoneTap(zoneID, contentWidth: layout.containerSize.width)
                }
            )
            .frame(width: layout.availableContentWidth, alignment: .topLeading)
            .onPreferenceChange(ZoneContentLeafDebugPreferenceKey.self) { snapshots in
                renderLeafDebugSnapshots = snapshots.sorted { $0.path < $1.path }
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
        if rendersRichText {
            guard !zoneFrames.contains(where: { $0.frame.contains(location) }) else {
                lastTapDebugLine = "render tap zone-owned"
                ZoneEditorDebugStore.shared.recordTap(lastTapDebugLine)
                return
            }

            if let groupHit = renderedAlignmentGroupHit(
                at: location,
                contentWidth: contentSize.width,
                frames: zoneFrames
            ) {
                selectRenderedAlignmentGroup(
                    groupHit,
                    contentWidth: contentSize.width,
                    anchor: location,
                    source: "render tap group"
                )
                return
            }

            if alignmentMenuState != nil {
                dismissAlignmentMenu()
                lastTapDebugLine = "tap dismiss alignment menu"
                ZoneEditorDebugStore.shared.recordTap(lastTapDebugLine)
                return
            }

            lastTapDebugLine = "render tap empty x=\(Int(location.x)) y=\(Int(location.y))"
            ZoneEditorDebugStore.shared.recordTap(lastTapDebugLine)
            selectedPath = nil
            return
        }

        if alignmentMenuState != nil {
            dismissAlignmentMenu()
            lastTapDebugLine = "tap dismiss alignment menu"
            ZoneEditorDebugStore.shared.recordTap(lastTapDebugLine)
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

    private func selectRenderedAlignmentGroup(
        _ groupHit: (path: ZonePath, hitFrame: CGRect),
        contentWidth: CGFloat,
        anchor: CGPoint,
        source: String
    ) {
        selectedPath = groupHit.path
        focusManager.forceReleaseKeyboard()
        ZoneController.shared.forceReleaseKeyboard()
        ZoneController.shared.updateFocusedZone(nil)
        lastTapDebugLine = "\(source) path=\(groupHit.path.id)"
        ZoneEditorDebugStore.shared.recordTap(lastTapDebugLine)
        recordInteractionTrace(
            "GROUP HIT path=\(groupHit.path.id) point=\(tracePoint(anchor)) frame=\(traceRect(groupHit.hitFrame))"
        )
        presentAlignmentMenu(
            for: groupHit.path,
            contentWidth: contentWidth,
            preferredAnchor: anchor
        )
    }

    private func handleRenderedZoneTap(
        _ zoneID: UUID,
        contentWidth: CGFloat,
        tapLocation: CGPoint? = nil
    ) {
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
        presentAlignmentMenu(for: path, contentWidth: contentWidth, preferredAnchor: tapLocation)
    }

    @ViewBuilder
    private func renderHitTargetOverlay(contentWidth: CGFloat) -> some View {
        if rendersRichText {
            ZStack(alignment: .topLeading) {
                ForEach(renderSelectableFrames, id: \.zoneID) { resolvedFrame in
                    Color.clear
                        .frame(
                            width: max(resolvedFrame.frame.width, 1),
                            height: max(resolvedFrame.frame.height, 1)
                        )
                        .contentShape(Rectangle())
                        .position(x: resolvedFrame.frame.midX, y: resolvedFrame.frame.midY)
                        .gesture(
                            SpatialTapGesture(coordinateSpace: .named(Self.coordinateSpaceName))
                                .onEnded { value in
                            handleRenderedZoneTap(
                                resolvedFrame.zoneID,
                                contentWidth: contentWidth,
                                tapLocation: value.location
                            )
                        })
                }
            }
            .allowsHitTesting(true)
        }
    }

    private var renderSelectableFrames: [ZoneEditorResolvedZoneFrame] {
        zoneFrames.filter { frame in
            content.zone(at: frame.path)?.isLeaf == true
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

    private func presentAlignmentMenu(
        for tappedPath: ZonePath,
        contentWidth: CGFloat,
        preferredAnchor: CGPoint? = nil
    ) {
        guard let state = resolvedAlignmentMenuState(
            for: tappedPath,
            contentWidth: contentWidth,
            frames: zoneFrames,
            preferredAnchor: preferredAnchor
        ) else {
            ZoneEditorDebugStore.shared.recordAlignment("align resolve failed tapped=\(tappedPath.id)")
            recordInteractionTrace("MENU resolve-failed path=\(tappedPath.id) frames=\(zoneFrames.count)")
            return
        }

        lastAlignmentMenuInteractionTime = CACurrentMediaTime()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            alignmentMenuState = state
        }
        recordInteractionTrace(
            "MENU present path=\(tappedPath.id) frame=\(traceRect(state.frame)) anchor=\(tracePoint(state.anchor))"
        )
        ZoneEditorDebugStore.shared.recordAlignment(debugSummary(for: state, action: "present"))
    }

    private func refreshAlignmentMenu(contentWidth: CGFloat, frames: [ZoneEditorResolvedZoneFrame]) {
        guard let currentState = alignmentMenuState,
              let refreshedState = resolvedAlignmentMenuState(
                  for: currentState.tappedPath,
                  contentWidth: contentWidth,
                  frames: frames,
                  preferredAnchor: currentState.anchor
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
        recordInteractionTrace("MENU dismiss")
        withAnimation(.easeOut(duration: 0.16)) {
            alignmentMenuState = nil
        }
        alignmentWiggleTask?.cancel()
        alignmentWiggleTask = nil
        alignmentWiggleTarget = nil
        alignmentWiggleOffset = 0
        thawFrameUpdates()
    }

    private func refreshBottomScrollInset(
        animationDuration: TimeInterval = 0,
        animationOptions: UIView.AnimationOptions = [.curveEaseOut]
    ) {
        let inset = dynamicBottomScrollInset
        if inset <= 0.5 {
            scrollDriver.resetBottomInset(
                animationDuration: animationDuration,
                animationOptions: animationOptions
            )
        } else {
            scrollDriver.setBottomInset(inset)
        }
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

        updateRenderMeasuredContentSize(from: frames, contentWidth: contentWidth)

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

    private func updateRenderMeasuredContentSize(
        from frames: [ZoneEditorResolvedZoneFrame],
        contentWidth: CGFloat
    ) {
        guard !frames.isEmpty else { return }

        let minY = frames.map(\.frame.minY).min() ?? 0
        let maxY = frames.map(\.frame.maxY).max() ?? 0
        let measuredHeight = ceil(max(maxY - minY, 1))
        let measuredSize = CGSize(width: max(contentWidth, 1), height: measuredHeight)
        let oldSize = renderMeasuredContentSize

        if abs(oldSize.width - measuredSize.width) > 0.5
            || abs(oldSize.height - measuredSize.height) > 0.5 {
            renderMeasuredContentSize = measuredSize
        }
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

    private func commitRenderScreenZoneFrames(_ frames: [ZoneEditorResolvedZoneFrame]) {
        guard !resolvedFramesMatch(renderScreenZoneFrames, frames) else { return }
        renderScreenZoneFrames = frames
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
        let position = alignmentMenuPosition(for: menuState, contentWidth: contentWidth)
        let transitionAnchor = UnitPoint(
            x: min(max((menuState.anchor.x - position.x) / menuWidth, 0), 1),
            y: (menuState.anchor.y - position.y) / menuHeight
        )

        return HStack(spacing: 4) {
            alignmentMenuButton(systemName: "chevron.compact.left") {
                performAlignmentAction(.left)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 18)
                .allowsHitTesting(false)

            alignmentMenuButton(systemName: "chevron.compact.right") {
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
        .offset(x: position.x, y: position.y)
        .transition(.scale(scale: 0.82, anchor: transitionAnchor).combined(with: .opacity))
        .zIndex(4)
    }

    private func alignmentMenuButton(
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            lastAlignmentMenuInteractionTime = CACurrentMediaTime()
            action()
        } label: {
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
        frames: [ZoneEditorResolvedZoneFrame],
        preferredAnchor: CGPoint? = nil
    ) -> ZoneAlignmentMenuState? {
        guard let target = resolveAlignmentTarget(for: tappedPath, contentWidth: contentWidth, frames: frames) else {
            return nil
        }
        let anchor = preferredAnchor ?? CGPoint(x: target.frame.midX, y: target.frame.maxY)

        return ZoneAlignmentMenuState(
            target: target.targetRef,
            tappedPath: tappedPath,
            frame: target.frame,
            anchor: anchor,
            movementWidth: target.movementWidth,
            currentAlignment: target.currentAlignment
        )
    }

    private func alignmentMenuPosition(
        for menuState: ZoneAlignmentMenuState,
        contentWidth: CGFloat
    ) -> CGPoint {
        let menuWidth = Self.alignmentMenuSize.width
        let menuHeight = Self.alignmentMenuSize.height
        let x = clampedMenuX(
            anchorX: menuState.anchor.x,
            menuWidth: menuWidth,
            contentWidth: contentWidth
        )
        let preferredY = menuState.anchor.y + Self.alignmentMenuVerticalSpacing
        if rendersRichText {
            return CGPoint(x: x, y: preferredY)
        }

        let visibleTopY = renderVisibleContentTopY
        let visibleBottomY = visibleTopY + max(viewportScreenFrame.height, menuHeight)
        let minY = visibleTopY + 8
        let maxY = max(visibleBottomY - menuHeight - 8, minY)
        let y = min(max(preferredY, minY), maxY)

        return CGPoint(x: x, y: y)
    }

    private var renderVisibleContentTopY: CGFloat {
        max(
            scrollDriver.effectiveNormalizedOffsetY() - contentVerticalPadding - topContentInset,
            0
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

        if !tappedZone.isLeaf,
           tappedZone.direction == .vertical,
           let groupFrame = frame(forSubtree: tappedPath, in: frames) {
            return (
                targetRef: ZoneAlignmentTargetRef(path: tappedPath, kind: .group),
                frame: groupFrame,
                movementWidth: availableAlignmentWidth(
                    for: tappedPath,
                    contentWidth: contentWidth,
                    frames: frames
                ),
                currentAlignment: resolvedAlignment(for: tappedZone, kind: .group)
            )
        }

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

    private func renderContentPoint(fromScreenPoint screenPoint: CGPoint, path: ZonePath) -> CGPoint? {
        guard let screenFrame = frame(for: path, in: renderScreenZoneFrames),
              let contentFrame = frame(for: path, in: zoneFrames) else {
            return nil
        }

        return CGPoint(
            x: contentFrame.minX + (screenPoint.x - screenFrame.minX),
            y: contentFrame.minY + (screenPoint.y - screenFrame.minY)
        )
    }

    private func renderedAlignmentGroupHit(
        at point: CGPoint,
        contentWidth: CGFloat,
        frames: [ZoneEditorResolvedZoneFrame]
    ) -> (path: ZonePath, hitFrame: CGRect)? {
        renderedAlignmentGroupHit(
            at: point,
            horizontalBounds: 0...contentWidth,
            frames: frames
        )
    }

    private func renderedAlignmentGroupHit(
        at point: CGPoint,
        horizontalBounds: ClosedRange<CGFloat>,
        frames: [ZoneEditorResolvedZoneFrame]
    ) -> (path: ZonePath, hitFrame: CGRect)? {
        var candidatePaths = Set<ZonePath>()

        for frame in frames {
            var candidatePath = frame.path.parent
            while let path = candidatePath {
                candidatePaths.insert(path)
                candidatePath = path.parent
            }
        }

        return candidatePaths.compactMap { path -> (path: ZonePath, hitFrame: CGRect)? in
            guard let zone = content.zone(at: path),
                  !zone.isLeaf,
                  zone.direction == .vertical,
                  renderedDirectChildCount(under: path, frames: frames) > 1,
                  let contentFrame = frame(forSubtree: path, in: frames) else {
                return nil
            }

            let expandedFrame = contentFrame.insetBy(
                dx: -contentHorizontalPadding,
                dy: -ZoneContentMetrics.childSpacing
            )
            let minX = max(expandedFrame.minX, horizontalBounds.lowerBound)
            let maxX = min(expandedFrame.maxX, horizontalBounds.upperBound)
            let hitFrame = CGRect(
                x: minX,
                y: expandedFrame.minY,
                width: max(maxX - minX, 0),
                height: expandedFrame.height
            )

            guard hitFrame.contains(point) else { return nil }
            return (path, hitFrame)
        }
        .min {
            ($0.hitFrame.width * $0.hitFrame.height)
                < ($1.hitFrame.width * $1.hitFrame.height)
        }
    }

    private func renderedDirectChildCount(
        under path: ZonePath,
        frames: [ZoneEditorResolvedZoneFrame]
    ) -> Int {
        Set(frames.compactMap { frame -> Int? in
            guard frame.path.indices.starts(with: path.indices),
                  frame.path.indices.count > path.indices.count else {
                return nil
            }
            return frame.path.indices[path.indices.count]
        }).count
    }

    private func siblingFrames(
        in frames: [ZoneEditorResolvedZoneFrame],
        under parentPath: ZonePath,
        directChildCount: Int
    ) -> [ZoneEditorResolvedZoneFrame] {
        let directChildPaths = (0 ..< directChildCount).map { parentPath.appending($0) }

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
        let contentWidth = max(viewportScreenFrame.width - (contentHorizontalPadding * 2), 1)
        let position = alignmentMenuPosition(for: state, contentWidth: contentWidth)
        let visibleTopY = renderVisibleContentTopY
        let visibleBottomY = visibleTopY + max(viewportScreenFrame.height, Self.alignmentMenuSize.height)

        return "align \(action) target=\(state.target.path.id) tapped=\(state.tappedPath.id) kind=\(state.target.kind.debugName) frame=\(Int(state.frame.width))x\(Int(state.frame.height))@\(Int(state.frame.minX)),\(Int(state.frame.minY)) anchor=\(tracePoint(state.anchor)) pos=\(tracePoint(position)) scroll=\(Int(scrollDriver.effectiveNormalizedOffsetY())) visible=\(Int(visibleTopY))...\(Int(visibleBottomY)) cur=\(state.currentAlignment.rawValue) moveW=\(Int(state.movementWidth))"
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

        return scrollSelectedZoneFrameAboveBottomChromeIfNeeded()
    }

    @discardableResult
    private func scrollActiveCaretAboveBottomChromeIfNeeded() -> Bool {
        guard activeCaretPathID == selectedPath?.id,
              keyboardMonitor.isVisible,
              isKeyboardAvoidanceChromeReady
        else {
            debugStore.recordScrollDecision(
                "scroll-skip",
                zoneID: selectedZone?.id,
                details: "reason=not-ready activePath=\(activeCaretPathID ?? "nil") selectedPath=\(selectedPath?.id ?? "nil") keyboard=\(keyboardMonitor.isVisible ? 1 : 0) chrome=\(isKeyboardAvoidanceChromeReady ? 1 : 0)"
            )
            return false
        }

        guard let caretWindowRect = activeCaretWindowRect else {
            debugStore.recordScrollDecision(
                "scroll-skip",
                zoneID: selectedZone?.id,
                details: "reason=no-caret-rect"
            )
            return false
        }

        let didScroll = scrollDriver.scrollWindowRectAboveBottomChromeIfNeeded(
            windowRect: caretWindowRect,
            bottomChromeTopY: bottomAccessoryTopY,
            keyboardHeight: keyboardMonitor.visibleHeight,
            bottomAccessoryHeight: bottomAccessoryHeight,
            bottomBuffer: caretBottomChromeBuffer,
            animationDuration: caretScrollAnimationDuration,
            animationOptions: keyboardMonitor.animationOptions,
            zoneID: selectedZone?.id
        )
        if didScroll {
            activeCaretWindowRect = nil
        }
        return didScroll
    }

    @discardableResult
    private func scrollSelectedZoneFrameAboveBottomChromeIfNeeded() -> Bool {
        guard keyboardMonitor.isVisible,
              let selectedFrame,
              let selectedZoneID = selectedZone?.id else {
            debugStore.recordScrollDecision(
                "scroll-skip",
                zoneID: selectedZone?.id,
                details: "reason=no-selected-frame"
            )
            return false
        }

        return scrollDriver.scrollContentRectAboveBottomChromeIfNeeded(
            contentRect: selectedFrame,
            contentTopOffset: contentVerticalPadding + topContentInset,
            bottomChromeTopY: bottomAccessoryTopY,
            keyboardHeight: keyboardMonitor.visibleHeight,
            bottomAccessoryHeight: bottomAccessoryHeight,
            bottomBuffer: caretBottomChromeBuffer,
            animationDuration: caretScrollAnimationDuration,
            animationOptions: keyboardMonitor.animationOptions,
            zoneID: selectedZoneID
        )
    }

    private func scheduleCaretAvoidanceScroll(
        delay: Duration = .milliseconds(120)
    ) {
        scheduledBottomChromeScrollTask?.cancel()
        guard shouldMaintainKeyboardAvoidance else {
            debugStore.recordScrollDecision(
                "scroll-schedule-skip",
                zoneID: selectedZone?.id,
                details: "reason=shouldMaintainKeyboardAvoidance-false keyboard=\(keyboardMonitor.isVisible ? 1 : 0) focused=\(shortID(focusManager.focusedZoneID)) selected=\(shortID(selectedZone?.id))"
            )
            return
        }

        scrollDriver.releaseOffsetLock()
        scheduledBottomChromeScrollTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, shouldMaintainKeyboardAvoidance else { return }

            let didScroll = scrollFocusedEditingContentAboveBottomChromeIfNeeded()
            if !didScroll {
                try? await Task.sleep(for: .milliseconds(24))
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

    private var selectedZone: ZoneModel? {
        guard let selectedPath else { return nil }
        return content.zone(at: selectedPath)
    }

    private func shortID(_ id: UUID?) -> String {
        guard let id else { return "nil" }
        return String(id.uuidString.prefix(6))
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

    private func caretScrollSource(from notification: Notification) -> ZoneEditorCaretScrollSource {
        guard let rawValue = notification.userInfo?[ZoneEditorCaretScrollNotification.sourceKey] as? String,
              let source = ZoneEditorCaretScrollSource(rawValue: rawValue) else {
            return .selectionTap
        }

        return source
    }

    private var keyboardTopDebugScreenY: CGFloat? {
        guard keyboardMonitor.isVisible || keyboardMonitor.visibleHeight > 0 else { return nil }
        return UIScreen.main.bounds.maxY - max(keyboardMonitor.visibleHeight, 0)
    }

    private var toolbarTopDebugScreenY: CGFloat? {
        let fallbackTopY = fallbackBottomChromeTopY(viewportBottomY: UIScreen.main.bounds.maxY)
        guard let bottomAccessoryTopY else { return fallbackTopY }
        guard let fallbackTopY else { return bottomAccessoryTopY }
        return min(bottomAccessoryTopY, fallbackTopY)
    }

    private var visibleBottomDebugScreenY: CGFloat? {
        let viewportBottomY = UIScreen.main.bounds.maxY - caretBottomChromeBuffer
        guard let toolbarTopDebugScreenY else { return viewportBottomY }
        return min(viewportBottomY, toolbarTopDebugScreenY - caretBottomChromeBuffer)
    }

    private var activeBottomChromeClearance: CGFloat {
        dynamicBottomScrollInset
    }

    private var legacyRawBottomChromeClearance: CGFloat {
        max(bottomAccessoryHeight, 0) + (keyboardMonitor.isVisible ? caretBottomChromeBuffer + 80 : 48)
    }

    private var caretBottomChromeBuffer: CGFloat {
        72
    }

    private var dynamicBottomScrollInset: CGFloat {
        guard keyboardMonitor.isVisible || bottomAccessoryHeight > 0 else {
            return 0
        }

        let viewportBottomY = viewportScreenFrame.height > 0
            ? viewportScreenFrame.maxY
            : UIScreen.main.bounds.maxY
        let chromeTopY = bottomAccessoryTopY ?? fallbackBottomChromeTopY(viewportBottomY: viewportBottomY)
        let chromeClearance = chromeTopY.map { max(viewportBottomY - $0, 0) } ?? max(bottomAccessoryHeight, 0)
        let keyboardClearance = keyboardMonitor.isVisible ? max(keyboardMonitor.visibleHeight, 0) : 0
        return max(
            chromeClearance,
            keyboardClearance + max(bottomAccessoryHeight, 0),
            max(bottomAccessoryHeight, 0)
        ) + caretBottomChromeBuffer
    }

    private func fallbackBottomChromeTopY(viewportBottomY: CGFloat) -> CGFloat? {
        guard keyboardMonitor.isVisible || bottomAccessoryHeight > 0 else { return nil }
        return viewportBottomY
            - max(keyboardMonitor.visibleHeight, 0)
            - max(bottomAccessoryHeight, 0)
    }

    private var caretScrollAnimationDuration: TimeInterval {
        guard keyboardMonitor.isVisible else { return 0.12 }
        return min(max(keyboardMonitor.animationDuration * 0.42, 0.12), 0.18)
    }

    private var keyboardDismissScrollAnimationDuration: TimeInterval {
        min(max(keyboardMonitor.animationDuration, 0.22), 0.32)
    }

    private var bottomScrollInsetAnimation: Animation {
        .easeOut(duration: keyboardDismissScrollAnimationDuration)
    }

    private func clearRawTextSelectionAfterKeyboardDismissIfIdle(reason: String) {
        guard !rendersRichText,
              !keyboardMonitor.isVisible,
              focusManager.focusedZoneID == nil,
              focusManager.pendingFocusZoneID == nil,
              let path = selectedPath,
              let zone = content.zone(at: path),
              !zone.isEditorMediaLeaf else {
            return
        }
        clearActiveCaretGeometry()
        selectedPath = nil
        ZoneEditorDebugStore.shared.recordEditorState(
            "keyboard.dismiss-clear-selection",
            details: "reason=\(reason) path=\(path.id) zone=\(shortID(zone.id))"
        )
    }

    private func recordKeyboardStateFlow(_ stage: String, details: String) {
        ZoneEditorDebugStore.shared.recordEditorState(
            stage,
            details: "render=\(rendersRichText ? 1 : 0) selectedPath=\(selectedPath?.id ?? "nil") selectedZone=\(shortID(selectedZone?.id)) focused=\(shortID(focusManager.focusedZoneID)) pending=\(shortID(focusManager.pendingFocusZoneID)) kb=\(keyboardMonitor.isVisible ? 1 : 0):\(debugNumber(keyboardMonitor.visibleHeight)) dur=\(debugNumber(keyboardMonitor.animationDuration)) accessory=\(debugNumber(bottomAccessoryHeight)) inset=\(debugNumber(scrollDriver.currentContentInsetBottom))/\(debugNumber(scrollDriver.currentAdjustedContentInsetBottom)) offset=\(debugNumber(scrollDriver.effectiveNormalizedOffsetY())) \(details) scroll={\(scrollDriver.debugSnapshotDetails())}"
        )
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
                    scrollY: scrollDriver.effectiveNormalizedOffsetY(),
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
        if showsEditorDebugHUD {
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
        if showsEditorDebugHUD {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                    )

                scrollDebugLine(
                    screenY: keyboardTopDebugScreenY,
                    color: .orange,
                    title: "keyboard top"
                )
                scrollDebugLine(
                    screenY: toolbarTopDebugScreenY,
                    color: .purple,
                    title: "toolbar top"
                )
                scrollDebugLine(
                    screenY: visibleBottomDebugScreenY,
                    color: .green,
                    title: "visible bottom"
                )
                if let activeCaretWindowRect {
                    scrollDebugLine(
                        screenY: activeCaretWindowRect.maxY,
                        color: .red,
                        title: "caret bottom"
                    )
                }

                VStack(alignment: .leading, spacing: 3) {
                    layoutDebugSummary(snapshot: rawLayoutDebugSnapshot, color: .green)
                    layoutDebugSummary(snapshot: renderLayoutDebugSnapshot, color: .pink)
                    Text(scrollDebugSummaryText)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 3))
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
    private func scrollDebugLine(
        screenY: CGFloat?,
        color: Color,
        title: String
    ) -> some View {
        if let screenY,
           viewportScreenFrame.height > 0,
           screenY.isFinite {
            let localY = screenY - viewportScreenFrame.minY
            if localY >= 0,
               localY <= viewportScreenFrame.height {
                HStack(spacing: 4) {
                    Rectangle()
                        .stroke(
                            color.opacity(0.95),
                            style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                        )
                        .frame(maxWidth: .infinity, minHeight: 1.5, maxHeight: 1.5)

                    Text(title)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 4))
                }
                .offset(y: localY)
            }
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

    private var scrollDebugSummaryText: String {
        "offset=\(debugNumber(scrollDriver.effectiveNormalizedOffsetY())) kb=\(debugNumber(keyboardMonitor.visibleHeight)) toolbar=\(debugNumber(bottomAccessoryHeight))\nvisible=\(debugOptionalNumber(visibleBottomDebugScreenY)) caret=\(debugOptionalNumber(activeCaretWindowRect?.maxY))"
    }

    private func debugNumber(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    private func debugNumber(_ value: TimeInterval) -> String {
        String(format: "%.3f", value)
    }

    private func debugOptionalNumber(_ value: CGFloat?) -> String {
        guard let value else { return "nil" }
        return debugNumber(value)
    }

    private func handleScrollOffsetChange(_ offsetY: CGFloat) {
        onScrollOffsetChange(offsetY)
    }

    private func handleUIKitTapProbe(_ snapshot: ZoneEditorTapProbeSnapshot) {
        let localPoint = CGPoint(
            x: snapshot.contentPoint.x - contentHorizontalPadding,
            y: snapshot.contentPoint.y - contentVerticalPadding - topContentInset
        )
        let candidateFrames = renderSelectableFrames
            .filter {
                $0.frame
                    .insetBy(
                        dx: -Self.renderLeafHorizontalHitSlop,
                        dy: -Self.renderLeafVerticalHitSlop
                    )
                    .contains(localPoint)
            }
        let matchedPath = candidateFrames
            .min { ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height) }?
            .path.id ?? "nil"

        recordInteractionTrace(
            "SCROLL TAP raw=\(tracePoint(snapshot.contentPoint)) local=\(tracePoint(localPoint)) hit=\(snapshot.hitViewName)"
        )
        recordInteractionTrace(
            "CLASSIFY candidates=\(candidateFrames.map(\.path.id).joined(separator: ",")) decision=KEEP"
        )

        guard showsDebugTools else { return }

        let line = "probe tap content=\(Int(localPoint.x)),\(Int(localPoint.y)) window=\(Int(snapshot.windowPoint.x)),\(Int(snapshot.windowPoint.y)) scroll=\(Int(scrollDriver.effectiveNormalizedOffsetY())) hit=\(snapshot.hitViewName) super=\(snapshot.hitSuperviewName) frames=\(zoneFrames.count) match=\(matchedPath) swift=\(lastTapDebugLine)"
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

    private var alignmentMenuFrame: CGRect? {
        guard let menuState = alignmentMenuState else { return nil }

        return CGRect(
            x: alignmentMenuPosition(
                for: menuState,
                contentWidth: viewportScreenFrame.width - (contentHorizontalPadding * 2)
            ).x,
            y: alignmentMenuPosition(
                for: menuState,
                contentWidth: viewportScreenFrame.width - (contentHorizontalPadding * 2)
            ).y,
            width: Self.alignmentMenuSize.width,
            height: Self.alignmentMenuSize.height
        )
    }

    private var alignmentMenuScreenFrame: CGRect? {
        guard let menuState = alignmentMenuState,
              let menuFrame = alignmentMenuFrame else {
            return nil
        }

        let targetPath = menuState.target.path
        let screenTargetFrame: CGRect?
        switch menuState.target.kind {
        case .group:
            screenTargetFrame = frame(forSubtree: targetPath, in: renderScreenZoneFrames)
        case .leaf:
            screenTargetFrame = frame(for: targetPath, in: renderScreenZoneFrames)
        }

        guard let screenTargetFrame else { return nil }

        return menuFrame.offsetBy(
            dx: screenTargetFrame.minX - menuState.frame.minX,
            dy: screenTargetFrame.minY - menuState.frame.minY
        )
    }

    private func handleWindowTouchProbe(_ snapshot: ZoneEditorWindowTouchSnapshot) {
        let selected = selectedPath?.id ?? "nil"
        let rootID = content.rootZone.id.uuidString.prefix(6)
        let effectiveScrollOffsetY = scrollDriver.effectiveNormalizedOffsetY()
        let contentPoint = CGPoint(
            x: snapshot.viewportPoint.x - contentHorizontalPadding,
            y: snapshot.viewportPoint.y
                + effectiveScrollOffsetY
                - contentVerticalPadding
                - topContentInset
        )
        let candidateFrames = renderSelectableFrames.filter {
            $0.frame
                .insetBy(
                    dx: -Self.renderLeafHorizontalHitSlop,
                    dy: -Self.renderLeafVerticalHitSlop
                )
                .contains(contentPoint)
        }
        let tappedFrame = candidateFrames.min {
            ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
        }
        let renderContentWidth = max(
            viewportScreenFrame.width - (contentHorizontalPadding * 2),
            1
        )
        let screenCandidateFrames = renderScreenZoneFrames.filter { frame in
            content.zone(at: frame.path)?.isLeaf == true
                && frame.frame
                    .insetBy(
                        dx: -Self.renderLeafHorizontalHitSlop,
                        dy: -Self.renderLeafVerticalHitSlop
                    )
                    .contains(snapshot.windowPoint)
        }
        let screenHorizontalBounds = (viewportScreenFrame.minX + contentHorizontalPadding)...(viewportScreenFrame.minX + contentHorizontalPadding + renderContentWidth)
        let screenGroupHit = renderScreenZoneFrames.isEmpty ? nil : renderedAlignmentGroupHit(
            at: snapshot.windowPoint,
            horizontalBounds: screenHorizontalBounds,
            frames: renderScreenZoneFrames
        )
        let groupHit = renderedAlignmentGroupHit(
            at: contentPoint,
            contentWidth: renderContentWidth,
            frames: zoneFrames
        )
        let tappedAlignmentMenuInContent = alignmentMenuFrame?
            .insetBy(dx: -24, dy: -24)
            .contains(contentPoint) ?? false
        let tappedAlignmentMenuInScreen = alignmentMenuScreenFrame?
            .insetBy(dx: -24, dy: -24)
            .contains(snapshot.windowPoint) ?? false
        let tappedAlignmentMenu = tappedAlignmentMenuInContent || tappedAlignmentMenuInScreen
        let isCompletedTap = snapshot.phase.contains("ended/") && snapshot.phase.hasSuffix("/now")
        let recentlyInteractedWithMenu = CACurrentMediaTime() - lastAlignmentMenuInteractionTime < 0.35
        let menuIsOpen = alignmentMenuState != nil
        let groupHitForSelection = (screenCandidateFrames.isEmpty ? screenGroupHit : nil) ?? groupHit
        let shouldSelectGroup = isCompletedTap
            && snapshot.isTapLike
            && !tappedAlignmentMenu
            && (screenGroupHit != nil ? screenCandidateFrames.isEmpty : candidateFrames.isEmpty)
            && groupHitForSelection != nil
        let shouldDismissMenu = isCompletedTap
            && snapshot.isTapLike
            && menuIsOpen
            && !tappedAlignmentMenu
            && (renderScreenZoneFrames.isEmpty ? groupHit == nil : screenGroupHit == nil)

        windowTouchDebugLines = [
            "WIN \(snapshot.phase) p=\(Int(snapshot.windowPoint.x)),\(Int(snapshot.windowPoint.y)) viewport=\(snapshot.viewportDescription)",
            "HIT \(snapshot.hitViewDescription)",
            "CHAIN \(snapshot.hitViewChain)",
            "CANVAS render=\(rendersRichText ? 1 : 0) root=\(rootID) selected=\(selected) frames=\(zoneFrames.count) scroll=\(Int(effectiveScrollOffsetY))",
        ] + snapshot.gestureLines
        ZoneEditorDebugStore.shared.recordTap(
            "window \(snapshot.phase) hit=\(snapshot.hitViewName) gestures=\(snapshot.gestureCount)"
        )
        recordInteractionTrace(
            "WINDOW \(snapshot.phase) point=\(tracePoint(snapshot.windowPoint)) hit=\(snapshot.hitViewName) tapLike=\(snapshot.isTapLike ? 1 : 0) gestures=\(snapshot.gestureCount)"
        )
        recordInteractionTrace(
            "WINDOW CLASSIFY viewport=\(tracePoint(snapshot.viewportPoint)) content=\(tracePoint(contentPoint)) scroll=\(Int(effectiveScrollOffsetY)) menu=\(alignmentMenuState == nil ? "closed" : "open") inMenu=\(tappedAlignmentMenu ? 1 : 0) recentMenu=\(recentlyInteractedWithMenu ? 1 : 0) completed=\(isCompletedTap ? 1 : 0) candidates=\(candidateFrames.map(\.path.id).joined(separator: ",")) screenCandidates=\(screenCandidateFrames.map(\.path.id).joined(separator: ",")) group=\(groupHit?.path.id ?? "nil") screenGroup=\(screenGroupHit?.path.id ?? "nil") decision=\(shouldSelectGroup ? "SELECT_GROUP" : shouldDismissMenu ? "DISMISS_MENU" : menuIsOpen ? "KEEP_MENU_OPEN" : isCompletedTap && tappedFrame != nil && !tappedAlignmentMenu ? "SELECT" : "KEEP")"
        )

        if shouldSelectGroup, let groupHit = groupHitForSelection {
            let anchor = screenGroupHit == nil
                ? contentPoint
                : renderContentPoint(fromScreenPoint: snapshot.windowPoint, path: groupHit.path) ?? contentPoint
            selectRenderedAlignmentGroup(
                groupHit,
                contentWidth: renderContentWidth,
                anchor: anchor,
                source: "window tap group"
            )
            recordInteractionTrace(
                "WINDOW SELECT_GROUP path=\(groupHit.path.id) frame=\(traceRect(groupHit.hitFrame))"
            )
            return
        }

        if shouldDismissMenu {
            dismissAlignmentMenu()
            recordInteractionTrace("WINDOW DISMISS_MENU")
            return
        }

        if menuIsOpen {
            return
        }

        guard isCompletedTap,
              snapshot.isTapLike,
              !menuIsOpen,
              !tappedAlignmentMenu,
              let tappedFrame,
              content.zone(at: tappedFrame.path) != nil else {
            return
        }

        handleRenderedZoneTap(
            tappedFrame.zoneID,
            contentWidth: max(viewportScreenFrame.width - (contentHorizontalPadding * 2), 1),
            tapLocation: contentPoint
        )
        recordInteractionTrace(
            "WINDOW SELECT path=\(tappedFrame.path.id) frame=\(traceRect(tappedFrame.frame))"
        )
    }

    private func recordInteractionTrace(_ event: String) {
        guard showsDebugTools else { return }
        interactionTraceIndex += 1
        let line = "#\(interactionTraceIndex) \(event)"
        guard interactionTrace.last != line else { return }
        interactionTrace.append(line)
        if interactionTrace.count > 24 {
            interactionTrace.removeFirst(interactionTrace.count - 24)
        }
    }

    private func tracePoint(_ point: CGPoint) -> String {
        "\(Int(point.x)),\(Int(point.y))"
    }

    private func traceRect(_ rect: CGRect) -> String {
        "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width))x\(Int(rect.height))"
    }

    private var interactionTraceReport: String {
        let menu = alignmentMenuState.map {
            let contentWidth = max(viewportScreenFrame.width - (contentHorizontalPadding * 2), 1)
            let position = alignmentMenuPosition(for: $0, contentWidth: contentWidth)
            return "open target=\($0.target.path.id) tapped=\($0.tappedPath.id) frame=\(traceRect($0.frame)) anchor=\(tracePoint($0.anchor)) pos=\(tracePoint(position)) scroll=\(Int(scrollDriver.effectiveNormalizedOffsetY()))"
        } ?? "closed"
        let frames = zoneFrames
            .map { "\($0.path.id)=\(traceRect($0.frame))" }
            .joined(separator: "\n")

        return """
        QuizFlash Zone Editor Debug
        timestamp: \(ISO8601DateFormatter().string(from: Date()))
        mode: \(rendersRichText ? "render" : "raw")
        menu: \(menu)
        viewport: \(traceRect(viewportScreenFrame))
        scrollY: \(Int(scrollDriver.effectiveNormalizedOffsetY()))
        tapProbe: \(scrollDriver.tapProbeStatus)
        padding: \(Int(contentHorizontalPadding)),\(Int(contentVerticalPadding))
        topContentInset: \(Int(topContentInset))
        selectedPath: \(selectedPath?.id ?? "nil")

        ZONE FRAMES
        \(frames.isEmpty ? "<none>" : frames)

        RENDER LEAF METRICS
        \(renderLeafDebugReport)

        EVENT FLOW
        \(interactionTrace.isEmpty ? "<none>" : interactionTrace.joined(separator: "\n"))

        LAYOUT / RENDER TIMELINE
        \(debugStore.layoutTraceReport)
        """
    }

    private var windowTouchProbeBackground: AnyView {
        guard rendersRichText else {
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
        if showsDebugTools && (developmentPreferences.zoneEditorDebugHUDEnabled || showsGridDebugOverlay) {
            VStack(alignment: .leading, spacing: 3) {
                if developmentPreferences.zoneEditorDebugHUDEnabled {
                    Text("DBG ON")
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.orange, in: Capsule(style: .continuous))

                    Button {
                        UIPasteboard.general.string = interactionTraceReport
                    } label: {
                        Text("COPY DEBUG")
                            .font(.caption2.monospaced().weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.orange, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedDebugLine)
                        if let selectedFrame {
                            Text("rect \(Int(selectedFrame.width))x\(Int(selectedFrame.height)) @ \(Int(selectedFrame.minX)),\(Int(selectedFrame.minY))")
                        }
                        ForEach(Array(debugStore.compactHudLines.enumerated()), id: \.offset) { _, line in
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

        return "selected \(selectedPath.id) size=\(zone.sizeMode.rawValue)"
    }

    private var selectedFrame: CGRect? {
        guard let selectedPath else { return nil }
        return zoneFrames.first { $0.path == selectedPath }?.frame
    }

    private var renderLeafDebugReport: String {
        guard rendersRichText else { return "<raw mode>" }
        guard !renderLeafDebugSnapshots.isEmpty else { return "<none captured>" }

        return renderLeafDebugSnapshots
            .flatMap(Self.renderLeafLines(for:))
            .joined(separator: "\n")
    }

    private nonisolated static func renderLeafLines(for leaf: ZoneContentLeafLayoutDebugSnapshot) -> [String] {
        let textWidthLimit = leaf.textWidthLimit ?? leaf.contentLayoutWidth
        let maxEstimatedLine = leaf.estimatedLineWidths.max() ?? 0
        let remainingTextWidth = max(textWidthLimit - maxEstimatedLine, 0)
        let measurementEvents = leaf.measurementEvents.isEmpty
            ? "    <none>"
            : leaf.measurementEvents.map { "    \($0)" }.joined(separator: "\n")
        let estimatedLineWidths = leaf.estimatedLineWidths.map(metric).joined(separator: ", ")
        let renderedLineWidths = leaf.renderedLineWidths.map(metric).joined(separator: ", ")
        let renderedLines = leaf.renderedLineTexts.enumerated()
            .map { index, text in
                let width = index < leaf.renderedLineWidths.count ? leaf.renderedLineWidths[index] : 0
                return "    \(index + 1). [\(metric(width))] \"\(singleLinePreview(text, limit: 120))\""
            }
            .joined(separator: "\n")

        return [
            "- \(leaf.path) id=\(leaf.zoneID.uuidString)",
            "  type=\(leaf.contentType.rawValue) chars=\(leaf.textCharacterCount) hasContent=\(leaf.hasContent) math=\(leaf.containsMath) inlineCode=\(leaf.containsInlineCode)",
            "  availableWidth=\(metric(leaf.availableWidth)) estimated=\(size(leaf.estimatedSize)) rendered=\(size(leaf.renderedContentSize)) rawMeasured=\(size(leaf.rawMeasuredContentSize))",
            "  block=\(size(leaf.blockSize)) leadingInset=\(metric(leaf.leadingInset)) contentLayoutWidth=\(metric(leaf.contentLayoutWidth)) textWidthLimit=\(metric(textWidthLimit)) remainingTextWidthAfterWidestLine=\(metric(remainingTextWidth))",
            "  textInsets=\(metric(leaf.textHorizontalInsets)) intrinsicText=\(leaf.usesIntrinsicTextMeasurement)",
            "  measurements updates=\(leaf.measurementUpdateCount) resets=\(leaf.measurementResetCount) last=\(leaf.lastMeasurementSource) \"\(leaf.lastMeasurementDecision)\"",
            "  measurementFlow:",
            measurementEvents,
            "  estimatedLineWidths=[\(estimatedLineWidths)] renderedLineWidths=[\(renderedLineWidths)]",
            "  renderedLines:",
            renderedLines.isEmpty ? "    <none>" : renderedLines,
            "  preview=\"\(leaf.textPreview)\"",
            "  fullText:",
            leaf.fullText.isEmpty ? "  <empty>" : indentMultiline(leaf.fullText, prefix: "  | "),
        ]
    }

    private nonisolated static func singleLinePreview(_ value: String, limit: Int) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "..."
    }

    private nonisolated static func indentMultiline(_ value: String, prefix: String) -> String {
        value.components(separatedBy: .newlines)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    private nonisolated static func size(_ size: CGSize) -> String {
        "\(metric(size.width)) x \(metric(size.height))"
    }

    private nonisolated static func metric(_ value: CGFloat) -> String {
        Double(value).formatted(.number.precision(.fractionLength(0 ... 1)))
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

    private func contentNeedsBottomScrollInset(
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        contentTopOffset: CGFloat,
        requestedBottomScrollInset: CGFloat
    ) -> Bool {
        guard requestedBottomScrollInset > 0 else { return false }

        let layout = contentLayoutMetrics(
            contentSize: CGSize(width: contentWidth, height: contentHeight)
        )
        let contentBodyHeight = bottomInsetContentBodyHeight(
            layout: layout,
            contentWidth: contentWidth
        )
        let visibleContentHeight = bottomChromeVisibleContentHeight(
            contentHeight: contentHeight,
            contentTopOffset: contentTopOffset
        )
        let activationHeight = keyboardMonitor.isVisible || bottomAccessoryHeight > 0
            ? visibleContentHeight
            : contentHeight * 0.5

        return ceil(contentBodyHeight) >= floor(activationHeight)
    }

    private func bottomInsetContentBodyHeight(
        layout: ZoneContentLayout,
        contentWidth: CGFloat
    ) -> CGFloat {
        guard !rendersRichText else {
            return layout.contentBodyHeight
        }

        let measuredFrameHeight = measuredContentBodySize(contentWidth: contentWidth).height
        let estimatedFrameHeight = ZoneContentEstimator.estimatedSize(
            for: content.rootZone,
            fontScale: fontScale,
            availableWidth: max(contentWidth, 1)
        ).height

        return max(layout.contentBodyHeight, measuredFrameHeight, estimatedFrameHeight)
    }

    private func bottomChromeVisibleContentHeight(
        contentHeight: CGFloat,
        contentTopOffset: CGFloat
    ) -> CGFloat {
        guard viewportScreenFrame.height > 0 else {
            return contentHeight
        }

        let viewportBottomY = viewportScreenFrame.maxY - caretBottomChromeBuffer
        let fallbackChromeTopY: CGFloat?
        if keyboardMonitor.isVisible || bottomAccessoryHeight > 0 {
            fallbackChromeTopY = UIScreen.main.bounds.maxY
                - max(keyboardMonitor.visibleHeight, 0)
                - max(bottomAccessoryHeight, 0)
        } else {
            fallbackChromeTopY = nil
        }

        let chromeTopY: CGFloat?
        if let bottomAccessoryTopY, let fallbackChromeTopY {
            chromeTopY = min(bottomAccessoryTopY, fallbackChromeTopY)
        } else {
            chromeTopY = bottomAccessoryTopY ?? fallbackChromeTopY
        }

        let visibleBottomWindowY = chromeTopY.map {
            min(viewportBottomY, $0 - caretBottomChromeBuffer)
        } ?? viewportBottomY
        let contentTopWindowY = viewportScreenFrame.minY + contentTopOffset
        let visibleContentHeight = visibleBottomWindowY - contentTopWindowY

        return min(max(visibleContentHeight, 1), contentHeight)
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
            scrollOffsetY: scrollDriver.effectiveNormalizedOffsetY(),
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
        showsEditorDebugHUD || showsGridDebugOverlay
    }

    private var showsEditorDebugHUD: Bool {
        AppFeatures.current.showsVisualDebugOverlays
            && showsDebugOverlays
            && developmentPreferences.zoneEditorDebugHUDEnabled
    }

    private var showsGridDebugOverlay: Bool {
        AppFeatures.current.showsVisualDebugOverlays
            && showsDebugOverlays
            && developmentPreferences.zoneContentLayoutDebugEnabled
    }
}

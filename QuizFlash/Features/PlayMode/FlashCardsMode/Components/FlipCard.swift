//
//  FlipCard.swift
//  QuizFlash
//
//  A SwiftUI view that renders both faces of a flashcard and animates
//  a 3D flip transition between the question (front) and answer (back) faces.
//
//  Content overflow is handled by one stable vertical scroll surface, with
//  `scrollDisabled(true)` when content fits so gestures pass through to
//  `SwipeableCard`'s UIKit recognisers unobstructed.
//

import SwiftUI
import UIKit

// MARK: - Flashcard Play Layout Tuning

enum FlashcardPlayLayoutTuning {
    static let screenToCardHorizontalPaddingCompact: CGFloat = 8
//    static let screenToCardHorizontalPaddingCompact: CGFloat = 12
    static let screenToCardHorizontalPaddingRegular: CGFloat = 8
//    static let screenToCardHorizontalPaddingRegular: CGFloat = 24

    static let cardToContentHorizontalPaddingCompact: CGFloat = 4
    static let cardToContentHorizontalPaddingRegular: CGFloat = 4
    static let cardToContentVerticalPaddingCompact: CGFloat = 4
    static let cardToContentVerticalPaddingRegular: CGFloat = 4
}

// MARK: - Static Swap Transition

private struct StaticSwapTransitionModifier: ViewModifier {
    let scale: CGFloat
    let opacity: Double
    let blurRadius: CGFloat
    let verticalOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .blur(radius: blurRadius)
            .offset(y: verticalOffset)
    }
}

private struct StaticSwapFaceStateModifier: ViewModifier {
    let isVisible: Bool
    let textMotion: FlashcardStaticSwapTextMotion
    let insertionDirection: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(isVisible ? 1 : 0.001)
            .blur(radius: blurRadius)
            .offset(y: verticalOffset)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }

    private var scale: CGFloat {
        guard textMotion == .animated else { return 1 }
        return isVisible ? 1 : 0.972
    }

    private var blurRadius: CGFloat {
        guard textMotion == .animated else { return 0 }
        return isVisible ? 0 : 6
    }

    private var verticalOffset: CGFloat {
        guard textMotion == .animated else { return 0 }
        return isVisible ? 0 : 8 * insertionDirection
    }
}

private extension View {
    func staticSwapFaceState(
        isVisible: Bool,
        textMotion: FlashcardStaticSwapTextMotion,
        insertionDirection: CGFloat
    ) -> some View {
        modifier(
            StaticSwapFaceStateModifier(
                isVisible: isVisible,
                textMotion: textMotion,
                insertionDirection: insertionDirection
            )
        )
    }
}

private extension AnyTransition {
    static var flashcardStaticSwap: AnyTransition {
            .asymmetric(
            insertion: .modifier(
                active: StaticSwapTransitionModifier(
                    scale: 0.972,
                    opacity: 0,
                    blurRadius: 6,
                    verticalOffset: 8
                ),
                identity: StaticSwapTransitionModifier(
                    scale: 1,
                    opacity: 1,
                    blurRadius: 0,
                    verticalOffset: 0
                )
            ),
            removal: .modifier(
                active: StaticSwapTransitionModifier(
                    scale: 1.018,
                    opacity: 0,
                    blurRadius: 8,
                    verticalOffset: -6
                ),
                identity: StaticSwapTransitionModifier(
                    scale: 1,
                    opacity: 1,
                    blurRadius: 0,
                    verticalOffset: 0
                )
            )
        )
    }
}

private struct FlipFaceModifier: AnimatableModifier {
    var rotationDegrees: Double
    var perspective: CGFloat = 0.78

    var animatableData: Double {
        get { rotationDegrees }
        set { rotationDegrees = newValue }
    }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(rotationDegrees),
            axis: (x: 0, y: 1, z: 0),
            perspective: perspective
        )
            // Keep the hidden face mounted so WebKit-backed math can pre-render.
            .opacity(isFacingViewer ? 1 : 0.001)
            .allowsHitTesting(isFacingViewer)
            .accessibilityHidden(!isFacingViewer)
    }

    private var isFacingViewer: Bool {
        let normalized = normalizedDegrees(rotationDegrees)
        return normalized < 90 || normalized > 270
    }

    private func normalizedDegrees(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }
}

private struct PlayModeScrollBounceDisabler: UIViewRepresentable {
    let resetToken: Int

    final class Coordinator {
        var appliedResetToken: Int?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = view.nearestAncestorScrollView() else { return }
            scrollView.bounces = false
            scrollView.alwaysBounceVertical = false

            guard context.coordinator.appliedResetToken != resetToken else { return }
            context.coordinator.appliedResetToken = resetToken
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top),
                animated: false
            )
        }
    }
}

private extension UIView {
    func nearestAncestorScrollView() -> UIScrollView? {
        var current = superview
        while let view = current {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }
}

// MARK: - FlipCard

/// Renders the question and answer faces of a flashcard using either a 3D
/// flip or a static content swap controlled by the `isFlipped` binding.
///
/// The view uses one scroll surface for both short and overflowing content so
/// WebKit-rendered math/code can settle without switching view trees mid-frame.
///
/// ## Performance Notes
/// - 3D flip visibility is gated by the live rotation angle so front/back text
///   never cross-fade through each other mid-flip.
/// - `contentShape(Rectangle())` ensures the full card surface forwards touches
///   to `SwipeableCard`'s underlying UIKit gesture recognisers.
struct FlipCard: View {
    private enum FaceDebugTimeline {
        static let maxEvents = 80
    }

    private enum FaceMarker {
        case question
        case answer

        var debugTitle: String {
            switch self {
            case .question:
                return "front"
            case .answer:
                return "back"
            }
        }

        var title: String {
            switch self {
            case .question:
                return "Q"
            case .answer:
                return "A"
            }
        }

        var tint: Color {
            switch self {
            case .question:
                return Color.white
            case .answer:
                return Color(red: 0.58, green: 0.84, blue: 0.12)
            }
        }
    }

    // MARK: - Properties

    /// Decoded content for the question face.
    private let frontZone: ZoneModel

    /// Decoded content for the answer face.
    private let backZone: ZoneModel

    /// Stable identity used to clear face-local layout measurements when a
    /// buffered card view is reused for another playable payload.
    private let contentIdentity: String

    /// Controls which face is currently visible.
    ///
    /// `false` = front (question), `true` = back (answer).
    @Binding var isFlipped: Bool
    private let tapAnimationStyle: FlashcardTapAnimationStyle
    private let staticSwapTextMotion: FlashcardStaticSwapTextMotion
    private let contentAlignment: FlashcardContentAlignment
    private let textSize: FlashcardTextSize
    private let onTap: (() -> Void)?
    private let onLayoutDebugSnapshot: ((ZoneContentLayoutDebugSnapshot) -> Void)?

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(DevelopmentPreferences.self) private var developmentPreferences

    // MARK: - State

    /// Measured rendered size of the front face content.
    @State private var frontContentSize: CGSize = .zero

    /// Measured rendered size of the back face content.
    @State private var backContentSize: CGSize = .zero

    @State private var latestFrontLayoutDebugSnapshot: ZoneContentLayoutDebugSnapshot?
    @State private var latestBackLayoutDebugSnapshot: ZoneContentLayoutDebugSnapshot?
    @State private var frontMeasurementSource = "none"
    @State private var backMeasurementSource = "none"
    @State private var frontFaceDebugEvents: [String] = []
    @State private var backFaceDebugEvents: [String] = []
    @State private var faceDebugStartDate = Date()
    @State private var scrollResetGeneration = 0

    // MARK: - Convenience

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var playModeTextScale: CGFloat {
        CGFloat(textSize.playModeScale)
    }
    private var cardCornerRadius: CGFloat { isCompact ? 42 : 52 }
    private var hPad: CGFloat {
        isCompact
            ? FlashcardPlayLayoutTuning.cardToContentHorizontalPaddingCompact
        : FlashcardPlayLayoutTuning.cardToContentHorizontalPaddingRegular
    }
    private var vPad: CGFloat {
        isCompact
            ? FlashcardPlayLayoutTuning.cardToContentVerticalPaddingCompact
        : FlashcardPlayLayoutTuning.cardToContentVerticalPaddingRegular
    }
    private var faceMarkerInset: CGFloat { isCompact ? 8 : 10 }
    private var faceMarkerFrameSize: CGFloat { isCompact ? 22 : 24 }
    private var cardSurfaceFill: Color {
        colorScheme == .dark
            ? Color(red: 0.068, green: 0.068, blue: 0.068)
        : Color(red: 0.92, green: 0.92, blue: 0.91)
    }
    private var cardBorderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.045)
        : Color.black.opacity(0.08)
    }
    private var cardInnerHighlightColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.025)
        : Color.white.opacity(0.36)
    }
    private var cardShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.42)
        : Color.black.opacity(0.12)
    }

    // MARK: - Init

    /// Creates a card renderer from a playback snapshot.
    init(
        card: PlayableCard,
        isFlipped: Binding<Bool>,
        tapAnimationStyle: FlashcardTapAnimationStyle,
        staticSwapTextMotion: FlashcardStaticSwapTextMotion = .animated,
        contentAlignment: FlashcardContentAlignment = .center,
        textSize: FlashcardTextSize = .large,
        onTap: (() -> Void)? = nil,
        onLayoutDebugSnapshot: ((ZoneContentLayoutDebugSnapshot) -> Void)? = nil
    ) {
        self.frontZone = card.frontZone
        self.backZone = card.backZone
        self.contentIdentity = String(describing: card.id)
        self._isFlipped = isFlipped
        self.tapAnimationStyle = tapAnimationStyle
        self.staticSwapTextMotion = staticSwapTextMotion
        self.contentAlignment = contentAlignment
        self.textSize = textSize
        self.onTap = onTap
        self.onLayoutDebugSnapshot = onLayoutDebugSnapshot
    }

    /// Creates a card renderer directly from question and answer zones.
    init(
        frontZone: ZoneModel,
        backZone: ZoneModel,
        isFlipped: Binding<Bool>,
        tapAnimationStyle: FlashcardTapAnimationStyle,
        staticSwapTextMotion: FlashcardStaticSwapTextMotion = .animated,
        contentAlignment: FlashcardContentAlignment = .center,
        textSize: FlashcardTextSize = .large,
        onTap: (() -> Void)? = nil,
        onLayoutDebugSnapshot: ((ZoneContentLayoutDebugSnapshot) -> Void)? = nil
    ) {
        self.frontZone = frontZone
        self.backZone = backZone
        self.contentIdentity = "\(frontZone.id.uuidString)|\(backZone.id.uuidString)"
        self._isFlipped = isFlipped
        self.tapAnimationStyle = tapAnimationStyle
        self.staticSwapTextMotion = staticSwapTextMotion
        self.contentAlignment = contentAlignment
        self.textSize = textSize
        self.onTap = onTap
        self.onLayoutDebugSnapshot = onLayoutDebugSnapshot
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch tapAnimationStyle {
            case .flip3D:
                threeDimensionalFlipBody
            case .staticSwap:
                staticSwapBody
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Full-surface hit testing so SwipeableCard gestures fire everywhere.
        .contentShape(Rectangle())
            .onAppear {
            recordFaceDebugEvent(.question, "card appear identity=\(contentIdentity) visible=\(visibleMarker.debugTitle) front=\(frontZone.id.uuidString.prefix(6)) back=\(backZone.id.uuidString.prefix(6))")
            recordFaceDebugEvent(.answer, "card appear identity=\(contentIdentity) visible=\(visibleMarker.debugTitle) front=\(frontZone.id.uuidString.prefix(6)) back=\(backZone.id.uuidString.prefix(6))")
        }
            .onChange(of: isFlipped) { oldValue, newValue in
            scrollResetGeneration += 1
            NotificationCenter.default.post(
                name: .quizFlashMixedMathVisibilityProbe,
                object: nil,
                userInfo: [
                    "reason": "flip \(oldValue ? "back" : "front")->\(newValue ? "back" : "front")"
                ]
            )
            recordFaceDebugEvent(.question, "flip changed \(oldValue ? "back" : "front")->\(newValue ? "back" : "front") visible=\(visibleMarker.debugTitle)")
            recordFaceDebugEvent(.answer, "flip changed \(oldValue ? "back" : "front")->\(newValue ? "back" : "front") visible=\(visibleMarker.debugTitle)")
            publishStoredLayoutDebugSnapshot()
        }
            .onChange(of: contentIdentity) { oldValue, newValue in
            resetFaceMeasurements(clearDebugEvents: true)
            recordFaceDebugEvent(.question, "identity changed \(oldValue)->\(newValue); measurements reset")
            recordFaceDebugEvent(.answer, "identity changed \(oldValue)->\(newValue); measurements reset")
        }
    }

    // MARK: - Card Face Builder

    private var threeDimensionalFlipBody: some View {
        let rotation = isFlipped ? 180.0 : 0.0

        return ZStack {
            cardFace(zone: backZone, marker: .answer, contentSize: $backContentSize)
                .modifier(FlipFaceModifier(rotationDegrees: rotation + 180))

            cardFace(zone: frontZone, marker: .question, contentSize: $frontContentSize)
                .modifier(FlipFaceModifier(rotationDegrees: rotation))
        }
    }

    private var staticSwapBody: some View {
        ZStack {
            cardFace(zone: backZone, marker: .answer, contentSize: $backContentSize)
                .staticSwapFaceState(
                    isVisible: isFlipped,
                    textMotion: staticSwapTextMotion,
                    insertionDirection: 1
                )
                .zIndex(isFlipped ? 2 : 1)

            cardFace(zone: frontZone, marker: .question, contentSize: $frontContentSize)
                .staticSwapFaceState(
                    isVisible: !isFlipped,
                    textMotion: staticSwapTextMotion,
                    insertionDirection: -1
                )
                .zIndex(isFlipped ? 1 : 2)
        }
    }

    @ViewBuilder
    private func cardFace(
        zone: ZoneModel,
        marker: FaceMarker,
        contentSize: Binding<CGSize>
    ) -> some View {
        cardShell(marker: marker) {
            cardFaceContent(zone: zone, marker: marker, contentSize: contentSize)
        }
    }

    @ViewBuilder
    private func cardShell<Content: View>(
        marker: FaceMarker,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let cardShape = RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)

        ZStack {
            content()
        }
            .background {
            cardShape
                .fill(cardSurfaceFill)
                .shadow(color: cardShadowColor, radius: isCompact ? 18 : 24, y: 10)
        }
            .overlay {
            cardShape
                .strokeBorder(cardBorderColor, lineWidth: 1)
        }
            .overlay {
            cardShape
                .strokeBorder(cardInnerHighlightColor, lineWidth: 0.7)
                .blur(radius: 1.2)
                .clipShape(cardShape)
        }
            .clipShape(cardShape)
            .overlay(alignment: .bottomTrailing) {
            faceMarkerBadge(marker)
                .padding(.bottom, faceMarkerInset + 2)
                .padding(.trailing, faceMarkerInset)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func cardFaceContent(
        zone: ZoneModel,
        marker: FaceMarker,
        contentSize: Binding<CGSize>
    ) -> some View {
        adaptiveScrollableContent(zone: zone, marker: marker, contentSize: contentSize)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func measuredFaceContent(
        zone: ZoneModel,
        marker: FaceMarker,
        contentSize: Binding<CGSize>,
        containerSize: CGSize,
        contentWidth: CGFloat,
        centersLeafBlocks: Bool,
        minimumMeasuredHeight: CGFloat,
        maximumMeasuredHeight: CGFloat
    ) -> some View {
        ZoneContentRenderView(
            zone: zone,
            fontScale: playModeTextScale,
            availableWidth: contentWidth,
            centersLeafBlocks: centersLeafBlocks,
            showsDebugGuides: showsZoneContentGuides,
            collectsDebugMetrics: onLayoutDebugSnapshot != nil,
            leafTapBehavior: .richContentOnly,
            onTap: onTap
        )
            .coordinateSpace(name: ZoneContentRenderCoordinateSpace.name)
            .frame(width: contentWidth, alignment: .topLeading)
            .onGeometryChange(for: CGSize.self) { proxy in
            CGSize(
                width: ceil(proxy.size.width),
                height: ceil(proxy.size.height)
            )
        } action: { newSize in
            updateMeasuredFaceContentSize(
                newSize,
                marker: marker,
                contentSize: contentSize,
                containerSize: containerSize,
                minimumMeasuredHeight: minimumMeasuredHeight,
                maximumMeasuredHeight: maximumMeasuredHeight,
                source: "root-geometry"
            )
        }
            .onPreferenceChange(ZoneContentRenderBlockBoundsPreferenceKey.self) { bounds in
            let expectedLeafCount = ZoneContentRenderPolicy.renderableLeafCount(in: zone)
            guard let blockSize = measuredContentSize(
                from: bounds,
                expectedLeafCount: expectedLeafCount,
                fallbackWidth: contentWidth
            ) else {
                let reportedLeafCount = Set(bounds.map(\.zoneID)).count
                recordFaceDebugEvent(
                    marker,
                    "geometry ignored incomplete-bounds reported=\(reportedLeafCount) expected=\(expectedLeafCount)"
                )
                return
            }
            updateMeasuredFaceContentSize(
                blockSize,
                marker: marker,
                contentSize: contentSize,
                containerSize: containerSize,
                minimumMeasuredHeight: minimumMeasuredHeight,
                maximumMeasuredHeight: maximumMeasuredHeight,
                source: "leaf-block-bounds"
            )
        }
    }

    private func updateMeasuredFaceContentSize(
        _ newSize: CGSize,
        marker: FaceMarker,
        contentSize: Binding<CGSize>,
        containerSize: CGSize,
        minimumMeasuredHeight: CGFloat,
        maximumMeasuredHeight: CGFloat,
        source: String
    ) {
        guard containerSize.width > 1, containerSize.height > 1 else {
                recordFaceDebugEvent(marker, "geometry ignored pending-container container=\(debugSize(containerSize)) raw=\(debugSize(newSize))")
                return
            }
        guard newSize.width > 0, newSize.height > 0 else {
            recordFaceDebugEvent(marker, "geometry ignored non-positive source=\(source) raw=\(debugSize(newSize))")
            return
        }
        guard newSize.height + 0.5 >= minimumMeasuredHeight else {
            recordFaceDebugEvent(marker, "geometry rejected source=\(source) raw=\(debugSize(newSize)) minH=\(debugMetric(minimumMeasuredHeight)) old=\(debugSize(contentSize.wrappedValue))")
            return
        }
        guard newSize.height <= maximumMeasuredHeight else {
            recordFaceDebugEvent(marker, "geometry rejected oversized source=\(source) raw=\(debugSize(newSize)) maxH=\(debugMetric(maximumMeasuredHeight)) old=\(debugSize(contentSize.wrappedValue))")
            return
        }

        let oldSize = contentSize.wrappedValue
        let oldSource = measurementSource(for: marker)
        if source == "root-geometry",
           oldSource == "leaf-block-bounds",
           oldSize.height > 0 {
            recordFaceDebugEvent(
                marker,
                "geometry ignored root-fallback-after-leaf raw=\(debugSize(newSize)) old=\(debugSize(oldSize))"
            )
            return
        }

        if source == "root-geometry",
           oldSize.height > 0,
           newSize.height > oldSize.height * 1.5,
           newSize.height - oldSize.height > 120 {
            recordFaceDebugEvent(marker, "geometry rejected stale-root raw=\(debugSize(newSize)) old=\(debugSize(oldSize))")
            return
        }

        if abs(oldSize.width - newSize.width) > 0.5
            || abs(oldSize.height - newSize.height) > 0.5 {
            contentSize.wrappedValue = newSize
            setMeasurementSource(source, for: marker)
            recordFaceDebugEvent(marker, "geometry accepted source=\(source) old=\(debugSize(oldSize)) new=\(debugSize(newSize)) minH=\(debugMetric(minimumMeasuredHeight))")
        } else {
            recordFaceDebugEvent(marker, "geometry unchanged source=\(source) raw=\(debugSize(newSize)) old=\(debugSize(oldSize))")
        }
    }

    private func measuredContentSize(
        from bounds: [ZoneContentRenderBlockBounds],
        expectedLeafCount: Int,
        fallbackWidth: CGFloat
    ) -> CGSize? {
        let framesByZone = Dictionary(
            bounds.compactMap { bound -> (UUID, CGRect)? in
                let frame = bound.frame
                guard !frame.isNull,
                      !frame.isInfinite,
                      frame.width > 0,
                      frame.height > 0 else {
                    return nil
                }
                return (bound.zoneID, frame)
            },
            uniquingKeysWith: { _, latest in latest }
        )
        guard expectedLeafCount > 0,
              framesByZone.count == expectedLeafCount else {
            return nil
        }
        let frames = Array(framesByZone.values)

        let minY = min(frames.map(\.minY).min() ?? 0, 0)
        let maxY = frames.map(\.maxY).max() ?? 0
        let maxX = frames.map(\.maxX).max() ?? fallbackWidth
        return CGSize(
            width: ceil(max(fallbackWidth, maxX)),
            height: ceil(max(maxY - minY, 1))
        )
    }

    // MARK: - Adaptive Scroll Content

    /// Uses one stable vertical scroll container for all card content.
    ///
    /// Rich/code/math content is measured asynchronously by WebKit, so switching
    /// between separate scale and scroll trees can leave the card in the wrong
    /// branch for a frame or more. A single scroll surface keeps long content
    /// scrollable as soon as its true height arrives, while short content remains
    /// vertically centered by adding symmetric spacer height.
    @ViewBuilder
    private func adaptiveScrollableContent(
        zone: ZoneModel,
        marker: FaceMarker,
        contentSize: Binding<CGSize>
    ) -> some View {
        GeometryReader { available in
            let fallbackVerticalAlignment = ZoneVerticalAlignment(fallbackContentAlignment: contentAlignment)
            let faceVerticalAlignment = zone.verticalAlignment.resolved(fallback: fallbackVerticalAlignment)
            let availableContentWidth = max(available.size.width - (hPad * 2), 1)
            let estimatedContentSize = ZoneContentEstimator.estimatedSize(
                for: zone,
                fontScale: playModeTextScale,
                availableWidth: availableContentWidth
            )
            let layoutMeasuredContentSize = resolvedFaceMeasuredContentSize(
                contentSize.wrappedValue,
                estimatedContentSize: estimatedContentSize
            )
            let layout = ZoneContentLayout(
                containerSize: available.size,
                horizontalPadding: hPad,
                verticalPadding: vPad,
                estimatedContentSize: estimatedContentSize,
                measuredContentSize: layoutMeasuredContentSize,
                verticalAlignment: faceVerticalAlignment
            )
            let layoutDebugKey = faceLayoutDebugKey(
                marker: marker,
                rawMeasuredContentSize: contentSize.wrappedValue,
                appliedMeasuredContentSize: layoutMeasuredContentSize,
                estimatedContentSize: estimatedContentSize,
                layout: layout
            )

            if zone.hasContent {
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        scrollOffsetProbe(marker: marker)

                        if showsZoneContentGuides {
                            zoneContentDebugGuides(layout: layout)
                        }

                        measuredFaceContent(
                            zone: zone,
                            marker: marker,
                            contentSize: contentSize,
                            containerSize: available.size,
                            contentWidth: layout.availableContentWidth,
                            centersLeafBlocks: faceVerticalAlignment == .center,
                            minimumMeasuredHeight: minimumFaceMeasurementHeight(
                                estimatedContentSize: estimatedContentSize
                            ),
                            maximumMeasuredHeight: maximumFaceMeasurementHeight(
                                estimatedContentSize: estimatedContentSize,
                                containerSize: available.size
                            )
                        )
                            .onPreferenceChange(ZoneContentLeafDebugPreferenceKey.self) { leafSnapshots in
                            updateLayoutDebugSnapshot(
                                marker: marker,
                                layout: layout,
                                leafSnapshots: leafSnapshots
                            )
                        }
                            .padding(.top, vPad + layout.contentTopInset)
                            .padding(.leading, hPad)
                            .padding(.bottom, vPad + layout.contentBottomInset)
                    }
                        .frame(
                        width: available.size.width,
                        height: layout.scrollContentHeight,
                        alignment: .topLeading
                    )
                }
                    .scrollDisabled(layout.contentFitsVertically)
                    .background(
                    PlayModeScrollBounceDisabler(
                        resetToken: marker == visibleMarker ? scrollResetGeneration : -1
                    )
                )
                    .coordinateSpace(name: scrollCoordinateSpaceName(marker))
                    .id(scrollContainerIdentity(marker))
                    .frame(width: available.size.width, height: available.size.height)
                    .onAppear {
                    recordFaceDebugEvent(marker, "layout appear \(layoutDebugKey)")
                }
                    .onChange(of: layoutDebugKey) { _, newValue in
                    recordFaceDebugEvent(marker, "layout changed \(newValue)")
                }
            } else {
                emptyContent
                    .frame(width: available.size.width, height: available.size.height)
                    .contentShape(Rectangle())
            }
        }
    }

    @ViewBuilder
    private func zoneContentDebugGuides(layout: ZoneContentLayout) -> some View {
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
            .padding(.leading, hPad)
            .padding(.top, vPad)
            .allowsHitTesting(false)
    }

    // MARK: - Empty State

    /// Placeholder displayed when the zone contains no renderable content.
    private var emptyContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.quote")
                .font(.system(size: isCompact ? 40 : 56))
                .foregroundStyle(.tertiary)
            Text("No content")
                .font(isCompact ? .body : .title3)
                .foregroundStyle(.secondary)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func faceMarkerBadge(_ marker: FaceMarker) -> some View {
        Text(marker.title)
            .font(.system(size: isCompact ? 16 : 18, weight: .black, design: .rounded))
            .foregroundStyle(marker.tint)
            .frame(width: faceMarkerFrameSize, height: faceMarkerFrameSize)
            .opacity(0.24)
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            .accessibilityHidden(true)
    }

    private var showsZoneContentGuides: Bool {
        AppFeatures.current.showsVisualDebugOverlays
            && developmentPreferences.zoneContentLayoutDebugEnabled
    }

    private var visibleMarker: FaceMarker {
        isFlipped ? .answer : .question
    }

    private func resetFaceMeasurements(clearDebugEvents: Bool = false) {
        frontContentSize = .zero
        backContentSize = .zero
        frontMeasurementSource = "none"
        backMeasurementSource = "none"
        latestFrontLayoutDebugSnapshot = nil
        latestBackLayoutDebugSnapshot = nil
        if clearDebugEvents {
            frontFaceDebugEvents = []
            backFaceDebugEvents = []
            faceDebugStartDate = Date()
            scrollResetGeneration = 0
        }
    }

    private func minimumFaceMeasurementHeight(estimatedContentSize: CGSize) -> CGFloat {
        max(1, ceil(estimatedContentSize.height * 0.25))
    }

    private func maximumFaceMeasurementHeight(
        estimatedContentSize: CGSize,
        containerSize: CGSize
    ) -> CGFloat {
        max(
            ceil(estimatedContentSize.height * 12),
            ceil(containerSize.height * 12),
            1
        )
    }

    private func resolvedFaceMeasuredContentSize(
        _ measuredSize: CGSize,
        estimatedContentSize: CGSize
    ) -> CGSize {
        guard measuredSize.width > 0, measuredSize.height > 0 else { return .zero }
        guard measuredSize.height + 0.5 >= minimumFaceMeasurementHeight(estimatedContentSize: estimatedContentSize) else {
            return .zero
        }

        return measuredSize
    }

    private func updateLayoutDebugSnapshot(
        marker: FaceMarker,
        layout: ZoneContentLayout,
        leafSnapshots: [ZoneContentLeafLayoutDebugSnapshot]
    ) {
        guard onLayoutDebugSnapshot != nil else { return }

        let snapshot = ZoneContentLayoutDebugSnapshot(
            face: marker.debugTitle,
            containerSize: roundedSize(layout.containerSize),
            horizontalPadding: ceil(layout.horizontalPadding),
            verticalPadding: ceil(layout.verticalPadding),
            availableContentSize: roundedSize(layout.debugAvailableFrame),
            estimatedContentSize: roundedSize(layout.estimatedContentSize),
            measuredContentSize: roundedSize(layout.measuredContentSize),
            measurementSource: measurementSource(for: marker),
            contentBodyHeight: ceil(layout.contentBodyHeight),
            contentFitsVertically: layout.contentFitsVertically,
            centeredTopInset: ceil(layout.centeredTopInset),
            scrollContentHeight: ceil(layout.scrollContentHeight),
            faceDebugEvents: faceDebugEvents(for: marker),
            leafSnapshots: leafSnapshots.sorted { $0.path < $1.path }
        )

        switch marker {
        case .question:
            latestFrontLayoutDebugSnapshot = snapshot
        case .answer:
            latestBackLayoutDebugSnapshot = snapshot
        }

        onLayoutDebugSnapshot?(snapshot)
    }

    private func publishStoredLayoutDebugSnapshot() {
        guard let onLayoutDebugSnapshot else { return }
        let snapshot = visibleMarker == .answer
            ? latestBackLayoutDebugSnapshot
        : latestFrontLayoutDebugSnapshot

        if let snapshot {
            onLayoutDebugSnapshot(snapshot)
        }
    }

    private func roundedSize(_ size: CGSize) -> CGSize {
        CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func scrollCoordinateSpaceName(_ marker: FaceMarker) -> String {
        "FlashcardFaceScroll-\(contentIdentity)-\(marker.debugTitle)"
    }

    private func scrollContainerIdentity(_ marker: FaceMarker) -> String {
        "\(contentIdentity)-\(marker.debugTitle)-scroll"
    }

    private func measurementSource(for marker: FaceMarker) -> String {
        switch marker {
        case .question:
            return frontMeasurementSource
        case .answer:
            return backMeasurementSource
        }
    }

    private func setMeasurementSource(_ source: String, for marker: FaceMarker) {
        switch marker {
        case .question:
            frontMeasurementSource = source
        case .answer:
            backMeasurementSource = source
        }
    }

    @ViewBuilder
    private func scrollOffsetProbe(marker: FaceMarker) -> some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(scrollCoordinateSpaceName(marker))).minY
            } action: { minY in
                recordFaceDebugEvent(marker, "scroll probe minY=\(debugMetric(minY)) offset=\(debugMetric(-minY)) visible=\(visibleMarker.debugTitle)")
            }
            .allowsHitTesting(false)
    }

    private func faceLayoutDebugKey(
        marker: FaceMarker,
        rawMeasuredContentSize: CGSize,
        appliedMeasuredContentSize: CGSize,
        estimatedContentSize: CGSize,
        layout: ZoneContentLayout
    ) -> String {
        [
            "face=\(marker.debugTitle)",
            "container=\(debugSize(layout.containerSize))",
            "available=\(debugSize(layout.debugAvailableFrame))",
            "estimate=\(debugSize(estimatedContentSize))",
            "rawMeasured=\(debugSize(rawMeasuredContentSize))",
            "appliedMeasured=\(debugSize(appliedMeasuredContentSize))",
            "bodyH=\(debugMetric(layout.contentBodyHeight))",
            "fits=\(layout.contentFitsVertically)",
            "topInset=\(debugMetric(layout.contentTopInset))",
            "centeredTop=\(debugMetric(layout.centeredTopInset))",
            "bottomInset=\(debugMetric(layout.contentBottomInset))",
            "scrollH=\(debugMetric(layout.scrollContentHeight))",
            "visible=\(visibleMarker.debugTitle)"
        ].joined(separator: " ")
    }

    private func recordFaceDebugEvent(_ marker: FaceMarker, _ message: String) {
        let event = "+\(debugMetric(Date().timeIntervalSince(faceDebugStartDate) * 1000))ms \(message)"

        switch marker {
        case .question:
            guard frontFaceDebugEvents.last != event else { return }
            frontFaceDebugEvents.append(event)
            if frontFaceDebugEvents.count > FaceDebugTimeline.maxEvents {
                frontFaceDebugEvents.removeFirst(frontFaceDebugEvents.count - FaceDebugTimeline.maxEvents)
            }
        case .answer:
            guard backFaceDebugEvents.last != event else { return }
            backFaceDebugEvents.append(event)
            if backFaceDebugEvents.count > FaceDebugTimeline.maxEvents {
                backFaceDebugEvents.removeFirst(backFaceDebugEvents.count - FaceDebugTimeline.maxEvents)
            }
        }
    }

    private func faceDebugEvents(for marker: FaceMarker) -> [String] {
        switch marker {
        case .question:
            frontFaceDebugEvents
        case .answer:
            backFaceDebugEvents
        }
    }

    private func debugSize(_ size: CGSize) -> String {
        "\(debugMetric(size.width))x\(debugMetric(size.height))"
    }

    private func debugMetric(_ value: CGFloat) -> String {
        debugMetric(Double(value))
    }

    private func debugMetric(_ value: TimeInterval) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.05 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", value)
    }

}

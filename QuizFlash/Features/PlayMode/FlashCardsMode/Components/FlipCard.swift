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
    let verticalOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
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
            .opacity(isVisible ? 1 : 0)
            .offset(y: verticalOffset)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }

    private var scale: CGFloat {
        guard textMotion == .animated else { return 1 }
        return isVisible ? 1 : 0.972
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
                    verticalOffset: 8
                ),
                identity: StaticSwapTransitionModifier(
                    scale: 1,
                    opacity: 1,
                    verticalOffset: 0
                )
            ),
            removal: .modifier(
                active: StaticSwapTransitionModifier(
                    scale: 1.018,
                    opacity: 0,
                    verticalOffset: -6
                ),
                identity: StaticSwapTransitionModifier(
                    scale: 1,
                    opacity: 1,
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
    /// Keeps diagnostic history outside SwiftUI's observation graph.
    ///
    /// Geometry callbacks can run repeatedly while a scene is being restored.
    /// Storing their log entries in `@State` invalidates this view and feeds the
    /// geometry pass back into itself. The reference is retained by `@State`,
    /// but mutations inside it intentionally do not trigger a render.
    private final class FaceDebugTimeline {
        static let maxEvents = 80

        private var frontEvents: [String] = []
        private var backEvents: [String] = []
        private var lastFrontMessage: String?
        private var lastBackMessage: String?
        private var startDate = Date()

        func record(_ marker: FaceMarker, message: String) {
            let event = formattedEvent(message)
            switch marker {
            case .question:
                guard lastFrontMessage != message else { return }
                lastFrontMessage = message
                Self.append(event, to: &frontEvents)
            case .answer:
                guard lastBackMessage != message else { return }
                lastBackMessage = message
                Self.append(event, to: &backEvents)
            }
        }

        func events(for marker: FaceMarker) -> [String] {
            switch marker {
            case .question:
                return frontEvents
            case .answer:
                return backEvents
            }
        }

        func reset() {
            frontEvents.removeAll(keepingCapacity: true)
            backEvents.removeAll(keepingCapacity: true)
            lastFrontMessage = nil
            lastBackMessage = nil
            startDate = Date()
        }

        private func formattedEvent(_ message: String) -> String {
            let elapsedMilliseconds = Date().timeIntervalSince(startDate) * 1000
            return "+\(Self.debugMetric(elapsedMilliseconds))ms \(message)"
        }

        private static func append(_ event: String, to events: inout [String]) {
            events.append(event)
            if events.count > Self.maxEvents {
                events.removeFirst(events.count - Self.maxEvents)
            }
        }

        private static func debugMetric(_ value: TimeInterval) -> String {
            let rounded = value.rounded()
            if abs(value - rounded) < 0.05 {
                return "\(Int(rounded))"
            }
            return String(format: "%.1f", value)
        }
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
    private let preloadsHiddenFace: Bool
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

    @State private var latestFrontLayoutDebugSnapshot: ZoneContentLayoutDebugSnapshot?
    @State private var latestBackLayoutDebugSnapshot: ZoneContentLayoutDebugSnapshot?
    @State private var faceDebugTimeline = FaceDebugTimeline()
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
        preloadsHiddenFace: Bool = true,
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
        self.preloadsHiddenFace = preloadsHiddenFace
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
        preloadsHiddenFace: Bool = true,
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
        self.preloadsHiddenFace = preloadsHiddenFace
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
            resetFaceDiagnostics(clearDebugEvents: true)
            recordFaceDebugEvent(.question, "identity changed \(oldValue)->\(newValue); measurements reset")
            recordFaceDebugEvent(.answer, "identity changed \(oldValue)->\(newValue); measurements reset")
        }
    }

    // MARK: - Card Face Builder

    private var threeDimensionalFlipBody: some View {
        let rotation = isFlipped ? 180.0 : 0.0

        return ZStack {
            if preloadsHiddenFace || isFlipped {
                cardFace(zone: backZone, marker: .answer)
                    .modifier(FlipFaceModifier(rotationDegrees: rotation + 180))
            }

            cardFace(zone: frontZone, marker: .question)
                .modifier(FlipFaceModifier(rotationDegrees: rotation))
        }
    }

    private var staticSwapBody: some View {
        ZStack {
            if preloadsHiddenFace || isFlipped {
                cardFace(zone: backZone, marker: .answer)
                    .staticSwapFaceState(
                        isVisible: isFlipped,
                        textMotion: staticSwapTextMotion,
                        insertionDirection: 1
                    )
                    .zIndex(isFlipped ? 2 : 1)
            }

            cardFace(zone: frontZone, marker: .question)
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
        marker: FaceMarker
    ) -> some View {
        cardShell(marker: marker) {
            cardFaceContent(zone: zone, marker: marker)
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
                .shadow(color: cardShadowColor, radius: isCompact ? 14 : 18, y: 8)
        }
            .overlay {
            cardShape
                .strokeBorder(cardBorderColor, lineWidth: 1)
        }
            .overlay {
            cardShape
                .strokeBorder(cardInnerHighlightColor, lineWidth: 0.7)
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
        marker: FaceMarker
    ) -> some View {
        adaptiveScrollableContent(zone: zone, marker: marker)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
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
        marker: FaceMarker
    ) -> some View {
        GeometryReader { available in
            let fallbackVerticalAlignment = ZoneVerticalAlignment(fallbackContentAlignment: contentAlignment)
            let faceVerticalAlignment = zone.verticalAlignment.resolved(fallback: fallbackVerticalAlignment)
            let layoutContext = ZoneContentSurfaceLayoutContext.viewport(
                size: available.size,
                horizontalPadding: hPad,
                verticalPadding: vPad,
                verticalAlignment: faceVerticalAlignment,
                verticalScrollPolicy: .automatic,
                scrollResetToken: marker == visibleMarker ? scrollResetGeneration : -1
            )
            let renderConfiguration = ZoneContentSurfaceRenderConfiguration(
                centersLeafBlocks: faceVerticalAlignment == .center,
                animatesLayoutChanges: false,
                showsDebugGuides: showsZoneContentGuides,
                showsViewportDebugGuide: showsZoneContentGuides,
                collectsDebugMetrics: onLayoutDebugSnapshot != nil,
                leafTapBehavior: .richContentOnly
            )
            let diagnosticsHandler: ((ZoneContentSurfaceDiagnostics) -> Void)? = onLayoutDebugSnapshot == nil
                ? nil
                : { diagnostics in
                    updateLayoutDebugSnapshot(
                        marker: marker,
                        diagnostics: diagnostics
                    )
                }
            let debugEventHandler: ((String) -> Void)? = onLayoutDebugSnapshot == nil
                ? nil
                : { event in
                    recordFaceDebugEvent(marker, event)
                }

            if zone.hasContent {
                ZoneContentSurface(
                    zone: zone,
                    fontScale: playModeTextScale,
                    layoutContext: layoutContext,
                    renderConfiguration: renderConfiguration,
                    identity: "\(contentIdentity)-\(marker.debugTitle)",
                    coordinateSpaceName: scrollCoordinateSpaceName(marker),
                    onTap: onTap,
                    onDiagnosticsChange: diagnosticsHandler,
                    onDebugEvent: debugEventHandler
                )
            } else {
                emptyContent
                    .frame(width: available.size.width, height: available.size.height)
                    .contentShape(Rectangle())
            }
        }
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
            .font(.system(size: isCompact ? 16 : 18, weight: .black))
            .foregroundStyle(marker.tint)
            .frame(width: faceMarkerFrameSize, height: faceMarkerFrameSize)
            .opacity(0.24)
            .accessibilityHidden(true)
    }

    private var showsZoneContentGuides: Bool {
        AppFeatures.current.showsVisualDebugOverlays
            && developmentPreferences.zoneContentLayoutDebugEnabled
    }

    private var visibleMarker: FaceMarker {
        isFlipped ? .answer : .question
    }

    private func resetFaceDiagnostics(clearDebugEvents: Bool = false) {
        latestFrontLayoutDebugSnapshot = nil
        latestBackLayoutDebugSnapshot = nil
        if clearDebugEvents {
            faceDebugTimeline.reset()
            scrollResetGeneration = 0
        }
    }

    private func updateLayoutDebugSnapshot(
        marker: FaceMarker,
        diagnostics: ZoneContentSurfaceDiagnostics
    ) {
        guard onLayoutDebugSnapshot != nil,
              let layout = diagnostics.metrics.layout else {
            return
        }
        recordFaceDebugEvent(
            marker,
            "layout changed \(faceLayoutDebugKey(marker: marker, metrics: diagnostics.metrics, layout: layout))"
        )

        let snapshot = ZoneContentLayoutDebugSnapshot(
            face: marker.debugTitle,
            containerSize: roundedSize(layout.containerSize),
            horizontalPadding: ceil(layout.horizontalPadding),
            verticalPadding: ceil(layout.verticalPadding),
            availableContentSize: roundedSize(layout.debugAvailableFrame),
            estimatedContentSize: roundedSize(layout.estimatedContentSize),
            measuredContentSize: roundedSize(layout.measuredContentSize),
            measurementSource: diagnostics.metrics.measurementSource,
            contentBodyHeight: ceil(layout.contentBodyHeight),
            contentFitsVertically: layout.contentFitsVertically,
            centeredTopInset: ceil(layout.centeredTopInset),
            scrollContentHeight: ceil(layout.scrollContentHeight),
            faceDebugEvents: faceDebugEvents(for: marker),
            leafSnapshots: diagnostics.leafSnapshots
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

    private func faceLayoutDebugKey(
        marker: FaceMarker,
        metrics: ZoneContentSurfaceMetrics,
        layout: ZoneContentLayout
    ) -> String {
        [
            "face=\(marker.debugTitle)",
            "container=\(debugSize(layout.containerSize))",
            "available=\(debugSize(layout.debugAvailableFrame))",
            "estimate=\(debugSize(layout.estimatedContentSize))",
            "rawMeasured=\(debugSize(metrics.rawMeasuredContentSize))",
            "appliedMeasured=\(debugSize(metrics.appliedMeasuredContentSize))",
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
        faceDebugTimeline.record(marker, message: message)
    }

    private func faceDebugEvents(for marker: FaceMarker) -> [String] {
        faceDebugTimeline.events(for: marker)
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

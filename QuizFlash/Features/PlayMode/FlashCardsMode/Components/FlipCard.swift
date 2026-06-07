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
            .opacity(isFacingViewer ? 1 : 0)
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

    /// Controls which face is currently visible.
    ///
    /// `false` = front (question), `true` = back (answer).
    @Binding var isFlipped: Bool
    private let tapAnimationStyle: FlashcardTapAnimationStyle
    private let staticSwapTextMotion: FlashcardStaticSwapTextMotion
    private let contentAlignment: FlashcardContentAlignment
    private let textSize: FlashcardTextSize
    private let onTap: (() -> Void)?
    private let onLayoutDebugSnapshot: ((FlashcardGridLayoutDebugSnapshot) -> Void)?

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(DevelopmentPreferences.self) private var developmentPreferences

    // MARK: - State

    /// Measured rendered size of the front face content.
    @State private var frontContentSize: CGSize = .zero

    /// Measured rendered size of the back face content.
    @State private var backContentSize: CGSize = .zero

    @State private var latestFrontLayoutDebugSnapshot: FlashcardGridLayoutDebugSnapshot?
    @State private var latestBackLayoutDebugSnapshot: FlashcardGridLayoutDebugSnapshot?

    // MARK: - Convenience

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var playModeTextScale: CGFloat {
        CGFloat(textSize.playModeScale)
    }
    private var cardCornerRadius: CGFloat { isCompact ? 42 : 52 }
    private var hPad: CGFloat { isCompact ? 20 : 28 }
    private var vPad: CGFloat { isCompact ? 20 : 24 }
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
        onLayoutDebugSnapshot: ((FlashcardGridLayoutDebugSnapshot) -> Void)? = nil
    ) {
        self.frontZone = card.frontZone
        self.backZone = card.backZone
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
        onLayoutDebugSnapshot: ((FlashcardGridLayoutDebugSnapshot) -> Void)? = nil
    ) {
        self.frontZone = frontZone
        self.backZone = backZone
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
        .onChange(of: isFlipped) { _, _ in
            publishStoredLayoutDebugSnapshot()
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
        Group {
            if staticSwapTextMotion == .animated {
                ZStack {
                    if isFlipped {
                        cardFace(zone: backZone, marker: .answer, contentSize: $backContentSize)
                            .id("back-face")
                            .transition(.flashcardStaticSwap)
                    } else {
                        cardFace(zone: frontZone, marker: .question, contentSize: $frontContentSize)
                            .id("front-face")
                            .transition(.flashcardStaticSwap)
                    }
                }
            } else if isFlipped {
                cardFace(zone: backZone, marker: .answer, contentSize: $backContentSize)
            } else {
                cardFace(zone: frontZone, marker: .question, contentSize: $frontContentSize)
            }
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
        contentSize: Binding<CGSize>,
        contentWidth: CGFloat,
        centersLeafBlocks: Bool
    ) -> some View {
        FlashcardGridFaceView(
            zone: zone,
            fontScale: playModeTextScale,
            availableWidth: contentWidth,
            centersLeafBlocks: centersLeafBlocks,
            showsDebugGuides: showsFlashcardGridGuides,
            collectsDebugMetrics: onLayoutDebugSnapshot != nil,
            leafTapBehavior: .richContentOnly,
            onTap: onTap
        )
            .frame(width: contentWidth, alignment: .topLeading)
            .onGeometryChange(for: CGSize.self) { proxy in
                CGSize(
                    width: ceil(proxy.size.width),
                    height: ceil(proxy.size.height)
                )
            } action: { newSize in
                guard newSize.width > 0, newSize.height > 0 else { return }
                let oldSize = contentSize.wrappedValue
                if abs(oldSize.width - newSize.width) > 0.5
                    || abs(oldSize.height - newSize.height) > 0.5 {
                    contentSize.wrappedValue = newSize
                }
            }
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
            let estimatedContentSize = FlashcardGridContentEstimator.estimatedSize(
                for: zone,
                fontScale: playModeTextScale,
                availableWidth: availableContentWidth
            )
            let layout = FlashcardGridContentLayout(
                containerSize: available.size,
                horizontalPadding: hPad,
                verticalPadding: vPad,
                estimatedContentSize: estimatedContentSize,
                measuredContentSize: contentSize.wrappedValue,
                verticalAlignment: faceVerticalAlignment
            )

            if zone.hasContent {
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        if showsFlashcardGridGuides {
                            flashcardGridDebugGuides(layout: layout)
                        }

                        measuredFaceContent(
                            zone: zone,
                            contentSize: contentSize,
                            contentWidth: layout.availableContentWidth,
                            centersLeafBlocks: faceVerticalAlignment == .center
                        )
                        .onPreferenceChange(FlashcardGridLeafDebugPreferenceKey.self) { leafSnapshots in
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
                .frame(width: available.size.width, height: available.size.height)
            } else {
                emptyContent
                    .frame(width: available.size.width, height: available.size.height)
                    .contentShape(Rectangle())
            }
        }
    }

    @ViewBuilder
    private func flashcardGridDebugGuides(layout: FlashcardGridContentLayout) -> some View {
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

    private var showsFlashcardGridGuides: Bool {
        AppFeatures.current.showsVisualDebugOverlays
            && developmentPreferences.flashcardGridTextLayoutDebugEnabled
    }

    private var visibleMarker: FaceMarker {
        isFlipped ? .answer : .question
    }

    private func updateLayoutDebugSnapshot(
        marker: FaceMarker,
        layout: FlashcardGridContentLayout,
        leafSnapshots: [FlashcardGridLeafLayoutDebugSnapshot]
    ) {
        guard onLayoutDebugSnapshot != nil else { return }

        let snapshot = FlashcardGridLayoutDebugSnapshot(
            face: marker.debugTitle,
            containerSize: roundedSize(layout.containerSize),
            horizontalPadding: ceil(layout.horizontalPadding),
            verticalPadding: ceil(layout.verticalPadding),
            availableContentSize: roundedSize(layout.debugAvailableFrame),
            estimatedContentSize: roundedSize(layout.estimatedContentSize),
            measuredContentSize: roundedSize(layout.measuredContentSize),
            contentBodyHeight: ceil(layout.contentBodyHeight),
            contentFitsVertically: layout.contentFitsVertically,
            centeredTopInset: ceil(layout.centeredTopInset),
            scrollContentHeight: ceil(layout.scrollContentHeight),
            leafSnapshots: leafSnapshots.sorted { $0.path < $1.path }
        )

        switch marker {
        case .question:
            latestFrontLayoutDebugSnapshot = snapshot
        case .answer:
            latestBackLayoutDebugSnapshot = snapshot
        }

        if marker == visibleMarker {
            onLayoutDebugSnapshot?(snapshot)
        }
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

}

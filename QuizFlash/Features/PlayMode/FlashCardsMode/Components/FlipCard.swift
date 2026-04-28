//
//  FlipCard.swift
//  QuizFlash
//
//  A SwiftUI view that renders both faces of a flashcard and animates
//  a 3D flip transition between the question (front) and answer (back) faces.
//
//  Content overflow is handled by two user-selectable modes:
//  - **Scale** — shrinks content proportionally to always fit inside the card.
//  - **Scroll** — enables vertical scrolling when content overflows, with
//    `scrollDisabled(true)` when content fits so gestures pass through
//    to `SwipeableCard`'s UIKit recognisers unobstructed.
//

import SwiftUI

// MARK: - ContentHeightKey

/// `PreferenceKey` used to propagate the natural (unconstrained) height of
/// card-face content up through the view hierarchy so the parent can decide
/// whether to scale or enable scrolling.
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
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
/// The view exposes two overflow modes via `CardContentMode`, allowing users
/// to choose between proportional scaling and a scrollable layout without
/// restarting the session.
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
    private let onTap: (() -> Void)?

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(CardAppearancePreferences.self) private var cardAppearancePreferences

    // MARK: - State

    /// Measured natural height of the front face content.
    @State private var frontContentHeight: CGFloat = 0

    /// Measured natural height of the back face content.
    @State private var backContentHeight: CGFloat = 0

    // MARK: - Convenience

    private var contentMode: CardContentMode {
        cardAppearancePreferences.cardContentMode
    }

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var playModeTextScale: CGFloat { 1.5 }
    private var cardCornerRadius: CGFloat { isCompact ? 42 : 52 }
    private var minimumScaledContentScale: CGFloat { 0.5 }
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
        onTap: (() -> Void)? = nil
    ) {
        self.frontZone = card.frontZone
        self.backZone = card.backZone
        self._isFlipped = isFlipped
        self.tapAnimationStyle = tapAnimationStyle
        self.staticSwapTextMotion = staticSwapTextMotion
        self.contentAlignment = contentAlignment
        self.onTap = onTap
    }

    /// Creates a card renderer directly from question and answer zones.
    init(
        frontZone: ZoneModel,
        backZone: ZoneModel,
        isFlipped: Binding<Bool>,
        tapAnimationStyle: FlashcardTapAnimationStyle,
        staticSwapTextMotion: FlashcardStaticSwapTextMotion = .animated,
        contentAlignment: FlashcardContentAlignment = .center,
        onTap: (() -> Void)? = nil
    ) {
        self.frontZone = frontZone
        self.backZone = backZone
        self._isFlipped = isFlipped
        self.tapAnimationStyle = tapAnimationStyle
        self.staticSwapTextMotion = staticSwapTextMotion
        self.contentAlignment = contentAlignment
        self.onTap = onTap
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
    }

    // MARK: - Card Face Builder

    private var threeDimensionalFlipBody: some View {
        let rotation = isFlipped ? 180.0 : 0.0

        return ZStack {
            cardFace(zone: backZone, marker: .answer, contentHeight: $backContentHeight)
                .modifier(FlipFaceModifier(rotationDegrees: rotation + 180))

            cardFace(zone: frontZone, marker: .question, contentHeight: $frontContentHeight)
                .modifier(FlipFaceModifier(rotationDegrees: rotation))
        }
    }

    private var staticSwapBody: some View {
        Group {
            if staticSwapTextMotion == .animated {
                ZStack {
                    if isFlipped {
                        cardFace(zone: backZone, marker: .answer, contentHeight: $backContentHeight)
                            .id("back-face")
                            .transition(.flashcardStaticSwap)
                    } else {
                        cardFace(zone: frontZone, marker: .question, contentHeight: $frontContentHeight)
                            .id("front-face")
                            .transition(.flashcardStaticSwap)
                    }
                }
            } else if isFlipped {
                cardFace(zone: backZone, marker: .answer, contentHeight: $backContentHeight)
            } else {
                cardFace(zone: frontZone, marker: .question, contentHeight: $frontContentHeight)
            }
        }
    }

    @ViewBuilder
    private func cardFace(
        zone: ZoneModel,
        marker: FaceMarker,
        contentHeight: Binding<CGFloat>
    ) -> some View {
        cardShell(marker: marker) {
            cardFaceContent(zone: zone, contentHeight: contentHeight)
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
    private func cardFaceContent(zone: ZoneModel, contentHeight: Binding<CGFloat>) -> some View {
        adaptiveScrollableContent(zone: zone, contentHeight: contentHeight)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
    }

    private func contentFrameAlignment(
        measuredHeight: CGFloat,
        availableHeight: CGFloat
    ) -> Alignment {
        guard contentAlignment == .center, measuredHeight > 0, measuredHeight <= availableHeight else {
            return .top
        }
        return .center
    }

    @ViewBuilder
    private func measuredFaceContent(
        zone: ZoneModel,
        contentHeight: Binding<CGFloat>
    ) -> some View {
        CardFaceView(
            zone: zone,
            fontScale: playModeTextScale,
            displayTextAlignment: .leading,
            onTap: onTap
        )
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .background(
                GeometryReader { inner in
                    Color.clear.preference(
                        key: ContentHeightKey.self,
                        value: inner.size.height
                    )
                }
            )
            .onPreferenceChange(ContentHeightKey.self) { h in
                if h > 0 { contentHeight.wrappedValue = h }
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
    private func adaptiveScrollableContent(zone: ZoneModel, contentHeight: Binding<CGFloat>) -> some View {
        GeometryReader { available in
            let measured = contentHeight.wrappedValue
            let contentFits = measured > 0 && measured <= available.size.height
            let shouldCenter = contentAlignment == .center && contentFits
            let spacerHeight = shouldCenter
                ? max((available.size.height - measured) / 2, 0)
                : 0

            if zone.hasContent {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        if spacerHeight > 0 {
                            Color.clear.frame(height: spacerHeight)
                        }

                        measuredFaceContent(zone: zone, contentHeight: contentHeight)
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                        if spacerHeight > 0 {
                            Color.clear.frame(height: spacerHeight)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollDisabled(contentFits)
                .onTapGesture {
                    onTap?()
                }
                .frame(width: available.size.width, height: available.size.height)
            } else {
                emptyContent
                    .frame(width: available.size.width, height: available.size.height)
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
            .font(.system(size: isCompact ? 16 : 18, weight: .black, design: .rounded))
            .foregroundStyle(marker.tint)
            .frame(width: faceMarkerFrameSize, height: faceMarkerFrameSize)
            .opacity(0.24)
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            .accessibilityHidden(true)
    }

}

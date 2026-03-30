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
/// The view exposes two overflow modes via `CardContentMode` (stored in
/// `@AppStorage`), allowing users to choose between proportional scaling and
/// a scrollable layout without restarting the session.
///
/// ## Performance Notes
/// - 3D flip visibility is gated by the live rotation angle so front/back text
///   never cross-fade through each other mid-flip.
/// - `contentShape(Rectangle())` ensures the full card surface forwards touches
///   to `SwipeableCard`'s underlying UIKit gesture recognisers.
struct FlipCard: View {

    // MARK: - Properties

    /// Decoded content for the question face.
    private let frontZone: ZoneModel

    /// Decoded content for the answer face.
    private let backZone: ZoneModel

    /// Controls which face is currently visible.
    ///
    /// `false` = front (question), `true` = back (answer).
    @Binding var isFlipped: Bool
    private let swipeFeedback: SwipeCardFeedbackState
    private let tapAnimationStyle: FlashcardTapAnimationStyle
    private let staticSwapTextMotion: FlashcardStaticSwapTextMotion
    private let onTap: (() -> Void)?

    // MARK: - Environment

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - AppStorage

    /// Reads the user's chosen overflow mode from `UserDefaults`.
    ///
    /// Reacts automatically when the user changes the setting in Settings,
    /// without requiring the session to be restarted.
    @AppStorage(CardContentMode.storageKey)
    private var rawContentMode: String = CardContentMode.scaleToFit.rawValue

    // MARK: - State

    /// Measured natural height of the front face content.
    @State private var frontContentHeight: CGFloat = 0

    /// Measured natural height of the back face content.
    @State private var backContentHeight: CGFloat = 0

    // MARK: - Convenience

    private var contentMode: CardContentMode {
        CardContentMode(rawValue: rawContentMode) ?? .scaleToFit
    }

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var cardCornerRadius: CGFloat { isCompact ? 24 : 32 }
    private var hPad: CGFloat { isCompact ? 20 : 28 }
    private var vPad: CGFloat { isCompact ? 20 : 24 }

    // MARK: - Init

    /// Creates a card renderer from a playback snapshot.
    init(
        card: PlayableCard,
        isFlipped: Binding<Bool>,
        swipeFeedback: SwipeCardFeedbackState,
        tapAnimationStyle: FlashcardTapAnimationStyle,
        staticSwapTextMotion: FlashcardStaticSwapTextMotion = .animated,
        onTap: (() -> Void)? = nil
    ) {
        self.frontZone = card.frontZone
        self.backZone = card.backZone
        self._isFlipped = isFlipped
        self.swipeFeedback = swipeFeedback
        self.tapAnimationStyle = tapAnimationStyle
        self.staticSwapTextMotion = staticSwapTextMotion
        self.onTap = onTap
    }

    /// Creates a card renderer directly from question and answer zones.
    init(
        frontZone: ZoneModel,
        backZone: ZoneModel,
        isFlipped: Binding<Bool>,
        swipeFeedback: SwipeCardFeedbackState,
        tapAnimationStyle: FlashcardTapAnimationStyle,
        staticSwapTextMotion: FlashcardStaticSwapTextMotion = .animated,
        onTap: (() -> Void)? = nil
    ) {
        self.frontZone = frontZone
        self.backZone = backZone
        self._isFlipped = isFlipped
        self.swipeFeedback = swipeFeedback
        self.tapAnimationStyle = tapAnimationStyle
        self.staticSwapTextMotion = staticSwapTextMotion
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
            cardFace(zone: backZone, contentHeight: $backContentHeight)
                .modifier(FlipFaceModifier(rotationDegrees: rotation + 180))

            cardFace(zone: frontZone, contentHeight: $frontContentHeight)
                .modifier(FlipFaceModifier(rotationDegrees: rotation))
        }
    }

    private var staticSwapBody: some View {
        cardShell {
            if staticSwapTextMotion == .animated {
                ZStack {
                    if isFlipped {
                        cardFaceContent(zone: backZone, contentHeight: $backContentHeight)
                            .id("back-face")
                            .transition(.flashcardStaticSwap)
                    } else {
                        cardFaceContent(zone: frontZone, contentHeight: $frontContentHeight)
                            .id("front-face")
                            .transition(.flashcardStaticSwap)
                    }
                }
            } else if isFlipped {
                cardFaceContent(zone: backZone, contentHeight: $backContentHeight)
            } else {
                cardFaceContent(zone: frontZone, contentHeight: $frontContentHeight)
            }
        }
    }

    @ViewBuilder
    private func cardFace(zone: ZoneModel, contentHeight: Binding<CGFloat>) -> some View {
        cardShell {
            cardFaceContent(zone: zone, contentHeight: contentHeight)
        }
    }

    @ViewBuilder
    private func cardShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            content()
        }
        .flashcardStyle(
            cornerRadius: cardCornerRadius,
            shadowRadius: isCompact ? 16 : 24,
            borderFeedbackColor: cardFeedbackBorderColor,
            borderFeedbackProgress: cardFeedbackProgress,
            borderFeedbackBlurRadius: cardFeedbackBorderRadius
        )
    }

    @ViewBuilder
    private func cardFaceContent(zone: ZoneModel, contentHeight: Binding<CGFloat>) -> some View {
        Group {
            if contentMode == .scrollable {
                scrollableContent(zone: zone, contentHeight: contentHeight)
            } else {
                scaledContent(zone: zone, contentHeight: contentHeight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
    }

    private var cardFeedbackBorderColor: Color? {
        guard let direction = swipeFeedback.direction else { return nil }

        let baseColor: Color = switch direction {
        case .left:
            Color(red: 1.0, green: 0.10, blue: 0.20)
        case .right:
            Color(red: 0.10, green: 1.0, blue: 0.30)
        }

        return baseColor
    }

    private var cardFeedbackProgress: CGFloat {
        guard swipeFeedback.direction != nil else { return 0 }

        let normalizedIntensity = min(max(((swipeFeedback.intensity - 0.08) / 0.92) * 1.3, 0), 1)
        return pow(normalizedIntensity, 1.65)
    }

    private var cardFeedbackBorderRadius: CGFloat {
        guard swipeFeedback.direction != nil else { return 0 }

        return 1.6 + cardFeedbackProgress * 5.4
    }

    // MARK: - Scale Mode

    /// Measures natural content height and shrinks it proportionally so
    /// everything is always visible without any scrolling.
    ///
    /// No `ScrollView` is used here, so there is no UIKit gesture recogniser
    /// competing with `SwipeableCard`'s pan and tap recognisers.
    @ViewBuilder
    private func scaledContent(zone: ZoneModel, contentHeight: Binding<CGFloat>) -> some View {
        GeometryReader { available in
            let availableH = available.size.height - vPad * 2
            let measured   = contentHeight.wrappedValue
            let scale: CGFloat = measured > 0 && measured > availableH
                ? max(availableH / measured, 0.5)
                : 1.0

            if zone.hasContent {
                CardFaceView(zone: zone, onTap: onTap)
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
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: available.size.width, alignment: .top)
            } else {
                emptyContent
                    .frame(width: available.size.width, height: available.size.height)
            }
        }
    }

    // MARK: - Scroll Mode

    /// Enables vertical scrolling when card content overflows the available height.
    ///
    /// ## Gesture Interaction Design
    ///
    /// 1. **Overflow detection** — content height is measured via `ContentHeightKey`
    ///    and compared to the available card height. `scrollDisabled(true)` is
    ///    applied when content fits, making the `ScrollView` transparent to all
    ///    gestures so taps and horizontal pans reach `SwipeableCard` unobstructed.
    ///
    /// 2. **When scroll is active** (content overflows) — `UIScrollView` only
    ///    intercepts vertical pans. Horizontal pans pass through to `SwipeableCard`'s
    ///    `UIPanGestureRecognizer` because its `gestureRecognizerShouldBegin` approves
    ///    only gestures with dominant horizontal velocity.
    ///
    /// 3. **Tap for flip when scroll is active** — `SwipeableCard`'s
    ///    `UITapGestureRecognizer` sits below the `ScrollView` layer and is blocked.
    ///    An `.onTapGesture` is added directly here to toggle `isFlipped` via
    ///    its `@Binding`. In non-scroll (or scroll-disabled) state this tap handler
    ///    is never reached because `SwipeableCard`'s recogniser fires first.
    @ViewBuilder
    private func scrollableContent(zone: ZoneModel, contentHeight: Binding<CGFloat>) -> some View {
        GeometryReader { available in
            let availableH  = available.size.height - vPad * 2
            let measured    = contentHeight.wrappedValue
            let needsScroll = measured > availableH && measured > 0

            if zone.hasContent {
                ScrollView(.vertical, showsIndicators: needsScroll) {
                    CardFaceView(zone: zone, onTap: onTap)
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
                .scrollIndicators(.hidden)
                // Disable scrolling when content fits so drag gestures pass through
                // to SwipeableCard's UIKit recognisers unobstructed.
                .scrollDisabled(!needsScroll)
                // Tap is handled here because a disabled ScrollView is transparent
                // to drag gestures but still blocks taps from reaching
                // SwipeableCard's UITapGestureRecognizer beneath it.
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

}

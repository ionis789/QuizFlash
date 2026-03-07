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

// MARK: - FlipCard

/// Renders the question and answer faces of a `PlayableCard` with a 3D Y-axis
/// flip animation controlled by the `isFlipped` binding.
///
/// The view exposes two overflow modes via `CardContentMode` (stored in
/// `@AppStorage`), allowing users to choose between proportional scaling and
/// a scrollable layout without restarting the session.
///
/// ## Performance Notes
/// - `rotation3DEffect` uses opacity gating (`.opacity(isFlipped ? 1 : 0)`) to
///   avoid rendering both faces simultaneously on the GPU.
/// - `contentShape(Rectangle())` ensures the full card surface forwards touches
///   to `SwipeableCard`'s underlying UIKit gesture recognisers.
struct FlipCard: View {

    // MARK: - Properties

    /// The card snapshot to display.
    let card: PlayableCard

    /// Controls which face is currently visible.
    ///
    /// `false` = front (question), `true` = back (answer).
    @Binding var isFlipped: Bool

    // MARK: - Environment

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

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

    // MARK: - Body

    var body: some View {
        ZStack {
            // Back face (answer) — rotated into view when isFlipped == true.
            cardFace(zone: card.backZone, contentHeight: $backContentHeight)
                .rotation3DEffect(.degrees(isFlipped ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)

            // Front face (question) — starts at 0° rotation, flips away.
            cardFace(zone: card.frontZone, contentHeight: $frontContentHeight)
                .rotation3DEffect(.degrees(isFlipped ? -180 : 0), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 0 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Full-surface hit testing so SwipeableCard gestures fire everywhere.
        .contentShape(Rectangle())
    }

    // MARK: - Card Face Builder

    @ViewBuilder
    private func cardFace(zone: ZoneModel, contentHeight: Binding<CGFloat>) -> some View {
        ZStack {
            // Card background
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(cardBackground)
                .shadow(color: shadowColor, radius: isCompact ? 16 : 24, y: 8)

            // Inner glow border — two layers produce a warm soft-edge effect.
            // A tight crisp rim sits in front of a wider blurred halo, creating
            // the "warm inner light" look without any harsh visible edge.
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.55), lineWidth: 1)
                .blur(radius: 2)
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))

            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.30), lineWidth: 1)
                .blur(radius: 1)

            // Content area — switches between user-selected overflow modes.
            Group {
                if contentMode == .scrollable {
                    scrollableContent(zone: zone, contentHeight: contentHeight)
                } else {
                    scaledContent(zone: zone, contentHeight: contentHeight)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        }
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
                CardFaceView(zone: zone)
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
                    CardFaceView(zone: zone)
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
                    withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 0.85)) {
                        isFlipped.toggle()
                    }
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

    // MARK: - Styling

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
            : AnyShapeStyle(Color.white)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.12)
    }
}

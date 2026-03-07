//
//  FlipCard.swift
//  QuizFlash
//

import SwiftUI

// MARK: - Content Height Measurement

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - FlipCard

struct FlipCard: View {
    let card: PlayableCard
    @Binding var isFlipped: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    /// Reads the user's chosen overflow mode from UserDefaults.
    /// Reacts automatically when the user changes the setting in Settings.
    @AppStorage(CardContentMode.storageKey)
    private var rawContentMode: String = CardContentMode.scaleToFit.rawValue

    private var contentMode: CardContentMode {
        CardContentMode(rawValue: rawContentMode) ?? .scaleToFit
    }

    @State private var frontContentHeight: CGFloat = 0
    @State private var backContentHeight: CGFloat = 0

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var cardCornerRadius: CGFloat { isCompact ? 24 : 32 }
    private var hPad: CGFloat { isCompact ? 20 : 28 }
    private var vPad: CGFloat { isCompact ? 20 : 24 }

    var body: some View {
        ZStack {
            cardFace(zone: card.backZone, contentHeight: $backContentHeight)
                .rotation3DEffect(.degrees(isFlipped ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)

            cardFace(zone: card.frontZone, contentHeight: $frontContentHeight)
                .rotation3DEffect(.degrees(isFlipped ? -180 : 0), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 0 : 1)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Full-surface hit testing so SwipeableCard gestures fire everywhere.
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func cardFace(zone: ZoneModel, contentHeight: Binding<CGFloat>) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(cardBackground)
                .shadow(color: shadowColor, radius: isCompact ? 16 : 24, y: 8)

            // Soft inner glow border: a blurred stroke clipped to the card
            // shape so the glow bleeds inward only, never outside the card.
            // Two layers — a tight crisp rim + a wider soft halo behind it —
            // produce the "warm inner light" look without any harsh edge.
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.55), lineWidth: 1)
                .blur(radius: 2)
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))

            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.30), lineWidth: 1)
                .blur(radius: 1)

            // Content area — switches between user-selected overflow modes.
            // Scale mode: no ScrollView, avoids UIKit gesture conflict with SwipeableCard.
            // Scroll mode: ScrollView disabled when content fits (no gesture conflict),
            //              enabled only when content overflows the card bounds.
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
    //
    // Measures natural content height and shrinks it proportionally so
    // everything is always visible without any scrolling.
    // No ScrollView → no UIKit gesture recogniser competing with SwipeableCard.

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
    //
    // KEY DESIGN:
    //
    // 1. Overflow detection — content height is measured via PreferenceKey
    //    and compared to the available card height. `scrollDisabled(true)` is
    //    applied when content fits. A disabled ScrollView is transparent to
    //    all gestures — tap (flip) and horizontal pan (swipe) reach
    //    SwipeableCard's UIKit recognisers exactly as in scale mode.
    //
    // 2. When scroll IS active (overflow) — UIScrollView only intercepts
    //    vertical pans. Horizontal pans pass through to SwipeableCard's
    //    UIPanGestureRecognizer naturally because its `gestureRecognizerShouldBegin`
    //    approves gestures with dominant horizontal velocity.
    //
    // 3. Tap for flip when scroll is active — SwipeableCard's UITapGestureRecognizer
    //    sits below the ScrollView layer and is blocked. We add `.onTapGesture`
    //    directly here, toggling `isFlipped` which is already a @Binding.
    //    In non-scroll or scroll-disabled state this tap handler is never
    //    reached because SwipeableCard's recogniser fires first.

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
                // When content fits, disable scroll so gestures pass through
                // to SwipeableCard's UIKit recognisers unobstructed.
                .scrollDisabled(!needsScroll)
                // Tap is always handled here — a disabled ScrollView is
                // transparent to drag gestures but still blocks taps from
                // reaching SwipeableCard's UITapGestureRecognizer beneath it.
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

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
        : AnyShapeStyle(Color.white)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.12)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
    }
}

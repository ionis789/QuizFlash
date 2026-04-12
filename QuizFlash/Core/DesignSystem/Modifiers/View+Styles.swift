//
//  View+Styles.swift
//  QuizFlash
//
//  Shared surface treatments for flashcard and widget surfaces.
//

import SwiftUI

// MARK: - Shared Motion Presets

extension Animation {
    /// Shared spring used when bottom chrome swaps between the custom tab bar and selection bars.
    static var bottomChromeSpring: Animation {
        .spring(response: 0.36, dampingFraction: 0.92)
    }

    /// Shared spring used by circular selection and accent-tracking motion.
    ///
    /// Use this when the effect should feel like the app's circular control
    /// family: stable, soft, and slightly elastic without overshooting hard.
    static var circularSelectionSpring: Animation {
        .spring(response: 0.34, dampingFraction: 0.84)
    }

    /// Shared spring used by circular progress and ring-style reveal motion.
    static var circularProgressSpring: Animation {
        .spring(response: 0.9, dampingFraction: 0.84)
    }

    /// Shared spring used for compact selection-toolbar state changes.
    static var selectionToolbarSpring: Animation {
        .spring(response: 0.3, dampingFraction: 0.9)
    }

    /// Shared spring used by tab-item emphasis inside the floating tab bar.
    static var tabItemSpring: Animation {
        .spring(response: 0.32, dampingFraction: 0.9)
    }

    /// Shared animation used while a context-menu source compresses under the finger.
    static var contextMenuPressIn: Animation {
        .timingCurve(0.42, 0.0, 0.20, 1.0, duration: 0.22)
    }

    /// Shared animation used when a pending press is released before opening the menu.
    static var contextMenuPressOut: Animation {
        .easeOut(duration: 0.08)
    }

    /// Shared spring used for the initial preview lift.
    static var contextMenuLiftSpring: Animation {
        .circularProgressSpring.speed(4.3)
    }

    /// Shared spring used while the pressed source scales back to its final size.
    static var contextMenuPreviewScaleBackSpring: Animation {
        .circularProgressSpring.speed(2.8)
    }

    /// Shared spring used when the lifted preview settles into place.
    static var contextMenuSettleSpring: Animation {
        .circularProgressSpring.speed(3.9)
    }

    /// Shared spring used when the preview has to travel vertically to fit the menu.
    static var contextMenuPreviewPushSpring: Animation {
        .circularProgressSpring.speed(3.3)
    }

    /// Shared spring used while dismissing the custom context menu.
    static var contextMenuDismissSpring: Animation {
        .circularProgressSpring.speed(4.0)
    }

    /// Shared spring used by the context-menu card and row cascade.
    static var contextMenuMenuSpring: Animation {
        .circularProgressSpring.speed(4.0)
    }

    /// Shared spring used when the main context-menu card pops in under the source preview.
    static var contextMenuMenuPopSpring: Animation {
        .circularProgressSpring.speed(3.6)
    }
}

/// Wraps bottom-chrome state swaps in the shared animation transaction.
@MainActor
func withBottomChromeAnimation(_ updates: () -> Void) {
    withAnimation(.bottomChromeSpring, updates)
}

extension AnyTransition {
    /// Standard insertion/removal transition for floating bottom chrome.
    static var bottomChrome: AnyTransition {
        .move(edge: .bottom)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.96, anchor: .bottom))
    }
}

// MARK: - FlashcardSurfaceRole

/// Semantic surface roles supported by the shared flashcard/widget chrome modifier.
enum FlashcardSurfaceRole {
    case card
    case widget
}

// MARK: - FlashcardSurfaceModifier

/// Applies the shared surface chrome used by flashcards and widget-like cards.
private struct FlashcardSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let surfaceRole: FlashcardSurfaceRole
    let baseBorderBlurRadius: CGFloat?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape
                    .fill(surfaceBackground)
                    .shadow(color: shadowColor, radius: shadowRadius, y: shadowYOffset)
            }
            .overlay {
                if surfaceRole == .card {
                    dynamicCardBorder(shape: shape)
                } else {
                    basePrimaryBorder(shape: shape)
                }
            }
            .overlay {
                if surfaceRole == .widget {
                    baseSecondaryBorder(shape: shape)
                }
            }
            .clipShape(shape)
    }

    private var surfaceBackground: AnyShapeStyle {
        switch surfaceRole {
        case .card:
            AnyShapeStyle(
                colorScheme == .dark
                    ? Color(uiColor: .secondarySystemBackground)
                    : Color.white
            )
        case .widget:
            AnyShapeStyle(
                Color.libraryDeckRow
                    .shadow(.inner(color: Color.white.opacity(colorScheme == .dark ? 0.12 : 0.18), radius: 1, x: 0, y: 0))
            )
        }
    }

    private var shadowColor: Color {
        switch surfaceRole {
        case .card:
            colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.12)
        case .widget:
            Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08)
        }
    }

    private var shadowYOffset: CGFloat {
        shadowRadius > 0 ? 8 : 0
    }

    private var basePrimaryBorderColor: Color {
        Color.white.opacity(colorScheme == .dark ? 0.18 : 0.55)
    }

    private var baseSecondaryBorderColor: Color {
        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.30)
    }

    private var resolvedBaseBorderBlurRadius: CGFloat {
        max(0, baseBorderBlurRadius ?? defaultBaseBorderBlurRadius)
    }

    private var defaultBaseBorderBlurRadius: CGFloat {
        switch surfaceRole {
        case .card:
            2
        case .widget:
            1
        }
    }

    private var primaryBorderLineWidth: CGFloat {
        1 + min(resolvedBaseBorderBlurRadius * 0.08, 0.9)
    }

    private var secondaryBorderLineWidth: CGFloat {
        1 + min(resolvedBaseBorderBlurRadius * 0.04, 0.5)
    }

    private var secondaryBorderBlurRadius: CGFloat {
        resolvedBaseBorderBlurRadius * 0.58
    }

    private var resolvedFeedbackIntensity: CGFloat {
        0
    }

    private var cardBorderColor: Color {
        Color.white.opacity(colorScheme == .dark ? 0.24 : 0.62)
    }

    private var resolvedCardBorderLineWidth: CGFloat {
        1.08 + min(resolvedBaseBorderBlurRadius * 0.16, 0.65)
    }

    private var resolvedCardBorderBlurRadius: CGFloat {
        resolvedBaseBorderBlurRadius
    }

    private func basePrimaryBorder(shape: RoundedRectangle) -> some View {
        shape
            .stroke(basePrimaryBorderColor, lineWidth: primaryBorderLineWidth)
            .blur(radius: resolvedBaseBorderBlurRadius)
            .clipShape(shape)
    }

    private func baseSecondaryBorder(shape: RoundedRectangle) -> some View {
        shape
            .stroke(baseSecondaryBorderColor, lineWidth: secondaryBorderLineWidth)
            .blur(radius: secondaryBorderBlurRadius)
    }

    private func dynamicCardBorder(shape: RoundedRectangle) -> some View {
        shape
            .stroke(
                cardBorderColor,
                lineWidth: resolvedCardBorderLineWidth
            )
            .blur(radius: resolvedCardBorderBlurRadius)
            .clipShape(shape)
    }
}

// MARK: - TopNavigationChromeModifier

/// Applies the shared top-bar inset used by Deck, Create, and Library chrome.
private struct TopNavigationChromeModifier: ViewModifier {
    let horizontalInset: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalInset)
            .padding(.top, UIConstants.Layout.deckNavigationTopPadding)
    }
}

// MARK: - StatusTextMotionModifier

/// Applies the shared springy numeric text transition used by live status and counter labels.
private struct StatusTextMotionModifier<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger

    func body(content: Content) -> some View {
        content
            .contentTransition(.numericText())
            .animation(.selectionToolbarSpring, value: trigger)
    }
}

// MARK: - BottomChromeVisibilityModifier

/// Applies the shared show/hide treatment for the floating tab bar and other persistent bottom chrome.
private struct BottomChromeVisibilityModifier: ViewModifier {
    let isVisible: Bool
    let hiddenOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : hiddenOffset)
            .scaleEffect(isVisible ? 1 : 0.98, anchor: .bottom)
            .allowsHitTesting(isVisible)
            .animation(.bottomChromeSpring, value: isVisible)
    }
}

private struct AppScreenBackgroundModifier: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager

    let style: AppScreenBackgroundStyle

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(themeManager.backgroundColor(for: style).ignoresSafeArea())
    }
}

// MARK: - View Extensions

extension View {
    /// Applies the shared flashcard/widget chrome.
    func flashcardStyle(
        cornerRadius: CGFloat = 40,
        shadowRadius: CGFloat = 0,
        surfaceRole: FlashcardSurfaceRole = .card,
        baseBorderBlurRadius: CGFloat? = nil
    ) -> some View {
        modifier(
            FlashcardSurfaceModifier(
                cornerRadius: cornerRadius,
                shadowRadius: shadowRadius,
                surfaceRole: surfaceRole,
                baseBorderBlurRadius: baseBorderBlurRadius
            )
        )
    }

    /// Applies the standard top chrome positioning shared by navigation surfaces.
    func topNavigationChrome(horizontalInset: CGFloat = UIConstants.Layout.compactScreenEdgeInset) -> some View {
        modifier(TopNavigationChromeModifier(horizontalInset: horizontalInset))
    }

    /// Applies the shared animated status-label treatment for counters and short live state text.
    func statusTextMotion<Trigger: Equatable>(trigger: Trigger) -> some View {
        modifier(StatusTextMotionModifier(trigger: trigger))
    }

    /// Applies the standard visibility motion used when bottom chrome appears or yields to selection bars.
    func bottomChromeVisibility(_ isVisible: Bool, hiddenOffset: CGFloat = 80) -> some View {
        modifier(BottomChromeVisibilityModifier(isVisible: isVisible, hiddenOffset: hiddenOffset))
    }

    /// Applies the app-level screen background so root surfaces do not fall back to UIKit system greys during resize.
    func appScreenBackground(_ style: AppScreenBackgroundStyle = .primary) -> some View {
        modifier(AppScreenBackgroundModifier(style: style))
    }
}

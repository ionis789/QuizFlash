//
//  View+Styles.swift
//  QuizFlash
//
//  Shared surface treatments for tappable glass chrome and static widget cards.
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
        .spring(response: 0.18, dampingFraction: 0.96)
    }

    /// Shared spring used while the pressed source scales back to its final size.
    static var contextMenuPreviewScaleBackSpring: Animation {
        .spring(response: 0.28, dampingFraction: 0.92)
    }

    /// Shared spring used when the lifted preview settles into place.
    static var contextMenuSettleSpring: Animation {
        .spring(response: 0.20, dampingFraction: 0.82)
    }

    /// Shared spring used when the preview has to travel vertically to fit the menu.
    static var contextMenuPreviewPushSpring: Animation {
        .spring(response: 0.24, dampingFraction: 0.76)
    }

    /// Shared spring used while dismissing the custom context menu.
    static var contextMenuDismissSpring: Animation {
        .spring(response: 0.18, dampingFraction: 0.98)
    }

    /// Shared spring used by the context-menu card and row cascade.
    static var contextMenuMenuSpring: Animation {
        .spring(response: 0.20, dampingFraction: 0.82)
    }

    /// Shared spring used when the main context-menu card pops in under the source preview.
    static var contextMenuMenuPopSpring: Animation {
        .spring(response: 0.24, dampingFraction: 0.74)
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

// MARK: - DesignShape

/// Semantic shape options used by the shared glass chrome modifier.
enum DesignShape {
    case circle
    case capsule

    fileprivate var anyShape: AnyShape {
        switch self {
        case .circle:
            AnyShape(Circle())
        case .capsule:
            AnyShape(Capsule())
        }
    }
}

// MARK: - GlassButtonModifier

/// Applies the shared glass background used by floating action chrome and capsules.
private struct GlassButtonModifier<BackgroundShape: Shape, BorderShape: Shape>: ViewModifier {
    let shape: BackgroundShape
    let borderShape: BorderShape

    func body(content: Content) -> some View {
        content.background {
            shape
                .fill(.ultraThinMaterial)
                .overlay {
                    borderShape
                        .fill(Color.white.opacity(0.35))
                        .blur(radius: 10)
                        .mask(borderShape.stroke(lineWidth: 4))
                        .blendMode(.overlay)
                }
        }
    }
}

// MARK: - WidgetStyleModifier

/// Applies the shared static card treatment used by deck rows, stats widgets, and info cards.
private struct WidgetStyleModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape
                    .fill(
                        Color.libraryDeckRow
                            .shadow(.inner(color: Color.white.opacity(0.15), radius: 1, x: 0, y: 0))
                    )
            }
            .clipShape(shape)
    }
}

// MARK: - FlashcardSurfaceModifier

/// Applies the dedicated flashcard chrome used by the play-mode card surface.
private struct FlashcardSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let borderFeedbackColor: Color?
    let borderFeedbackProgress: CGFloat
    let borderFeedbackBlurRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let opacityProgress = pow(borderFeedbackProgress, 1.2)

        content
            .background {
                shape
                    .fill(cardBackground)
                    .shadow(color: shadowColor, radius: shadowRadius, y: 8)
            }
            .overlay {
                shape
                    .stroke(basePrimaryBorderColor, lineWidth: 1)
                    .blur(radius: 2)
                    .clipShape(shape)
            }
            .overlay {
                shape
                    .stroke(baseSecondaryBorderColor, lineWidth: 1)
                    .blur(radius: 1)
            }
            .overlay {
                if let borderFeedbackColor, borderFeedbackProgress > 0.001 {
                    shape
                        .stroke(
                            borderFeedbackColor.opacity(opacityProgress * 0.82),
                            lineWidth: 1.2
                        )
                        .blur(radius: 2.4 + borderFeedbackBlurRadius)
                        .clipShape(shape)
                }
            }
            .overlay {
                if let borderFeedbackColor, borderFeedbackProgress > 0.001 {
                    shape
                        .stroke(
                            borderFeedbackColor.opacity(opacityProgress * 0.48),
                            lineWidth: 1.1
                        )
                        .blur(radius: 1.3 + borderFeedbackBlurRadius * 0.65)
                        .clipShape(shape)
                }
            }
            .clipShape(shape)
    }

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? Color(uiColor: .secondarySystemBackground)
            : Color.white
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.12)
    }

    private var basePrimaryBorderColor: Color {
        Color.white.opacity(colorScheme == .dark ? 0.18 : 0.55)
    }

    private var baseSecondaryBorderColor: Color {
        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.30)
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
    /// Applies the shared glass chrome used by floating action buttons and animated capsules.
    func glassButton(shape: DesignShape) -> some View {
        modifier(GlassButtonModifier(shape: shape.anyShape, borderShape: shape.anyShape))
    }

    /// Applies the shared glass chrome to any custom shape that needs the same treatment.
    func glassButton<S: Shape>(shape: S) -> some View {
        modifier(GlassButtonModifier(shape: shape, borderShape: shape))
    }

    /// Applies the shared glass chrome to a custom fill shape and a custom border mask.
    func glassButton<S: Shape, B: Shape>(shape: S, borderShape: B) -> some View {
        modifier(GlassButtonModifier(shape: shape, borderShape: borderShape))
    }

    /// Applies the shared static widget card style used by dashboard and deck information surfaces.
    func widgetStyle(cornerRadius: CGFloat = 40) -> some View {
        modifier(WidgetStyleModifier(cornerRadius: cornerRadius))
    }

    /// Applies the dedicated flashcard card chrome with optional swipe-driven border feedback.
    func flashcardStyle(
        cornerRadius: CGFloat,
        shadowRadius: CGFloat,
        borderFeedbackColor: Color? = nil,
        borderFeedbackProgress: CGFloat = 0,
        borderFeedbackBlurRadius: CGFloat = 0
    ) -> some View {
        modifier(
            FlashcardSurfaceModifier(
                cornerRadius: cornerRadius,
                shadowRadius: shadowRadius,
                borderFeedbackColor: borderFeedbackColor,
                borderFeedbackProgress: borderFeedbackProgress,
                borderFeedbackBlurRadius: borderFeedbackBlurRadius
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

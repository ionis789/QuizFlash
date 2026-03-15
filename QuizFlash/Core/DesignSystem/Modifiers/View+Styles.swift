//
//  View+Styles.swift
//  QuizFlash
//
//  Shared surface treatments for tappable glass chrome and static widget cards.
//

import SwiftUI

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
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: trigger)
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

    /// Applies the standard top chrome positioning shared by navigation surfaces.
    func topNavigationChrome(horizontalInset: CGFloat = UIConstants.Layout.compactScreenEdgeInset) -> some View {
        modifier(TopNavigationChromeModifier(horizontalInset: horizontalInset))
    }

    /// Applies the shared animated status-label treatment for counters and short live state text.
    func statusTextMotion<Trigger: Equatable>(trigger: Trigger) -> some View {
        modifier(StatusTextMotionModifier(trigger: trigger))
    }
}

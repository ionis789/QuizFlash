import SwiftUI

// MARK: - Scroll3DDirection

/// The axis direction for the 3D rotation effect applied by ``ScrollProximityModifier``.
public enum Scroll3DDirection {
    /// The bottom of the card rotates towards the viewer (coming out of the screen).
    case forward
    /// The bottom of the card rotates away from the viewer (going into the screen).
    case backward
}

// MARK: - ScrollProximityModifier

/// A view modifier that applies a combined 3D fold, dissolve, and scale-down effect
/// as the view scrolls past a defined trigger distance from the top of the screen.
///
/// Apply via the ``View/scrollProximityEffect(triggerDistanceFromTop:dissolveDistance:minScale:maxBlur:minOpacity:maxRotationX:direction:)``
/// convenience modifier rather than using this type directly.
public struct ScrollProximityModifier: ViewModifier {

    // MARK: - Configuration

    /// The Y coordinate (from the top of the screen) at which the effect begins.
    var triggerDistanceFromTop: CGFloat

    /// The distance over which the full effect is applied, measured upward from `triggerDistanceFromTop`.
    var dissolveDistance: CGFloat

    /// The minimum scale the view reaches at the end of the effect. Values below `1.0` shrink the view.
    var minScale: CGFloat

    /// The maximum blur radius applied at the end of the effect.
    var maxBlur: CGFloat

    /// The minimum opacity the view reaches at the end of the effect.
    var minOpacity: CGFloat

    /// The maximum rotation angle (in degrees) applied around the X axis.
    var maxRotationX: Double

    /// The axis direction of the 3D fold effect.
    var direction: Scroll3DDirection

    private var rotationAxisX: CGFloat {
        switch direction {
        case .forward:
            1.0
        case .backward:
            -1.0
        }
    }

    // MARK: - Body

    public func body(content: Content) -> some View {
        let axisX = rotationAxisX
        content
            .visualEffect { view, proxy in
                let minY = proxy.frame(in: .global).minY
                let distancePastTrigger = triggerDistanceFromTop - minY
                let raw = max(0, min(1, distancePastTrigger / dissolveDistance))

                // Ease-in curve: effect accelerates as the view exits the trigger zone.
                let eased = raw * raw

                return view
                    .rotation3DEffect(
                        .degrees(eased * maxRotationX),
                        axis: (x: axisX, y: 0.0, z: 0.0),
                        anchor: .top,
                        perspective: 0.6
                    )
                    .scaleEffect(1.0 - eased * (1.0 - minScale), anchor: .top)
                    .blur(radius: eased * maxBlur)
                    .opacity(1.0 - eased * (1.0 - minOpacity))
            }
    }
}

// MARK: - View Extension

public extension View {
    /// Applies a 3D fold-and-dissolve exit effect as the view scrolls past a trigger point.
    ///
    /// The effect combines rotation around the X axis, a scale-down, a blur, and an opacity
    /// fade — all driven by the view's distance from the top of the screen.
    ///
    /// - Parameters:
    ///   - triggerDistanceFromTop: Distance from the screen top at which the effect begins. Default `20`.
    ///   - dissolveDistance: Distance over which the full effect plays out. Default `200`.
    ///   - minScale: Minimum scale reached at the end of the effect. Default `1.1`.
    ///   - maxBlur: Maximum blur radius applied at the end of the effect. Default `7.0`.
    ///   - minOpacity: Minimum opacity reached at the end of the effect. Default `0.0`.
    ///   - maxRotationX: Maximum 3D rotation in degrees around the X axis. Default `45.0`.
    ///   - direction: Whether the card folds `.backward` into the screen or `.forward` out of it.
    ///     Defaults to `.backward` (rolling into the screen).
    func scrollProximityEffect(
        triggerDistanceFromTop: CGFloat = 20.0,
        dissolveDistance: CGFloat = 200.0,
        minScale: CGFloat = 1.1,
        maxBlur: CGFloat = 7.0,
        minOpacity: CGFloat = 0.0,
        maxRotationX: Double = 45.0,
        direction: Scroll3DDirection = .backward
    ) -> some View {
        self.modifier(
            ScrollProximityModifier(
                triggerDistanceFromTop: triggerDistanceFromTop,
                dissolveDistance: dissolveDistance,
                minScale: minScale,
                maxBlur: maxBlur,
                minOpacity: minOpacity,
                maxRotationX: maxRotationX,
                direction: direction
            )
        )
    }
}

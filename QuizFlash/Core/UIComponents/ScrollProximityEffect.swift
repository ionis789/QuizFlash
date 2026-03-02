import SwiftUI

/// Direcția în care se va aplica rotația 3D
public enum Scroll3DDirection {
    /// Partea de jos a cardului vine înspre tine (iese din ecran)
    case forward
    /// Partea de jos a cardului se duce în spate (intră în ecran)
    case backward
}

/// Un modificator care aplică un efect 3D de "pliere", dizolvare și micșorare
/// care ÎNCEPE exact la o anumită distanță față de top-ul ecranului.
public struct ScrollProximityModifier: ViewModifier {
    
    var triggerDistanceFromTop: CGFloat
    var dissolveDistance: CGFloat
    var minScale: CGFloat
    var maxBlur: CGFloat
    var minOpacity: CGFloat
    var maxRotationX: Double
    
    /// NOU: Direcția rotației
    var direction: Scroll3DDirection
    
    public func body(content: Content) -> some View {
        content
            .visualEffect { view, proxy in
                let minY = proxy.frame(in: .global).minY
                let distancePastTrigger = triggerDistanceFromTop - minY
                let raw = max(0, min(1, distancePastTrigger / dissolveDistance))
                
                let eased = raw * raw
                
                // Determinăm axa X matematic în funcție de direcția aleasă
                let axisX: CGFloat = direction == .backward ? -1.0 : 1.0
                
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

public extension View {
    /// Aplică un efect de dispariție 3D când elementul dintr-un ScrollView trece de un anumit punct.
    /// - Parameters:
    ///   - triggerDistanceFromTop: Punctul de start al animației (distanța de la top-ul ecranului).
    ///   - dissolveDistance: Distanța pe care se desfășoară efectul în sus.
    ///   - minScale: Cât de mult se micșorează la final (default 0.90).
    ///   - maxBlur: Cât de tare se blurează la final (default 7.0).
    ///   - minOpacity: Opacitatea finală (default 0.0).
    ///   - maxRotationX: Gradul de rotație 3D (default 45 de grade).
    ///   - direction: Direcția în care se pliază cardul (.backward sau .forward).
    func scrollProximityEffect(
        triggerDistanceFromTop: CGFloat = 20.0,
        dissolveDistance: CGFloat = 200.0,
        minScale: CGFloat = 1.1,
        maxBlur: CGFloat = 7.0,
        minOpacity: CGFloat = 0.0,
        maxRotationX: Double = 45.0,
        direction: Scroll3DDirection = .backward // Default este pe spate
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

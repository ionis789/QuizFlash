
import SwiftUI

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // 1. FOLOSIM HACK-UL TĂU AICI
                    // Asta va blura fundalul fără să adauge gri-ul urât
                    TransparentBlurView(removeAllFilteres: false)
                        .blur(radius: 0) // Uneori ajută să forțezi render-ul
                    
                    // 2. TINT-UL CONTROLAT DE TINE
                    // Acum tu decizi exact ce culoare are sticla.
                    // Pentru efectul Dark Mode Telegram:
//                    Color.white.opacity(0.1) // Un negru fin "Ochelari de soare"
                    
                    // 3. VIBRANCY
//                    Color.white.opacity(0.1)
//                        .blendMode(.overlay)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // ... restul codului cu Overlay și Shadow rămâne la fel ...
            .overlay(
                 RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.35),
                                .white.opacity(0.05),
                                .white.opacity(0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 15, x: 0, y: 10)
    }
}



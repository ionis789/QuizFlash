//
//  GlassModifier.swift
//  QuizFlash
//
//  Refactored & Enhanced by Ion Socol
//

import SwiftUI

// MARK: - Enums
enum GlassBorderStyle {
    case spotlight
    case continuous
}

// MARK: - Glass Modifier
struct GlassModifier<S: Shape>: ViewModifier {
    var shape: S
    var style: GlassBorderStyle

    func body(content: Content) -> some View {
        content
            .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
            .background(Color.white.opacity(0.05))
            .clipShape(shape)
            .overlay {
            switch style {
            case .spotlight:
                ZStack {
                    shape.stroke(.white.opacity(0.05), lineWidth: 1)
                    shape.stroke(
                        RadialGradient(
                            colors: [.white.opacity(0.2), .clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 30
                        ),
                        lineWidth: 0.7
                    )
                    shape.stroke(
                        RadialGradient(
                            colors: [.white.opacity(0.2), .clear],
                            center: .bottomTrailing,
                            startRadius: 0,
                            endRadius: 30
                        ),
                        lineWidth: 1
                    )
                }

            case .continuous:
                shape.stroke(
                    LinearGradient(
                        colors: [
                                .white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
        }
            .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
    }
}

// MARK: - True Glow Modifier
struct TrueGlowModifier<S: Shape>: ViewModifier {
    var shape: S
    var color: Color
    var intensity: Double // 0.0 la 1.0
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
        .background {
            shape
                .fill(color)
                .blur(radius: radius)
            .opacity(intensity * 0.4)
            .scaleEffect(1.1)
        }
        .background {
            shape
                .stroke(color, lineWidth: 2)
                .blur(radius: radius / 3)
            .opacity(intensity * 0.8)
        }
        .shadow(color: color.opacity(intensity * 0.5), radius: radius, x: 0, y: 0)
    }
}

// MARK: - View Extensions (Glass & Glow)
extension View {
    func glassEffect(cornerRadius: CGFloat = 30, style: GlassBorderStyle = .spotlight) -> some View {
        modifier(GlassModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), style: style))
    }

    func glassEffect<S: Shape>(shape: S, style: GlassBorderStyle = .spotlight) -> some View {
        modifier(GlassModifier(shape: shape, style: style))
    }

    /// Adds a diffuse glow (neon/bloom) effect.
    /// - Parameters:
    ///   - color: Glow color.
    ///   - radius: Glow spread (default 15).
    ///   - intensity: Glow strength (0.0 - 1.0).
    func glowEffect(
        color: Color,
        radius: CGFloat = 15,
        intensity: Double = 0.8,
        cornerRadius: CGFloat = 30
    ) -> some View {
        self.modifier(TrueGlowModifier(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            color: color,
            intensity: intensity,
            radius: radius
        ))
    }

    /// Glow effect for custom shapes (e.g. Circle, Capsule).
    func glowEffect<S: Shape>(
        shape: S,
        color: Color,
        radius: CGFloat = 15,
        intensity: Double = 0.8
    ) -> some View {
        self.modifier(TrueGlowModifier(
            shape: shape,
            color: color,
            intensity: intensity,
            radius: radius
        ))
    }
}

//
//  GlassModifier.swift
//  QuizFlash
//
//  Created by Ion Socol on 22.01.2026.
//

import SwiftUI

enum GlassBorderStyle {
    case spotlight
    case continuous
}

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

extension View {

    func glassEffect(cornerRadius: CGFloat = 30, style: GlassBorderStyle = .spotlight) -> some View {
        modifier(GlassModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), style: style))
    }

    func glassEffect<S: Shape>(shape: S, style: GlassBorderStyle = .spotlight) -> some View {
        modifier(GlassModifier(shape: shape, style: style))
    }
}

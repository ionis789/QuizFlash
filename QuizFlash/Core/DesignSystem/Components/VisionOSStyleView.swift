//
//  VisionOSStyleView.swift
//  QuizFlash
//
//  Originally by Balaji Venkatesh (14/03/25). Adapted for QuizFlash.
//

import SwiftUI

// MARK: - VisionOSStyleView

/// A generic container that wraps its content in a visionOS-inspired glass-morphism style.
///
/// Applies:
/// - Continuous rounded clipping.
/// - A layered background of thinMaterial stroke, dark fill, and ultraThinMaterial with an inner shadow.
/// - Subtle bilateral drop shadows for depth.
/// - An `onGeometryChange` observer for downstream size tracking.
///
/// Example:
/// ```swift
/// VisionOSStyleView(cornerRadius: 24) {
///     MyContent()
/// }
/// ```
struct VisionOSStyleView<Content: View>: View {

    // MARK: - Configuration

    /// The corner radius applied to the clip shape and background layers. Defaults to `30`.
    var cornerRadius: CGFloat = 30

    /// The content to render inside the glass container.
    @ViewBuilder var content: Content

    // MARK: - State

    /// Tracks the rendered size of the container for external layout calculations.
    @State private var viewSize: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        content
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .background {
                BackgroundView()
            }
            .compositingGroup()
            // Bilateral drop shadows for a floating-card appearance.
            .shadow(color: .black.opacity(0.15), radius: 15, x: 8, y: 8)
            .shadow(color: .black.opacity(0.1), radius: 15, x: -5, y: -5)
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: { newValue in
                viewSize = newValue
            }
    }

    // MARK: - Background

    /// Renders the layered visionOS-style material background.
    @ViewBuilder
    private func BackgroundView() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.thinMaterial, style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round))

            // Tuneable inner shadow colour — currently set to black for a universal look.
            let innerShadowColor: Color = .black

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.black.opacity(0.1))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial.shadow(.inner(color: innerShadowColor.opacity(0.15), radius: 10)))
        }
        .compositingGroup()
        .environment(\.colorScheme, .light)
    }
}

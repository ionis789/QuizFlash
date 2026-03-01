//
//  VisionOSStyleView.swift
//  VisionOSMenuBar
//
//  Created by Balaji Venkatesh on 14/03/25.
//

import SwiftUI

struct VisionOSStyleView<Content: View>: View {
    var cornerRadius: CGFloat = 30
    @ViewBuilder var content: Content
    /// View Properties
    @State private var viewSize: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        content
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .background {
                BackgroundView()
            }
            .compositingGroup()
            /// Shadows (Optional)
            .shadow(color: .black.opacity(0.15), radius: 15, x: 8, y: 8)
            .shadow(color: .black.opacity(0.1), radius: 15, x: -5, y: -5)
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: { newValue in
                viewSize = newValue
            }
    }
    
    /// VisionOS Style Background
    @ViewBuilder
    private func BackgroundView() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.thinMaterial, style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round))
            
            /// Optional Changes
            //let innerShadowColor: Color = colorScheme == .dark ? .white : .black
            //let innerShadowColor: Color = .white
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


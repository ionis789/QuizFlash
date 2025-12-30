//
//  TransparentBlurView.swift
//  QuizFlash
//
//  Created by Ion Socol on 30.12.2025.
//
import SwiftUI
struct TransparentBlurView: UIViewRepresentable {
    var removeAllFilteres: Bool = false
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        DispatchQueue.main.async {
            if let backdropLayer = uiView.layer.sublayers?.first {
                print(backdropLayer.filters)
                if removeAllFilteres {
                    backdropLayer.filters = []
                } else {
                    backdropLayer.filters?.removeAll(where: { filter in
                        let name = String(describing: filter)
//                        return name != "gaussianBlur" && name != "colorSaturate"
                        return name != "gaussianBlur" 
                    })
                }
            }
        }
    }
}

#Preview {
    TransparentBlurView(removeAllFilteres: false)
}

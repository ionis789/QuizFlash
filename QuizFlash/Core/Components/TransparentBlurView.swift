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
                if removeAllFilteres {
                    backdropLayer.filters = []
                } else {
                    backdropLayer.filters?.removeAll(where: { filter in
                        //Options to change: Optional([luminanceCurveMap, colorSaturate, gaussianBlur])
                        let name = String(describing: filter)
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

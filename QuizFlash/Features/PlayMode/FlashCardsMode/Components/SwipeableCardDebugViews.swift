//
//  SwipeableCardDebugViews.swift
//  QuizFlash
//
//  Debug-only UIKit support views for swipeable cards.
//

import SwiftUI
import UIKit

/// Lightweight FPS counter rendered entirely in UIKit.
///
/// Uses no SwiftUI state so it is invisible to SwiftUI's diffing engine
/// and never triggers `updateUIView` on the parent representable.
private struct _FPSBadge: UIViewRepresentable {
    func makeUIView(context: Context) -> _FPSBadgeView { _FPSBadgeView() }
    func updateUIView(_ uiView: _FPSBadgeView, context: Context) {}
}

private final class _FPSBadgeView: UIView {
    private let label = UILabel()
    private var link: CADisplayLink?
    private var count = 0
    private var last: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 10
        layer.masksToBounds = true
        backgroundColor = UIColor.systemGreen.withAlphaComponent(0.85)
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        link = CADisplayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { link?.invalidate() }

    @objc private func tick(_ l: CADisplayLink) {
        if last == 0 { last = l.timestamp; return }
        count += 1
        let dt = l.timestamp - last
        if dt >= 0.5 {
            let fps = Int(Double(count) / dt)
            label.text = "\(fps) fps"
            backgroundColor = fps >= 100
                ? UIColor.systemGreen.withAlphaComponent(0.85)
                : UIColor.systemOrange.withAlphaComponent(0.85)
            count = 0
            last = l.timestamp
        }
    }
}

//
//  UIKitTabBarControl.swift
//  QuizFlash
//
//  UIKit-backed capsule animator used by the SwiftUI custom tab bar.
//

import SwiftUI
import UIKit

/// A `UIViewRepresentable` that animates only the selected tab capsule.
///
/// The surrounding tab-bar layout stays in SwiftUI so the visuals can be
/// restyled there without reworking the UIKit motion layer.
struct UIKitTabBarSelectionAnimator: UIViewRepresentable {
    let offset: CGFloat
    let itemWidth: CGFloat
    let itemHeight: CGFloat
    let isInteracting: Bool
    let fillColor: Color

    func makeUIView(context: Context) -> SelectionAnimatorView {
        SelectionAnimatorView()
    }

    func updateUIView(_ uiView: SelectionAnimatorView, context: Context) {
        uiView.update(
            offset: offset,
            itemWidth: itemWidth,
            itemHeight: itemHeight,
            isInteracting: isInteracting,
            fillColor: UIColor(fillColor)
        )
    }
}

// MARK: - Selection Animator View

final class SelectionAnimatorView: UIView {
    private let fillView = UIView()

    private var didApplyInitialLayout = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        offset: CGFloat,
        itemWidth: CGFloat,
        itemHeight: CGFloat,
        isInteracting: Bool,
        fillColor: UIColor
    ) {
        let frame = alignedCapsuleFrame(offset: offset, itemWidth: itemWidth, itemHeight: itemHeight)

        fillView.layer.cornerRadius = frame.height / 2
        fillView.backgroundColor = fillColor

        if !didApplyInitialLayout {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fillView.frame = frame
            fillView.transform = .identity
            CATransaction.commit()
            didApplyInitialLayout = true
            return
        }

        if isInteracting {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fillView.frame = frame
            CATransaction.commit()
        } else {
            UIView.animate(
                withDuration: UIConstants.Animation.medium,
                delay: 0,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0.45,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.fillView.frame = frame
            }
        }

        UIView.animate(
            withDuration: UIConstants.Animation.instant,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.fillView.transform = .identity
        }
    }

    // MARK: - Setup

    private func configure() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = false

        fillView.isUserInteractionEnabled = false
        fillView.layer.cornerCurve = .continuous
        fillView.clipsToBounds = true
        addSubview(fillView)
    }

    private func alignedCapsuleFrame(offset: CGFloat, itemWidth: CGFloat, itemHeight: CGFloat) -> CGRect {
        let scale = window?.screen.scale ?? UIScreen.main.scale

        func align(_ value: CGFloat) -> CGFloat {
            (value * scale).rounded() / scale
        }

        return CGRect(
            x: align(offset),
            y: 0,
            width: align(itemWidth),
            height: align(itemHeight)
        )
    }
}

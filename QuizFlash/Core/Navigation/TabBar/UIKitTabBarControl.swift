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

    func makeUIView(context: Context) -> SelectionAnimatorView {
        SelectionAnimatorView()
    }

    func updateUIView(_ uiView: SelectionAnimatorView, context: Context) {
        uiView.update(
            offset: offset,
            itemWidth: itemWidth,
            itemHeight: itemHeight,
            isInteracting: isInteracting
        )
    }
}

// MARK: - Selection Animator View

final class SelectionAnimatorView: UIView {
    private let fillView = UIView()
    private let borderView = UIView()

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
        isInteracting: Bool
    ) {
        let frame = alignedCapsuleFrame(offset: offset, itemWidth: itemWidth, itemHeight: itemHeight)

        fillView.layer.cornerRadius = itemHeight / 2
        borderView.layer.cornerRadius = itemHeight / 2

        if !didApplyInitialLayout {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fillView.frame = frame
            borderView.frame = frame
            borderView.alpha = isInteracting ? 1 : 0
            fillView.transform = .identity
            borderView.transform = .identity
            CATransaction.commit()
            didApplyInitialLayout = true
            return
        }

        if isInteracting {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fillView.frame = frame
            borderView.frame = frame
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
                self.borderView.frame = frame
            }
        }

        UIView.animate(
            withDuration: UIConstants.Animation.instant,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.fillView.transform = .identity
            self.borderView.transform = .identity
            self.borderView.alpha = isInteracting ? 1 : 0
        }
    }

    // MARK: - Setup

    private func configure() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = false

        fillView.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        fillView.isUserInteractionEnabled = false
        fillView.layer.cornerCurve = .continuous
        addSubview(fillView)

        borderView.backgroundColor = .clear
        borderView.isUserInteractionEnabled = false
        borderView.layer.cornerCurve = .continuous
        borderView.layer.borderWidth = 1
        borderView.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        borderView.alpha = 0
        addSubview(borderView)
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

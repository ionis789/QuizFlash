//
//  TabBarScrollScaleHost.swift
//  QuizFlash
//
//  Hosts the floating SwiftUI tab bar in UIKit so scroll-driven scale changes
//  can update a view transform without invalidating the root SwiftUI tree.
//

import SwiftUI
import UIKit

@MainActor
final class TabBarScrollScaleController {
    private weak var targetView: UIView?
    private var currentProgress: CGFloat = 0
    private var activeAnimator: UIViewPropertyAnimator?

    func attach(_ view: UIView) {
        targetView = view
        view.backgroundColor = .clear
        view.isOpaque = false
        apply(progress: currentProgress, animated: false)
    }

    func detach(_ view: UIView) {
        guard targetView === view else { return }
        activeAnimator?.stopAnimation(true)
        view.transform = .identity
        targetView = nil
    }

    func setProgress(_ progress: CGFloat, animated: Bool) {
        let clamped = min(max(progress, 0), 1)
        guard abs(clamped - currentProgress) >= UIConstants.Layout.bottomChromeCompactProgressEpsilon
            || (clamped == 0 && currentProgress != 0) else {
            return
        }
        currentProgress = clamped
        apply(progress: clamped, animated: animated)
    }

    func reset(animated: Bool) {
        setProgress(0, animated: animated)
    }

    private func apply(progress: CGFloat, animated: Bool) {
        guard let targetView else { return }

        let scale = 1 - (progress * (1 - UIConstants.Layout.bottomChromeCompactScale))
        let transform = bottomAnchoredScaleTransform(scale: scale, height: targetView.bounds.height)

        activeAnimator?.stopAnimation(true)
        guard animated else {
            targetView.transform = transform
            return
        }

        let animator = UIViewPropertyAnimator(duration: 0.32, dampingRatio: 0.92) {
            targetView.transform = transform
        }
        activeAnimator = animator
        animator.addCompletion { [weak self, weak animator] _ in
            if self?.activeAnimator === animator {
                self?.activeAnimator = nil
            }
        }
        animator.startAnimation()
    }

    private func bottomAnchoredScaleTransform(scale: CGFloat, height: CGFloat) -> CGAffineTransform {
        let bottomCorrection = height * (1 - scale) / 2
        return CGAffineTransform(translationX: 0, y: bottomCorrection)
            .scaledBy(x: scale, y: scale)
    }
}

struct TabBarScrollScaleHost<Content: View>: UIViewControllerRepresentable {
    let scaleController: TabBarScrollScaleController
    let content: Content

    init(
        scaleController: TabBarScrollScaleController,
        @ViewBuilder content: () -> Content
    ) {
        self.scaleController = scaleController
        self.content = content()
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        scaleController.attach(controller.view)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIHostingController<Content>, context: Context) {
        uiViewController.rootView = content
        scaleController.attach(uiViewController.view)
    }

    static func dismantleUIViewController(
        _ uiViewController: UIHostingController<Content>,
        coordinator: ()
    ) {
        // The controller is intentionally not reset here. The next live host will
        // attach and receive the last known progress immediately.
    }
}

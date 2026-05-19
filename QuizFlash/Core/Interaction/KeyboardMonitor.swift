//
//  KeyboardMonitor.swift
//  QuizFlash
//

import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class KeyboardMonitor {
    static let shared = KeyboardMonitor()

    private(set) var isVisible = false
    private(set) var visibleHeight: CGFloat = 0
    private(set) var animationDuration: TimeInterval = 0.25
    private(set) var animationOptions: UIView.AnimationOptions = [.curveEaseInOut]

    private var observers: [NSObjectProtocol] = []

    private init(notificationCenter: NotificationCenter = .default) {
        let names: [NSNotification.Name] = [
            UIResponder.keyboardWillChangeFrameNotification,
            UIResponder.keyboardWillHideNotification,
            UIResponder.keyboardDidHideNotification
        ]

        observers = names.map { name in
            notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let notificationName = notification.name
                let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
                let curveRaw = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int
                Task { @MainActor [weak self] in
                    self?.handle(
                        notificationName: notificationName,
                        endFrame: endFrame,
                        animationDuration: duration,
                        animationCurveRaw: curveRaw
                    )
                }
            }
        }
    }

    private func handle(
        notificationName: NSNotification.Name,
        endFrame: CGRect?,
        animationDuration: TimeInterval?,
        animationCurveRaw: Int?
    ) {
        if let animationDuration {
            self.animationDuration = animationDuration
        }
        if let animationCurveRaw {
            self.animationOptions = UIView.AnimationOptions(rawValue: UInt(animationCurveRaw << 16))
        }

        if notificationName == UIResponder.keyboardWillHideNotification
            || notificationName == UIResponder.keyboardDidHideNotification {
            isVisible = false
            visibleHeight = 0
            return
        }

        guard let endFrame else {
            return
        }
        let window = activeKeyWindow()
        let screenBounds = window?.bounds ?? UIScreen.main.bounds
        let convertedFrame = window?.convert(endFrame, from: nil) ?? endFrame
        let intersection = screenBounds.intersection(convertedFrame)
        let safeBottom = window?.safeAreaInsets.bottom ?? 0
        let height = max(0, intersection.height - safeBottom)

        visibleHeight = height
        isVisible = height > 0
    }

    private func activeKeyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

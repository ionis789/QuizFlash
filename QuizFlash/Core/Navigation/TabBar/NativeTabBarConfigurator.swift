//
//  NativeTabBarConfigurator.swift
//  QuizFlash
//
//  Abstract:
//  Directly controls the native UITabBar instance that UIKit keeps alive beneath
//  SwiftUI's TabView, regardless of what UITabBar.appearance() reports.
//
//  Problem:
//  UITabBar.appearance().isHidden = true hides the bar visually but does NOT:
//    1. Remove it from the safe area calculation → bottom inset persists →
//       LibrarySelectionBarView gets pushed up by ~49 pt (tab bar height).
//    2. Disable its hit-testing → _tabBarItemClicked: fires independently of
//       the SwiftUI tabSelectionBinding → tabs switch even when custom bar
//       is intentionally hidden during selection / search mode.
//
//  Solution:
//  A zero-size UIViewRepresentable inserted into the view hierarchy walks the
//  UIWindow to locate the live UITabBar instance and applies isHidden /
//  isUserInteractionEnabled directly on it. Direct mutation is immediate and
//  affects both layout (safe area recalculates) and touch handling.
//
//  This is the only approach that reliably controls both concerns on iOS 17+.
//

import SwiftUI
import UIKit

// MARK: - NativeTabBarConfigurator

/// A zero-size UIViewRepresentable that finds the live UITabBar in the window
/// hierarchy and keeps it suppressed while the custom bar owns the UI.
struct NativeTabBarConfigurator: UIViewRepresentable {

    /// Mirrors `isTabBarVisible` from MainAppView so updates still flow through
    /// the representable whenever the root chrome changes.
    var isVisible: Bool

    func makeUIView(context: Context) -> ConfiguratorView {
        let view = ConfiguratorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: ConfiguratorView, context: Context) {
        // Walk deferred to next run-loop so the UITabBar is in the hierarchy.
        DispatchQueue.main.async {
            uiView.apply(visible: isVisible)
        }
    }

    // MARK: - ConfiguratorView

    final class ConfiguratorView: UIView {

        func apply(visible _: Bool) {
            guard let tabBar = findTabBar() else { return }

            // The native UITabBar must never receive taps — our custom bar handles
            // all tab selection. Disabling interaction here blocks _tabBarItemClicked:
            // from firing even when the bar is technically in the view hierarchy.
            tabBar.isUserInteractionEnabled = false

            // The native UITabBar stays hidden in both custom-bar states. Showing
            // it when the custom bar is visible lets newer iOS releases render
            // their own adaptive tab-bar material behind our floating chrome.
            if !tabBar.isHidden {
                tabBar.isHidden = true
            }

            // Keep the live bar visually inert if UIKit reuses or reconfigures
            // the instance during a trait-collection or scene transition.
            if tabBar.alpha != 0 {
                tabBar.alpha = 0
            }
        }

        /// Walks the key window's subview tree breadth-first to locate the UITabBar
        /// that UIKit creates internally for SwiftUI's TabView.
        private func findTabBar() -> UITabBar? {
            guard let window = self.window ?? UIApplication.shared
                    .connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow })
            else { return nil }

            return findTabBar(in: window)
        }

        private func findTabBar(in view: UIView) -> UITabBar? {
            if let tabBar = view as? UITabBar { return tabBar }
            for subview in view.subviews {
                if let found = findTabBar(in: subview) { return found }
            }
            return nil
        }
    }
}

// MARK: - View Extension

extension View {
    /// Keeps the native UITabBar suppressed and non-interactive on the live TabView host.
    func configureNativeTabBar(visible: Bool) -> some View {
        background(
            NativeTabBarConfigurator(isVisible: visible)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
    }
}

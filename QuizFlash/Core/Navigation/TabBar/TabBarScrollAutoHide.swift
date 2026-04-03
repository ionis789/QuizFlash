//
//  TabBarScrollAutoHide.swift
//  QuizFlash
//
//  UIKit-backed scroll direction reporting for the floating custom tab bar.
//

import SwiftUI
import UIKit

// MARK: - TabBarAutoHideAction

/// A user-driven visibility intent emitted by scrollable root surfaces.
enum TabBarAutoHideAction: Equatable {
    case show
    case hide
}

// MARK: - Scroll Eligibility

/// Pure helpers used to decide whether a scroll view still has meaningful downward range.
enum TabBarScrollAutoHideEligibility {
    /// Resolves the maximum in-bounds vertical content offset for the observed scroll view.
    static func maximumOffset(
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        adjustedInsets: UIEdgeInsets,
        minOffset: CGFloat
    ) -> CGFloat {
        let contentBottomOffset = contentHeight - viewportHeight + adjustedInsets.bottom
        return max(minOffset, contentBottomOffset)
    }

    /// Returns `true` only while the user can still scroll further downward in-bounds.
    static func canHide(
        offset: CGFloat,
        minOffset: CGFloat,
        maxOffset: CGFloat,
        isUserDriven: Bool,
        bottomTolerance: CGFloat = UIConstants.Layout.bottomChromeAutoHideBottomTolerance
    ) -> Bool {
        guard isUserDriven else { return false }
        guard maxOffset > minOffset + bottomTolerance else { return false }
        return offset < maxOffset - bottomTolerance
    }
}

// MARK: - TabBarScrollAutoHideResolver

/// Resolves raw vertical scroll offsets into stable tab-bar visibility intents.
///
/// The resolver intentionally avoids per-pixel visibility toggles:
/// - scrolling down hides only after a small cumulative threshold
/// - any meaningful upward drag reveals immediately
/// - reaching the top always reveals the bar
struct TabBarScrollAutoHideResolver {
    private enum Direction {
        case up
        case down
    }

    let downwardHideThreshold: CGFloat
    let upwardRevealThreshold: CGFloat
    let topRevealTolerance: CGFloat

    private(set) var isHidden = false
    private var lastOffset: CGFloat?
    private var directionAnchorOffset: CGFloat?
    private var lastDirection: Direction?

    init(
        downwardHideThreshold: CGFloat = UIConstants.Layout.bottomChromeAutoHideDownwardThreshold,
        upwardRevealThreshold: CGFloat = UIConstants.Layout.bottomChromeAutoRevealUpwardThreshold,
        topRevealTolerance: CGFloat = UIConstants.Layout.bottomChromeAutoRevealTopTolerance
    ) {
        self.downwardHideThreshold = downwardHideThreshold
        self.upwardRevealThreshold = upwardRevealThreshold
        self.topRevealTolerance = topRevealTolerance
    }

    /// Resets resolver state and, when needed, requests the bar to become visible again.
    mutating func reset() -> TabBarAutoHideAction? {
        let shouldReveal = isHidden
        isHidden = false
        lastOffset = nil
        directionAnchorOffset = nil
        lastDirection = nil
        return shouldReveal ? .show : nil
    }

    /// Processes a new vertical content offset sampled from the observed UIScrollView.
    mutating func handle(
        offset: CGFloat,
        minOffset: CGFloat,
        canHide: Bool,
        canShow: Bool
    ) -> TabBarAutoHideAction? {
        guard let previousOffset = lastOffset else {
            lastOffset = offset
            directionAnchorOffset = offset
            return nil
        }

        defer { lastOffset = offset }

        if offset <= minOffset + topRevealTolerance {
            directionAnchorOffset = offset
            lastDirection = nil

            guard isHidden else { return nil }
            isHidden = false
            return .show
        }

        let delta = offset - previousOffset
        guard abs(delta) > 0.5 else { return nil }

        let direction: Direction = delta > 0 ? .down : .up
        if lastDirection != direction {
            lastDirection = direction
            directionAnchorOffset = previousOffset
        }

        let anchorOffset = directionAnchorOffset ?? previousOffset

        switch direction {
        case .down:
            guard canHide else { return nil }
            guard !isHidden else { return nil }
            guard offset - anchorOffset >= downwardHideThreshold else { return nil }

            isHidden = true
            directionAnchorOffset = offset
            return .hide

        case .up:
            guard canShow else { return nil }
            guard isHidden else { return nil }
            guard anchorOffset - offset >= upwardRevealThreshold else { return nil }

            isHidden = false
            directionAnchorOffset = offset
            return .show
        }
    }
}

// MARK: - Environment Wiring

private struct TabBarScrollAutoHideActionKey: EnvironmentKey {
    static let defaultValue: (TabBarAutoHideAction) -> Void = { _ in }
}

private struct BottomChromeVisibilityKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var tabBarScrollAutoHideAction: (TabBarAutoHideAction) -> Void {
        get { self[TabBarScrollAutoHideActionKey.self] }
        set { self[TabBarScrollAutoHideActionKey.self] = newValue }
    }

    var bottomChromeIsVisible: Bool {
        get { self[BottomChromeVisibilityKey.self] }
        set { self[BottomChromeVisibilityKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Reports user-driven vertical scroll direction to the shared custom tab bar.
    ///
    /// Attach this to the root vertical `ScrollView` of a screen. The reporter keeps
    /// the tab bar visible by default and only requests hide/show when the underlying
    /// `UIScrollView` receives genuine user-driven motion.
    func tabBarAutoHideOnScroll(enabled: Bool = true) -> some View {
        modifier(TabBarAutoHideOnScrollModifier(isEnabled: enabled))
    }
}

private struct TabBarAutoHideOnScrollModifier: ViewModifier {
    @Environment(\.tabBarScrollAutoHideAction) private var action

    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.overlay {
            TabBarAutoHideScrollProbe(
                isEnabled: isEnabled,
                action: action
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - UIKit Probe

private struct TabBarAutoHideScrollProbe: UIViewRepresentable {
    let isEnabled: Bool
    let action: (TabBarAutoHideAction) -> Void

    func makeUIView(context: Context) -> ProbeView {
        ProbeView(
            isEnabled: isEnabled,
            action: action
        )
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.isEnabled = isEnabled
        uiView.action = action
    }

    final class ProbeView: UIView {
        var isEnabled: Bool {
            didSet {
                guard oldValue != isEnabled else { return }
                handleEnablementChange()
            }
        }

        var action: (TabBarAutoHideAction) -> Void

        private var resolver = TabBarScrollAutoHideResolver()
        private weak var scrollView: UIScrollView?
        private var offsetObservation: NSKeyValueObservation?

        init(
            isEnabled: Bool,
            action: @escaping (TabBarAutoHideAction) -> Void
        ) {
            self.isEnabled = isEnabled
            self.action = action
            super.init(frame: .zero)
            isHidden = true
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            fatalError("Not implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()

            if window != nil {
                if scrollView == nil {
                    attachToScrollView()
                }
            } else {
                tearDownObservation()
                emitIfNeeded(resolver.reset())
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            if window != nil, scrollView == nil {
                attachToScrollView()
            }
        }

        private func handleEnablementChange() {
            if isEnabled {
                if let scrollView {
                    _ = resolver.handle(
                        offset: scrollView.contentOffset.y,
                        minOffset: -scrollView.adjustedContentInset.top,
                        canHide: false,
                        canShow: false
                    )
                }
            } else {
                emitIfNeeded(resolver.reset())
            }
        }

        private func attachToScrollView() {
            guard let scrollView = nearestAncestorScrollView() else { return }
            guard self.scrollView !== scrollView else { return }

            tearDownObservation()
            self.scrollView = scrollView

            _ = resolver.handle(
                offset: scrollView.contentOffset.y,
                minOffset: -scrollView.adjustedContentInset.top,
                canHide: false,
                canShow: false
            )

            offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                self?.handleObservedScroll(scrollView)
            }
        }

        private func handleObservedScroll(_ scrollView: UIScrollView) {
            if !isEnabled {
                emitIfNeeded(resolver.reset())
                return
            }

            let offset = scrollView.contentOffset.y
            let minOffset = -scrollView.adjustedContentInset.top
            let maxOffset = TabBarScrollAutoHideEligibility.maximumOffset(
                contentHeight: scrollView.contentSize.height,
                viewportHeight: scrollView.bounds.height,
                adjustedInsets: scrollView.adjustedContentInset,
                minOffset: minOffset
            )
            let canHide = TabBarScrollAutoHideEligibility.canHide(
                offset: offset,
                minOffset: minOffset,
                maxOffset: maxOffset,
                isUserDriven: scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
            )
            let canShow = scrollView.isTracking || scrollView.isDragging

            emitIfNeeded(
                resolver.handle(
                    offset: offset,
                    minOffset: minOffset,
                    canHide: canHide,
                    canShow: canShow
                )
            )
        }

        private func emitIfNeeded(_ action: TabBarAutoHideAction?) {
            guard let action else { return }
            self.action(action)
        }

        private func tearDownObservation() {
            offsetObservation = nil
            scrollView = nil
        }

        private func nearestAncestorScrollView() -> UIScrollView? {
            var candidate = superview
            while let view = candidate {
                if let scrollView = view as? UIScrollView {
                    return scrollView
                }
                candidate = view.superview
            }
            return nil
        }

        deinit {
            emitIfNeeded(resolver.reset())
        }
    }
}

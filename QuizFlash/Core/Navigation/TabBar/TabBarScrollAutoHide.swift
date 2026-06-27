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
    case setCompactProgress(CGFloat, animated: Bool)
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

    /// Returns `true` only when the scroll view has meaningful vertical range.
    static func canScroll(
        minOffset: CGFloat,
        maxOffset: CGFloat,
        bottomTolerance: CGFloat = UIConstants.Layout.bottomChromeAutoHideBottomTolerance
    ) -> Bool {
        maxOffset > minOffset + bottomTolerance
    }
}

// MARK: - TabBarScrollCompactProgressResolver

/// Resolves raw scroll offsets into a continuous bottom-edge compact progress.
/// Progress is intentionally tied to elastic bottom overscroll instead of scroll direction,
/// so the tab bar only compresses when the user reaches the bottom and keeps pulling.
struct TabBarScrollCompactProgressResolver {
    let compactDistance: CGFloat
    let changeEpsilon: CGFloat

    init(
        compactDistance: CGFloat = UIConstants.Layout.bottomChromeCompactOverscrollDistance,
        changeEpsilon: CGFloat = UIConstants.Layout.bottomChromeCompactProgressEpsilon
    ) {
        self.compactDistance = compactDistance
        self.changeEpsilon = changeEpsilon
    }

    private(set) var progress: CGFloat = 0

    mutating func reset(animated: Bool = true) -> TabBarAutoHideAction? {
        setProgress(0, animated: animated)
    }

    /// Processes a new vertical content offset sampled from the observed `UIScrollView`.
    mutating func handle(
        offset: CGFloat,
        minOffset: CGFloat,
        maxOffset: CGFloat,
        isUserDriven: Bool,
        isDragging: Bool
    ) -> TabBarAutoHideAction? {
        guard isUserDriven,
              TabBarScrollAutoHideEligibility.canScroll(minOffset: minOffset, maxOffset: maxOffset)
        else {
            return reset(animated: true)
        }

        guard isDragging else {
            return reset(animated: true)
        }

        let overscroll = max(0, offset - maxOffset)
        let targetProgress = min(max(overscroll / compactDistance, 0), 1)
        return setProgress(targetProgress, animated: false)
    }

    private mutating func setProgress(_ newValue: CGFloat, animated: Bool) -> TabBarAutoHideAction? {
        let clamped = min(max(newValue, 0), 1)
        let isResettingActiveProgress = clamped == 0 && progress != 0
        let didMeaningfullyChange = abs(clamped - progress) > changeEpsilon
        guard isResettingActiveProgress || didMeaningfullyChange else {
            return nil
        }
        progress = clamped
        return .setCompactProgress(clamped, animated: animated)
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
    /// Reports user-driven bottom overscroll to the shared custom tab bar.
    ///
    /// Attach this to the root vertical `ScrollView` of a screen. The reporter keeps
    /// the tab bar full-size by default and only compacts it while the user is actively
    /// pulling past the bottom edge.
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

        private var resolver = TabBarScrollCompactProgressResolver()
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
                emitIfNeeded(resolver.reset(animated: true))
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
                    emitIfNeeded(resolver.handle(
                        offset: scrollView.contentOffset.y,
                        minOffset: -scrollView.adjustedContentInset.top,
                        maxOffset: currentMaxOffset(for: scrollView),
                        isUserDriven: false,
                        isDragging: false
                    ))
                }
            } else {
                emitIfNeeded(resolver.reset(animated: true))
            }
        }

        private func attachToScrollView() {
            guard let scrollView = nearestAncestorScrollView() else { return }
            guard self.scrollView !== scrollView else { return }

            tearDownObservation()
            self.scrollView = scrollView

            emitIfNeeded(resolver.handle(
                offset: scrollView.contentOffset.y,
                minOffset: -scrollView.adjustedContentInset.top,
                maxOffset: currentMaxOffset(for: scrollView),
                isUserDriven: false,
                isDragging: false
            ))

            offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                self?.handleObservedScroll(scrollView)
            }
        }

        private func handleObservedScroll(_ scrollView: UIScrollView) {
            if !isEnabled {
                emitIfNeeded(resolver.reset(animated: true))
                return
            }

            let offset = scrollView.contentOffset.y
            let minOffset = -scrollView.adjustedContentInset.top
            let maxOffset = currentMaxOffset(for: scrollView)
            let isUserDriven = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
            let isDragging = scrollView.isTracking || scrollView.isDragging
            emitIfNeeded(
                resolver.handle(
                    offset: offset,
                    minOffset: minOffset,
                    maxOffset: maxOffset,
                    isUserDriven: isUserDriven,
                    isDragging: isDragging
                )
            )
        }

        private func currentMaxOffset(for scrollView: UIScrollView) -> CGFloat {
            TabBarScrollAutoHideEligibility.maximumOffset(
                contentHeight: scrollView.contentSize.height,
                viewportHeight: scrollView.bounds.height,
                adjustedInsets: scrollView.adjustedContentInset,
                minOffset: -scrollView.adjustedContentInset.top
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

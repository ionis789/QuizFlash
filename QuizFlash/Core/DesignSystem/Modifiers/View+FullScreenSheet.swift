//
//  View+FullScreenSheet.swift
//  QuizFlash
//

import SwiftUI
import UIKit

// MARK: - Full Screen Sheet Dismiss Action

struct FullScreenSheetDismissAction {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    func callAsFunction() { handler() }
}

// MARK: - Environment Values

private struct FullScreenSheetDismissActionKey: EnvironmentKey {
    static let defaultValue: FullScreenSheetDismissAction? = nil
}

private struct FullScreenSheetDragActivationHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = next }
    }
}

private struct FullScreenSheetDragProgressKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var fullScreenSheetDismiss: FullScreenSheetDismissAction? {
        get { self[FullScreenSheetDismissActionKey.self] }
        set { self[FullScreenSheetDismissActionKey.self] = newValue }
    }

    /// 0 = sheet at rest, 1 = fully off-screen.
    var fullScreenSheetDragProgress: CGFloat {
        get { self[FullScreenSheetDragProgressKey.self] }
        set { self[FullScreenSheetDragProgressKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    @ViewBuilder
    func fullScreenSheet<Content: View, Background: View>(
        ignoresSafeArea: Bool = false,
        isPresented: Binding<Bool>,
        dragDismissActivationHeight: CGFloat? = nil,
        @ViewBuilder content: @escaping (UIEdgeInsets) -> Content,
        @ViewBuilder background: @escaping () -> Background
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            FullScreenSheetContainer(
                ignoresSafeArea: ignoresSafeArea,
                dragDismissActivationHeight: dragDismissActivationHeight,
                content: content,
                background: background
            )
        }
    }

    @ViewBuilder
    func fullScreenSheet<Item: Identifiable, Content: View, Background: View>(
        ignoresSafeArea: Bool = false,
        item: Binding<Item?>,
        dragDismissActivationHeight: CGFloat? = nil,
        @ViewBuilder content: @escaping (Item, UIEdgeInsets) -> Content,
        @ViewBuilder background: @escaping () -> Background
    ) -> some View {
        fullScreenCover(item: item) { wrappedItem in
            FullScreenSheetContainer(
                ignoresSafeArea: ignoresSafeArea,
                dragDismissActivationHeight: dragDismissActivationHeight,
                content: { insets in content(wrappedItem, insets) },
                background: background
            )
        }
    }

    func fullScreenSheetDragActivationHeight(_ height: CGFloat?) -> some View {
        preference(key: FullScreenSheetDragActivationHeightPreferenceKey.self, value: height)
    }
}

// MARK: - Full Screen Sheet Container

private struct FullScreenSheetContainer<Content: View, Background: View>: View {
    let ignoresSafeArea: Bool
    let dragDismissActivationHeight: CGFloat?
    @ViewBuilder var content: (UIEdgeInsets) -> Content
    @ViewBuilder var background: Background

    @Environment(\.dismiss) private var dismiss

    @State private var offset: CGFloat = 0
    @State private var scrollDisabled = false
    @State private var isAnimatingDismiss = false
    @State private var preferredDragActivationHeight: CGFloat? = nil

    private var dismissalAnimation: Animation {
        .snappy(duration: UIConstants.Animation.medium, extraBounce: 0)
    }

    private var dragProgress: CGFloat {
        min(max(offset / max(windowSize.height, 1), 0), 1)
    }

    private var activeSheetCornerRadius: CGFloat {
        guard offset > 0 else { return 0 }
        return UIConstants.isPad ? 32 : 28
    }

    var body: some View {
        let sheetShape = UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: activeSheetCornerRadius,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: activeSheetCornerRadius
            ),
            style: .continuous
        )

        let baseView = ZStack {
            // Background only is clipped — content frame never changes so
            // text/cards never reflow during drag. Shadow removed entirely.
            background
                .environment(\.fullScreenSheetDragProgress, dragProgress)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(sheetShape)

            content(safeAreaInsets)
                .scrollDisabled(scrollDisabled)
        }
        .geometryGroup()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .offset(y: offset)
        .presentationBackground { Color.clear }
        .ignoresSafeArea(.container, edges: ignoresSafeArea ? .all : [])
        .environment(\.fullScreenSheetDismiss, FullScreenSheetDismissAction { animateDismiss() })
        .onPreferenceChange(FullScreenSheetDragActivationHeightPreferenceKey.self) {
            preferredDragActivationHeight = $0
        }

        if #available(iOS 18.0, *) {
            baseView.gesture(
                CustomPanGesture { [self] gesture in
                    let translation = clampedTranslation(gesture.translation(in: gesture.view).y)
                    let locationY   = gesture.location(in: gesture.view).y
                    let velocityY   = gesture.velocity(in: gesture.view).y

                    switch gesture.state {
                    case .began:
                        guard canStartDismiss(at: locationY) else { return }
                        scrollDisabled = true
                        offset = translation

                    case .changed:
                        guard scrollDisabled else { return }
                        offset = translation

                    case .ended, .cancelled, .failed:
                        if scrollDisabled {
                            gesture.isEnabled = false
                            let predictedEnd = translation + max(velocityY * 0.28, 0)
                            finalizeDrag(translation: translation, predictedEnd: predictedEnd) {
                                gesture.isEnabled = true
                            }
                        } else {
                            let startY = gesture.location(in: gesture.view).y - translation
                            let isDownwardFlick = velocityY > 500
                                && canStartDismiss(at: startY)
                                && abs(gesture.translation(in: gesture.view).y)
                                    >= abs(gesture.translation(in: gesture.view).x)
                            if isDownwardFlick {
                                gesture.isEnabled = false
                                animateDismiss { gesture.isEnabled = true }
                            }
                        }

                    default: ()
                    }
                }
            )
        } else {
            baseView.background {
                LegacySheetPanBridge(
                    activationHeight: preferredDragActivationHeight ?? dragDismissActivationHeight
                ) { [self] gesture in
                    let translation = clampedTranslation(gesture.translation(in: gesture.view).y)
                    let velocityY   = gesture.velocity(in: gesture.view).y

                    switch gesture.state {
                    case .began:
                        scrollDisabled = true
                        offset = translation

                    case .changed:
                        guard scrollDisabled else { return }
                        offset = translation

                    case .ended, .cancelled, .failed:
                        guard scrollDisabled else { return }
                        gesture.isEnabled = false
                        let predictedEnd = translation + max(velocityY * 0.28, 0)
                        finalizeDrag(translation: translation, predictedEnd: predictedEnd) {
                            gesture.isEnabled = true
                        }

                    default:
                        break
                    }
                }
                .frame(width: 0, height: 0)
            }
        }
    }

    // MARK: - Dismiss Logic

    private func finalizeDrag(
        translation: CGFloat,
        predictedEnd: CGFloat,
        completion: (() -> Void)?
    ) {
        if predictedEnd > windowSize.height * 0.28 {
            animateDismiss(completion: completion)
        } else {
            withAnimation(dismissalAnimation) { offset = 0 }
            if translation < windowSize.height * 0.05 {
                scrollDisabled = false
                completion?()
            } else {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(animationDurationMilliseconds))
                    scrollDisabled = false
                    completion?()
                }
            }
        }
    }

    private func animateDismiss(completion: (() -> Void)? = nil) {
        guard !isAnimatingDismiss else { return }
        isAnimatingDismiss = true
        scrollDisabled = true

        withAnimation(dismissalAnimation) { offset = windowSize.height }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(animationDurationMilliseconds))
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) { dismiss() }
            isAnimatingDismiss = false
            scrollDisabled = false
            completion?()
        }
    }

    // MARK: - Helpers

    private var windowSize: CGSize {
        keyWindow?.bounds.size ?? UIScreen.main.bounds.size
    }

    private var safeAreaInsets: UIEdgeInsets {
        keyWindow?.safeAreaInsets ?? .zero
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private func canStartDismiss(at locationY: CGFloat) -> Bool {
        let h = preferredDragActivationHeight ?? dragDismissActivationHeight
        guard let h else { return true }
        return locationY <= h
    }

    private func clampedTranslation(_ raw: CGFloat) -> CGFloat {
        min(max(raw, 0), windowSize.height)
    }

    private var animationDurationMilliseconds: Int {
        Int(UIConstants.Animation.medium * 1_000)
    }
}

// MARK: - Legacy Sheet Pan Bridge (iOS 17)

private struct LegacySheetPanBridge: UIViewRepresentable {
    let activationHeight: CGFloat?
    let onPan: (UIPanGestureRecognizer) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.activationHeight = activationHeight
        view.onPan = onPan
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.activationHeight = activationHeight
        uiView.onPan = onPan
    }

    final class ProbeView: UIView, UIGestureRecognizerDelegate {
        var activationHeight: CGFloat?
        var onPan: ((UIPanGestureRecognizer) -> Void)?

        private weak var hostView: UIView?
        private lazy var panGesture: UIPanGestureRecognizer = {
            let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            gesture.delegate = self
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            gesture.maximumNumberOfTouches = 1
            return gesture
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isHidden = true
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("Not implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                attachPanGestureIfNeeded()
            } else {
                detachPanGesture()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard window != nil else { return }
            attachPanGestureIfNeeded()
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            onPan?(gesture)
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let host = hostView else { return false }

            let location = pan.location(in: host)
            if let activationHeight, location.y > activationHeight {
                return false
            }

            let velocity = pan.velocity(in: host)
            if velocity == .zero { return true }
            return velocity.y > 0 && abs(velocity.y) >= abs(velocity.x)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let host = hostView else { return false }

            let velocityY = pan.velocity(in: host).y
            var scrollOffset: CGFloat = 0
            if let collectionView = otherGestureRecognizer.view as? UICollectionView {
                scrollOffset = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
            } else if let scrollView = otherGestureRecognizer.view as? UIScrollView {
                scrollOffset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            }
            return Int(scrollOffset) <= 1 && velocityY > 0
        }

        private func attachPanGestureIfNeeded() {
            guard let target = gestureHostView() else { return }
            if hostView !== target {
                detachPanGesture()
                target.addGestureRecognizer(panGesture)
                hostView = target
            }
        }

        private func gestureHostView() -> UIView? {
            var candidate: UIView? = superview
            var highest: UIView?
            while let view = candidate, !(view is UIWindow) {
                highest = view
                candidate = view.superview
            }
            return highest
        }

        private func detachPanGesture() {
            if let hostView {
                hostView.removeGestureRecognizer(panGesture)
            }
            hostView = nil
        }

        deinit {
            detachPanGesture()
        }
    }
}

// MARK: - Custom Pan Gesture (iOS 18+)

@available(iOS 18.0, *)
private struct CustomPanGesture: UIGestureRecognizerRepresentable {
    var handle: (UIPanGestureRecognizer) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.delegate = context.coordinator
        return g
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {}

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        handle(recognizer)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let vy = pan.velocity(in: pan.view).y
            var scrollOffset: CGFloat = 0
            if let cv = other.view as? UICollectionView {
                scrollOffset = cv.contentOffset.y + cv.adjustedContentInset.top
            }
            if let sv = other.view as? UIScrollView {
                scrollOffset = sv.contentOffset.y + sv.adjustedContentInset.top
            }
            return Int(scrollOffset) <= 1 && vy > 0
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            !(gestureRecognizer.view?.gestureRecognizers?
                .contains(where: { ($0.name ?? "").localizedStandardContains("zoom") }) ?? false)
        }
    }
}

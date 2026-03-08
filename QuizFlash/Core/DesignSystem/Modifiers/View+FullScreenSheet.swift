//
//  View+FullScreenSheet.swift
//  QuizFlash
//
//  Reusable full-screen sheet wrapper that coordinates a custom slide-out
//  dismissal animation for both drag gestures and button-triggered dismissals.
//

import SwiftUI
import UIKit

// MARK: - Full Screen Sheet Dismiss Action

/// Environment-provided dismiss action that reuses the custom sheet slide-out animation.
struct FullScreenSheetDismissAction {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func callAsFunction() {
        handler()
    }
}

// MARK: - Environment Values

private struct FullScreenSheetDismissActionKey: EnvironmentKey {
    static let defaultValue: FullScreenSheetDismissAction? = nil
}

private struct FullScreenSheetDragActivationHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() {
            value = next
        }
    }
}

extension EnvironmentValues {
    /// Dismisses a custom `fullScreenSheet` using the wrapper's coordinated animation.
    var fullScreenSheetDismiss: FullScreenSheetDismissAction? {
        get { self[FullScreenSheetDismissActionKey.self] }
        set { self[FullScreenSheetDismissActionKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Presents a full-screen sheet with a coordinated drag-to-dismiss animation.
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

    /// Presents an identifiable item in a full-screen sheet with a coordinated drag-to-dismiss animation.
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
                content: { safeAreaInsets in
                    content(wrappedItem, safeAreaInsets)
                },
                background: background
            )
        }
    }

    /// Publishes the maximum Y coordinate that may start a sheet drag-to-dismiss interaction.
    func fullScreenSheetDragActivationHeight(_ height: CGFloat?) -> some View {
        preference(
            key: FullScreenSheetDragActivationHeightPreferenceKey.self,
            value: height
        )
    }
}

// MARK: - Full Screen Sheet Container

/// Hosts the presented view and drives the custom offset-based dismissal motion.
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
        let height = max(windowSize.height, 1)
        return min(max(offset / height, 0), 1)
    }

    private var activeSheetCornerRadius: CGFloat {
        guard offset > 0 else { return 0 }
        return UIConstants.isPad ? 32 : 28
    }

    var body: some View {
        // The rounded-top shape used to clip the background layer during drag.
        // Only the background is clipped — content is never clipped, so text
        // inside cards never reflows when the corner radius animates in/out.
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
            // ── Background layer ────────────────────────────────────────────
            // clipShape is applied HERE, not on the ZStack, so layout of
            // everything above this layer is never affected.  The shadow is
            // also placed here so it hugs the rounded shape during drag.
            background
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(sheetShape)
                .shadow(
                    color: .black.opacity(dragProgress > 0 ? 0.14 : 0),
                    radius: dragProgress > 0 ? UIConstants.Shadow.heavyRadius : 0,
                    y: dragProgress > 0 ? UIConstants.Shadow.yOffset * 2 : 0
                )

            // ── Content layer ───────────────────────────────────────────────
            // No clipShape, no shadow — the background layer provides all
            // visual chrome.  Text, cards, and scroll views measure against
            // the full-screen frame at all times.
            content(safeAreaInsets)
                .scrollDisabled(scrollDisabled)
        }
        .geometryGroup()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .offset(y: offset)
        .presentationBackground {
            // Transparent so the background inside the ZStack body is the only
            // visible surface — prevents a double-background artefact.
            Color.clear
        }
        .ignoresSafeArea(.container, edges: ignoresSafeArea ? .all : [])
        .environment(\.fullScreenSheetDismiss, FullScreenSheetDismissAction {
            animateDismiss()
        })
        .onPreferenceChange(FullScreenSheetDragActivationHeightPreferenceKey.self) { newValue in
            preferredDragActivationHeight = newValue
        }

        if #available(iOS 18.0, *) {
            baseView.gesture(
                CustomPanGesture { gesture in
                    let translation = boundedTranslation(from: gesture.translation(in: gesture.view).y)
                    let velocity = boundedVelocity(from: gesture.velocity(in: gesture.view).y / 5)
                    let locationY = gesture.location(in: gesture.view).y

                    switch gesture.state {
                    case .began:
                        guard canStartDismiss(at: locationY) else { return }
                        scrollDisabled = true
                        offset = translation

                    case .changed:
                        guard scrollDisabled else { return }
                        offset = translation

                    case .ended, .cancelled, .failed:
                        guard scrollDisabled else { return }

                        gesture.isEnabled = false
                        finalizeDrag(translation: translation, velocity: velocity) {
                            gesture.isEnabled = true
                        }

                    default:
                        ()
                    }
                }
            )
        } else {
            baseView.simultaneousGesture(fallbackDismissGesture)
        }
    }

    private var fallbackDismissGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                guard shouldTrackFallbackDismiss(value) else { return }

                if !scrollDisabled {
                    scrollDisabled = true
                }

                offset = boundedTranslation(from: value.translation.height)
            }
            .onEnded { value in
                guard scrollDisabled, shouldTrackFallbackDismiss(value) else { return }

                let translation = boundedTranslation(from: value.translation.height)
                let velocity = boundedVelocity(
                    from: value.predictedEndTranslation.height - value.translation.height
                )

                finalizeDrag(translation: translation, velocity: velocity, completion: nil)
            }
    }

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
        let activationHeight = preferredDragActivationHeight ?? dragDismissActivationHeight
        guard let activationHeight else { return true }
        return locationY <= activationHeight
    }

    private func shouldTrackFallbackDismiss(_ value: DragGesture.Value) -> Bool {
        canStartDismiss(at: value.startLocation.y)
            && value.translation.height > 0
            && abs(value.translation.height) > abs(value.translation.width)
    }

    private func boundedTranslation(from rawValue: CGFloat) -> CGFloat {
        min(max(rawValue, 0), windowSize.height)
    }

    private func boundedVelocity(from rawValue: CGFloat) -> CGFloat {
        min(max(rawValue, 0), windowSize.height / 2)
    }

    private func finalizeDrag(
        translation: CGFloat,
        velocity: CGFloat,
        completion: (() -> Void)?
    ) {
        let halfHeight = windowSize.height / 2

        if (translation + velocity) > halfHeight {
            animateDismiss(completion: completion)
        } else {
            withAnimation(dismissalAnimation) {
                offset = 0
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(animationDurationMilliseconds))
                scrollDisabled = false
                completion?()
            }
        }
    }

    private func animateDismiss(completion: (() -> Void)? = nil) {
        guard !isAnimatingDismiss else { return }

        isAnimatingDismiss = true
        scrollDisabled = true

        withAnimation(dismissalAnimation) {
            offset = windowSize.height
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(animationDurationMilliseconds))

            var transaction = Transaction()
            transaction.disablesAnimations = true

            withTransaction(transaction) {
                dismiss()
            }

            isAnimatingDismiss = false
            scrollDisabled = false
            completion?()
        }
    }

    private var animationDurationMilliseconds: Int {
        Int(UIConstants.Animation.medium * 1_000)
    }
}

// MARK: - Custom Pan Gesture

/// Bridges a `UIPanGestureRecognizer` into SwiftUI so the sheet can coordinate with nested scroll views.
@available(iOS 18.0, *)
private struct CustomPanGesture: UIGestureRecognizerRepresentable {
    var handle: (UIPanGestureRecognizer) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer()
        gesture.delegate = context.coordinator
        return gesture
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {}

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        handle(recognizer)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
                return false
            }

            let verticalVelocity = panGesture.velocity(in: panGesture.view).y
            var scrollOffset: CGFloat = 0

            if let collectionView = otherGestureRecognizer.view as? UICollectionView {
                scrollOffset = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
            }

            if let scrollView = otherGestureRecognizer.view as? UIScrollView {
                scrollOffset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            }

            return Int(scrollOffset) <= 1 && verticalVelocity > 0
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let hasZoomGesture = gestureRecognizer.view?.gestureRecognizers?.contains(where: {
                ($0.name ?? "").localizedStandardContains("zoom")
            }) ?? false

            return !hasZoomGesture
        }
    }
}

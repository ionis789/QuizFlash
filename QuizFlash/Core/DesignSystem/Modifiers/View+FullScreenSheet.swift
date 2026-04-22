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

private struct FullScreenSheetDismissCoordinatorKey: EnvironmentKey {
    static let defaultValue: FullScreenSheetDismissCoordinator? = nil
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

    var fullScreenSheetDismissCoordinator: FullScreenSheetDismissCoordinator? {
        get { self[FullScreenSheetDismissCoordinatorKey.self] }
        set { self[FullScreenSheetDismissCoordinatorKey.self] = newValue }
    }
}

// MARK: - Dismiss Coordination

final class FullScreenSheetDismissCoordinator {
    var shouldAllowDismiss: (() -> Bool)?
}

// MARK: - Sheet Configuration

/// Available presentation heights for the shared QuizFlash sheet surface.
enum FullScreenSheetHeightMode: Sendable {
    case fullScreen
    case medium
    case small
    case custom(CGFloat)

    fileprivate func resolvedHeight(in containerHeight: CGFloat) -> CGFloat {
        let fraction: CGFloat
        switch self {
        case .fullScreen:
            fraction = 1
        case .medium:
            fraction = 0.7
        case .small:
            fraction = 0.5
        case .custom(let value):
            fraction = min(max(value, 0.2), 1)
        }

        return max(containerHeight * fraction, 1)
    }
}

/// Defines the area near the sheet's top edge that can start drag-dismiss.
enum FullScreenSheetDragActivationArea: Sendable {
    case fullSurface
    case fixed(CGFloat)
    case fraction(CGFloat)

    fileprivate func resolvedHeight(sheetHeight: CGFloat) -> CGFloat? {
        switch self {
        case .fullSurface:
            return nil
        case .fixed(let value):
            return max(value, 0)
        case .fraction(let value):
            return max(sheetHeight * min(max(value, 0), 1), 0)
        }
    }
}

/// Shared presentation configuration for `fullScreenSheet`.
struct FullScreenSheetConfiguration: Sendable {
    var ignoresSafeArea: Bool = true
    var heightMode: FullScreenSheetHeightMode = .fullScreen
    var topCornerRadius: CGFloat = UIConstants.Radius.maximum
    var dragActivationArea: FullScreenSheetDragActivationArea = .fullSurface
    var showsDragIndicator: Bool = false
    var dragIndicatorTopPadding: CGFloat = UIConstants.Spacing.extraLarge
    var backgroundReceivesDragProgress: Bool = true
    var appliesDefaultDragTopOverlay: Bool = false

    /// Standard rounded QuizFlash sheet with drag indicator and clipped top corners.
    static func sheet(
        ignoresSafeArea: Bool = true,
        heightMode: FullScreenSheetHeightMode = .fullScreen,
        topCornerRadius: CGFloat = UIConstants.Radius.maximum,
        dragActivationArea: FullScreenSheetDragActivationArea = .fullSurface,
        showsDragIndicator: Bool = false,
        dragIndicatorTopPadding: CGFloat = UIConstants.Spacing.extraLarge,
        backgroundReceivesDragProgress: Bool = true
    ) -> FullScreenSheetConfiguration {
        FullScreenSheetConfiguration(
            ignoresSafeArea: ignoresSafeArea,
            heightMode: heightMode,
            topCornerRadius: topCornerRadius,
            dragActivationArea: dragActivationArea,
            showsDragIndicator: showsDragIndicator,
            dragIndicatorTopPadding: dragIndicatorTopPadding,
            backgroundReceivesDragProgress: backgroundReceivesDragProgress,
            appliesDefaultDragTopOverlay: false
        )
    }

    /// Full-height rounded sheet used by immersive surfaces that already own their top chrome.
    static func chrome(
        ignoresSafeArea: Bool = true,
        heightMode: FullScreenSheetHeightMode = .fullScreen,
        topCornerRadius: CGFloat = UIConstants.Radius.maximum,
        dragActivationArea: FullScreenSheetDragActivationArea = .fullSurface,
        backgroundReceivesDragProgress: Bool = true
    ) -> FullScreenSheetConfiguration {
        FullScreenSheetConfiguration(
            ignoresSafeArea: ignoresSafeArea,
            heightMode: heightMode,
            topCornerRadius: topCornerRadius,
            dragActivationArea: dragActivationArea,
            showsDragIndicator: false,
            dragIndicatorTopPadding: UIConstants.Spacing.extraLarge,
            backgroundReceivesDragProgress: backgroundReceivesDragProgress,
            appliesDefaultDragTopOverlay: false
        )
    }
}

// MARK: - View Extension

extension View {
    @ViewBuilder
    func fullScreenSheet<Content: View, Background: View>(
        isPresented: Binding<Bool>,
        configuration: FullScreenSheetConfiguration = .sheet(),
        @ViewBuilder content: @escaping (UIEdgeInsets) -> Content,
        @ViewBuilder background: @escaping () -> Background
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            FullScreenSheetContainer(
                configuration: configuration,
                content: content,
                background: background
            )
        }
    }

    @ViewBuilder
    func fullScreenSheet<Item: Identifiable, Content: View, Background: View>(
        item: Binding<Item?>,
        configuration: FullScreenSheetConfiguration = .sheet(),
        @ViewBuilder content: @escaping (Item, UIEdgeInsets) -> Content,
        @ViewBuilder background: @escaping () -> Background
    ) -> some View {
        fullScreenCover(item: item) { wrappedItem in
            FullScreenSheetContainer(
                configuration: configuration,
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
    let configuration: FullScreenSheetConfiguration
    @ViewBuilder var content: (UIEdgeInsets) -> Content
    @ViewBuilder var background: Background

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var offset: CGFloat = 0
    @State private var scrollDisabled = false
    @State private var isAnimatingDismiss = false
    @State private var preferredDragActivationHeight: CGFloat? = nil
    @State private var dismissCoordinator = FullScreenSheetDismissCoordinator()

    private var dismissalAnimation: Animation {
            .snappy(duration: UIConstants.Animation.medium, extraBounce: 0)
    }

    private var dragIndicatorHeight: CGFloat { 6 }
    private var dragIndicatorWidth: CGFloat { 54 }
    private var dragIndicatorTopPadding: CGFloat { configuration.dragIndicatorTopPadding }
    private var dragIndicatorBottomPadding: CGFloat { UIConstants.Spacing.medium }
    private var dragIndicatorInset: CGFloat {
        configuration.showsDragIndicator
            ? dragIndicatorTopPadding + dragIndicatorHeight + dragIndicatorBottomPadding
            : 0
    }

    var body: some View {
        let containerHeight = max(windowSize.height, 1)
        let containerWidth = max(windowSize.width, 1)
        let sheetHeight = configuration.heightMode.resolvedHeight(in: containerHeight)
        let sheetTopY = max(containerHeight - sheetHeight, 0)
        let contentSafeAreaInsets = resolvedContentSafeAreaInsets(
            sheetTopY: sheetTopY,
            additionalTopInset: dragIndicatorInset
        )
        let dragProgress = min(max(offset / containerHeight, 0), 1)
        let sheetShape = UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: configuration.topCornerRadius,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: configuration.topCornerRadius
            ),
            style: .continuous
        )

        let sheetSurface = ZStack(alignment: .top) {
            backgroundView(dragProgress: dragProgress)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if configuration.appliesDefaultDragTopOverlay {
                defaultDragTopOverlay(dragProgress: dragProgress)
                    .allowsHitTesting(false)
            }

            StableHostedSheetContent(
                topCornerRadius: configuration.topCornerRadius,
                interactionDisabled: scrollDisabled,
                makeRootView: { content(contentSafeAreaInsets) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.fullScreenSheetDragProgress, dragProgress)

            if configuration.showsDragIndicator {
                Capsule()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.32))
                    .frame(width: dragIndicatorWidth, height: dragIndicatorHeight)
                    .padding(.top, dragIndicatorTopPadding)
                    .allowsHitTesting(false)
            }
        }
        .compositingGroup()
        .clipShape(sheetShape)
        .frame(width: containerWidth, height: sheetHeight, alignment: .topLeading)
        .offset(y: offset)

        let baseView = ZStack(alignment: .bottom) {
            sheetSurface
        }
        .frame(width: containerWidth, height: containerHeight, alignment: .bottom)
        .contentShape(.rect)
        .presentationBackground { Color.clear }
        .ignoresSafeArea(.container, edges: configuration.ignoresSafeArea ? .all : [])
        .environment(
            \.fullScreenSheetDismiss,
            FullScreenSheetDismissAction {
                animateDismiss(containerHeight: containerHeight)
            }
        )
        .environment(\.fullScreenSheetDismissCoordinator, dismissCoordinator)
        .onPreferenceChange(FullScreenSheetDragActivationHeightPreferenceKey.self) {
            preferredDragActivationHeight = $0
        }

        if #available(iOS 18.0, *) {
            baseView.gesture(
                CustomPanGesture { [self] gesture in
                    let translation = clampedTranslation(
                        gesture.translation(in: gesture.view).y,
                        containerHeight: containerHeight
                    )
                    let locationY = gesture.location(in: gesture.view).y
                    let velocityY = gesture.velocity(in: gesture.view).y

                    switch gesture.state {
                    case .began:
                        guard canStartDismiss(at: locationY, sheetTopY: sheetTopY, sheetHeight: sheetHeight) else { return }
                        scrollDisabled = true
                        offset = translation

                    case .changed:
                        guard scrollDisabled else { return }
                        offset = translation

                    case .ended, .cancelled, .failed:
                        if scrollDisabled {
                            gesture.isEnabled = false
                            let predictedEnd = translation + max(velocityY * 0.28, 0)
                            finalizeDrag(
                                translation: translation,
                                predictedEnd: predictedEnd,
                                containerHeight: containerHeight
                            ) {
                                gesture.isEnabled = true
                            }
                        } else {
                            let startY = gesture.location(in: gesture.view).y - translation
                            let isDownwardFlick = velocityY > 500
                                && canStartDismiss(at: startY, sheetTopY: sheetTopY, sheetHeight: sheetHeight)
                                && abs(gesture.translation(in: gesture.view).y)
                            >= abs(gesture.translation(in: gesture.view).x)
                            if isDownwardFlick {
                                gesture.isEnabled = false
                                animateDismiss(containerHeight: containerHeight) {
                                    gesture.isEnabled = true
                                }
                            }
                        }

                    default:
                        ()
                    }
                }
            )
        } else {
            baseView.background {
                LegacySheetPanBridge(
                    sheetTopY: sheetTopY,
                    activationHeight: resolvedDragActivationHeight(sheetHeight: sheetHeight)
                ) { [self] gesture in
                    let translation = clampedTranslation(
                        gesture.translation(in: gesture.view).y,
                        containerHeight: containerHeight
                    )
                    let velocityY = gesture.velocity(in: gesture.view).y

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
                        finalizeDrag(
                            translation: translation,
                            predictedEnd: predictedEnd,
                            containerHeight: containerHeight
                        ) {
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

    @ViewBuilder
    private func backgroundView(dragProgress: CGFloat) -> some View {
        if configuration.backgroundReceivesDragProgress {
            background
                .environment(\.fullScreenSheetDragProgress, dragProgress)
        } else {
            background
        }
    }

    private func defaultDragTopOverlay(dragProgress: CGFloat) -> some View {
        topOverlayTint
            .opacity(topOverlayOpacity(for: dragProgress))
            .mask(topOverlayMask)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Dismiss Logic

    private func finalizeDrag(
        translation: CGFloat,
        predictedEnd: CGFloat,
        containerHeight: CGFloat,
        completion: (() -> Void)?
    ) {
        if predictedEnd > containerHeight * 0.28 {
            animateDismiss(containerHeight: containerHeight, completion: completion)
        } else {
            withAnimation(dismissalAnimation) { offset = 0 }
            if translation < containerHeight * 0.05 {
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

    private func animateDismiss(
        containerHeight: CGFloat,
        completion: (() -> Void)? = nil
    ) {
        guard !isAnimatingDismiss else { return }
        guard dismissCoordinator.shouldAllowDismiss?() ?? true else {
            scrollDisabled = false
            completion?()
            return
        }
        isAnimatingDismiss = true
        scrollDisabled = true

        withAnimation(dismissalAnimation) { offset = containerHeight }

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

    private func canStartDismiss(
        at locationY: CGFloat,
        sheetTopY: CGFloat,
        sheetHeight: CGFloat
    ) -> Bool {
        guard locationY >= sheetTopY else { return false }
        guard let activationHeight = resolvedDragActivationHeight(sheetHeight: sheetHeight) else {
            return locationY <= sheetTopY + sheetHeight
        }
        return locationY <= sheetTopY + activationHeight
    }

    private func clampedTranslation(
        _ raw: CGFloat,
        containerHeight: CGFloat
    ) -> CGFloat {
        min(max(raw, 0), containerHeight)
    }

    private var animationDurationMilliseconds: Int {
        Int(UIConstants.Animation.medium * 1_000)
    }

    private func resolvedDragActivationHeight(sheetHeight: CGFloat) -> CGFloat? {
        if let preferredDragActivationHeight {
            return preferredDragActivationHeight
        }

        return configuration.dragActivationArea.resolvedHeight(sheetHeight: sheetHeight)
    }

    private func resolvedContentSafeAreaInsets(
        sheetTopY: CGFloat,
        additionalTopInset: CGFloat
    ) -> UIEdgeInsets {
        UIEdgeInsets(
            top: (sheetTopY <= windowSafeAreaInsets.top + 1 ? windowSafeAreaInsets.top : 0) + additionalTopInset,
            left: windowSafeAreaInsets.left,
            bottom: windowSafeAreaInsets.bottom,
            right: windowSafeAreaInsets.right
        )
    }

    private var topOverlayMask: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0.00),
                .init(color: .white, location: 0.06),
                .init(color: .clear, location: 0.30)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var topOverlayTint: Color {
        colorScheme == .dark ? .white : .white
    }

    private func topOverlayOpacity(for dragProgress: CGFloat) -> Double {
        let progress = min(max(dragProgress / 0.08, 0), 1)
        let maxOpacity = colorScheme == .dark ? 0.16 : 0.08
        return progress * maxOpacity
    }

    private var windowSize: CGSize {
        if let size = keyWindow?.bounds.size, size != .zero {
            return size
        }
        return activeWindowScene?.screen.bounds.size ?? .zero
    }

    private var windowSafeAreaInsets: UIEdgeInsets {
        keyWindow?.safeAreaInsets ?? .zero
    }

    private var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
    }

    private var keyWindow: UIWindow? {
        activeWindowScene?.windows.first(where: \.isKeyWindow)
    }
}

// MARK: - Stable Hosted Sheet Content

/// Hosts the heavy SwiftUI sheet content inside a persistent `UIHostingController`
/// so drag offset updates on the outer container do not force the entire content
/// tree to be rebuilt every frame.
private struct StableHostedSheetContent<Root: View>: UIViewControllerRepresentable {
    let topCornerRadius: CGFloat
    let interactionDisabled: Bool
    let makeRootView: () -> Root

    func makeUIViewController(context: Context) -> SheetHostingContainerController {
        let controller = SheetHostingContainerController(
            rootView: hostedRootView,
            topCornerRadius: topCornerRadius
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: SheetHostingContainerController, context: Context) {
        uiViewController.updateTopCornerRadius(topCornerRadius)
        uiViewController.setSheetInteractionDisabled(interactionDisabled)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController: SheetHostingContainerController,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private var hostedRootView: AnyView {
        AnyView(
            makeRootView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .ignoresSafeArea(.container, edges: .all)
        )
    }
}

private final class SheetHostingContainerController: UIViewController {
    private let hostingController: SheetHostingController

    init(rootView: AnyView, topCornerRadius: CGFloat) {
        self.hostingController = SheetHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
        updateTopCornerRadius(topCornerRadius)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.clipsToBounds = true
        view.insetsLayoutMarginsFromSafeArea = false

        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.view.clipsToBounds = true
        hostingController.view.insetsLayoutMarginsFromSafeArea = false
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    func setSheetInteractionDisabled(_ disabled: Bool) {
        hostingController.setSheetInteractionDisabled(disabled)
    }

    func updateTopCornerRadius(_ radius: CGFloat) {
        let resolvedRadius = max(radius, 0)
        let maskedCorners: CACornerMask = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner
        ]

        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = resolvedRadius
        view.layer.maskedCorners = maskedCorners
        view.layer.masksToBounds = resolvedRadius > 0

        hostingController.view.layer.cornerCurve = .continuous
        hostingController.view.layer.cornerRadius = resolvedRadius
        hostingController.view.layer.maskedCorners = maskedCorners
        hostingController.view.layer.masksToBounds = resolvedRadius > 0
    }
}

private final class SheetHostingController: UIHostingController<AnyView> {
    private struct ScrollState {
        let bounces: Bool
        let alwaysBounceVertical: Bool
    }

    private var preservedScrollStates: [ObjectIdentifier: ScrollState] = [:]
    private var isSheetInteractionDisabled = false

    func setSheetInteractionDisabled(_ disabled: Bool) {
        guard disabled != isSheetInteractionDisabled else { return }
        isSheetInteractionDisabled = disabled
        view.isUserInteractionEnabled = !disabled

        if disabled {
            freezeNestedScrollViews()
        } else {
            restoreNestedScrollViews()
        }
    }

    private func freezeNestedScrollViews() {
        for scrollView in nestedVerticalScrollViews(in: view) {
            let id = ObjectIdentifier(scrollView)
            if preservedScrollStates[id] == nil {
                preservedScrollStates[id] = ScrollState(
                    bounces: scrollView.bounces,
                    alwaysBounceVertical: scrollView.alwaysBounceVertical
                )
            }

            scrollView.layer.removeAllAnimations()
            let topOffset = -scrollView.adjustedContentInset.top
            if scrollView.contentOffset.y < topOffset {
                scrollView.setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: topOffset),
                    animated: false
                )
            }

            scrollView.bounces = false
            scrollView.alwaysBounceVertical = false
        }
    }

    private func restoreNestedScrollViews() {
        for scrollView in nestedVerticalScrollViews(in: view) {
            let id = ObjectIdentifier(scrollView)
            guard let state = preservedScrollStates[id] else { continue }
            scrollView.bounces = state.bounces
            scrollView.alwaysBounceVertical = state.alwaysBounceVertical
        }
        preservedScrollStates.removeAll()
    }

    private func nestedVerticalScrollViews(in root: UIView) -> [UIScrollView] {
        var result: [UIScrollView] = []

        func walk(_ view: UIView) {
            if let scrollView = view as? UIScrollView,
               scrollView.contentSize.height > scrollView.bounds.height + 1 || scrollView.alwaysBounceVertical {
                result.append(scrollView)
            }
            for subview in view.subviews {
                walk(subview)
            }
        }

        walk(root)
        return result
    }
}

// MARK: - Legacy Sheet Pan Bridge (iOS 17)

private struct LegacySheetPanBridge: UIViewRepresentable {
    let sheetTopY: CGFloat
    let activationHeight: CGFloat?
    let onPan: (UIPanGestureRecognizer) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.sheetTopY = sheetTopY
        view.activationHeight = activationHeight
        view.onPan = onPan
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.sheetTopY = sheetTopY
        uiView.activationHeight = activationHeight
        uiView.onPan = onPan
    }

    final class ProbeView: UIView, UIGestureRecognizerDelegate {
        var sheetTopY: CGFloat = 0
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
            guard location.y >= sheetTopY else { return false }
            if let activationHeight, location.y > sheetTopY + activationHeight {
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

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) { }

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

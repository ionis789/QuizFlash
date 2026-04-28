//
//  View+FullScreenSheet.swift
//  QuizFlash
//

import SwiftUI
import UIKit

private let fullScreenSheetDismissVerticalBias: CGFloat = 1.2

private func fullScreenSheetHasDownwardDismissIntent(
    _ pan: UIPanGestureRecognizer,
    in view: UIView?
) -> Bool {
    guard let view else { return false }

    let velocity = pan.velocity(in: view)
    let translation = pan.translation(in: view)
    let verticalSignal = abs(velocity.y) > 1 ? velocity.y : translation.y
    let horizontalSignal = max(abs(velocity.x), abs(translation.x))

    guard verticalSignal > 0 else { return false }
    return abs(verticalSignal) >= horizontalSignal * fullScreenSheetDismissVerticalBias
}

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

private struct FullScreenSheetTopChromeClearanceKey: EnvironmentKey {
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

    /// Vertical clearance reserved for the shared custom-sheet top blur/header.
    var fullScreenSheetTopChromeClearance: CGFloat {
        get { self[FullScreenSheetTopChromeClearanceKey.self] }
        set { self[FullScreenSheetTopChromeClearanceKey.self] = newValue }
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
    var showsBackdropBlur: Bool = true
    var showsDefaultTopProgressiveBlur: Bool = true
    var showsCloseButton: Bool = false
    var appliesDefaultDragTopOverlay: Bool = false
    var hidesTabBar: Bool = true
    var coversTabBar: Bool = false

    /// Standard rounded QuizFlash sheet with drag indicator and clipped top corners.
    static func sheet(
        ignoresSafeArea: Bool = true,
        heightMode: FullScreenSheetHeightMode = .fullScreen,
        topCornerRadius: CGFloat = UIConstants.Radius.maximum,
        dragActivationArea: FullScreenSheetDragActivationArea = .fullSurface,
        showsDragIndicator: Bool = false,
        dragIndicatorTopPadding: CGFloat = UIConstants.Spacing.extraLarge,
        backgroundReceivesDragProgress: Bool = true,
        showsBackdropBlur: Bool = true,
        showsDefaultTopProgressiveBlur: Bool = true,
        showsCloseButton: Bool = false,
        hidesTabBar: Bool = true,
        coversTabBar: Bool = false
    ) -> FullScreenSheetConfiguration {
        FullScreenSheetConfiguration(
            ignoresSafeArea: ignoresSafeArea,
            heightMode: heightMode,
            topCornerRadius: topCornerRadius,
            dragActivationArea: dragActivationArea,
            showsDragIndicator: showsDragIndicator,
            dragIndicatorTopPadding: dragIndicatorTopPadding,
            backgroundReceivesDragProgress: backgroundReceivesDragProgress,
            showsBackdropBlur: showsBackdropBlur,
            showsDefaultTopProgressiveBlur: showsDefaultTopProgressiveBlur,
            showsCloseButton: showsCloseButton,
            appliesDefaultDragTopOverlay: false,
            hidesTabBar: hidesTabBar,
            coversTabBar: coversTabBar
        )
    }

    /// Full-height rounded sheet used by immersive surfaces that already own their top chrome.
    static func chrome(
        ignoresSafeArea: Bool = true,
        heightMode: FullScreenSheetHeightMode = .fullScreen,
        topCornerRadius: CGFloat = UIConstants.Radius.maximum,
        dragActivationArea: FullScreenSheetDragActivationArea = .fullSurface,
        backgroundReceivesDragProgress: Bool = true,
        showsBackdropBlur: Bool = false,
        showsDefaultTopProgressiveBlur: Bool = false,
        showsCloseButton: Bool = false,
        hidesTabBar: Bool = true,
        coversTabBar: Bool = false
    ) -> FullScreenSheetConfiguration {
        FullScreenSheetConfiguration(
            ignoresSafeArea: ignoresSafeArea,
            heightMode: heightMode,
            topCornerRadius: topCornerRadius,
            dragActivationArea: dragActivationArea,
            showsDragIndicator: false,
            dragIndicatorTopPadding: UIConstants.Spacing.extraLarge,
            backgroundReceivesDragProgress: backgroundReceivesDragProgress,
            showsBackdropBlur: showsBackdropBlur,
            showsDefaultTopProgressiveBlur: showsDefaultTopProgressiveBlur,
            showsCloseButton: showsCloseButton,
            appliesDefaultDragTopOverlay: false,
            hidesTabBar: hidesTabBar,
            coversTabBar: coversTabBar
        )
    }
}

// MARK: - Shared Debug Settings

struct CustomSheetDebugSettings: Codable, Equatable {
    var backdropBlurRadius: CGFloat = 18
    var backdropPresentationDelay: CGFloat = UIConstants.Animation.medium * 0.18
    var backdropPresentationDuration: CGFloat = UIConstants.Animation.medium * 1.65
    var backdropDismissDuration: CGFloat = UIConstants.Animation.medium * 0.18
    var blurRadius: CGFloat = 3.12
    var blurFadeExtension: CGFloat = 27
    var blurTintOpacityTop: CGFloat = 0
    var blurTintOpacityMiddle: CGFloat = 0
    var blurAreaHeight: CGFloat = 24
    var topBlurRevealDistance: CGFloat = 44
    var contentTopInset: CGFloat = 18
    var scrimOpacity: CGFloat = 0

    static let `default` = CustomSheetDebugSettings()

    init(
        backdropBlurRadius: CGFloat = 18,
        backdropPresentationDelay: CGFloat = UIConstants.Animation.medium * 0.18,
        backdropPresentationDuration: CGFloat = UIConstants.Animation.medium * 1.65,
        backdropDismissDuration: CGFloat = UIConstants.Animation.medium * 0.18,
        blurRadius: CGFloat = 3.12,
        blurFadeExtension: CGFloat = 27,
        blurTintOpacityTop: CGFloat = 0,
        blurTintOpacityMiddle: CGFloat = 0,
        blurAreaHeight: CGFloat = 24,
        topBlurRevealDistance: CGFloat = 44,
        contentTopInset: CGFloat = 18,
        scrimOpacity: CGFloat = 0
    ) {
        self.backdropBlurRadius = backdropBlurRadius
        self.backdropPresentationDelay = backdropPresentationDelay
        self.backdropPresentationDuration = backdropPresentationDuration
        self.backdropDismissDuration = backdropDismissDuration
        self.blurRadius = blurRadius
        self.blurFadeExtension = blurFadeExtension
        self.blurTintOpacityTop = blurTintOpacityTop
        self.blurTintOpacityMiddle = blurTintOpacityMiddle
        self.blurAreaHeight = blurAreaHeight
        self.topBlurRevealDistance = topBlurRevealDistance
        self.contentTopInset = contentTopInset
        self.scrimOpacity = scrimOpacity
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.default
        backdropBlurRadius = try values.decodeIfPresent(CGFloat.self, forKey: .backdropBlurRadius) ?? defaults.backdropBlurRadius
        backdropPresentationDelay = try values.decodeIfPresent(CGFloat.self, forKey: .backdropPresentationDelay) ?? defaults.backdropPresentationDelay
        backdropPresentationDuration = try values.decodeIfPresent(CGFloat.self, forKey: .backdropPresentationDuration) ?? defaults.backdropPresentationDuration
        backdropDismissDuration = try values.decodeIfPresent(CGFloat.self, forKey: .backdropDismissDuration) ?? defaults.backdropDismissDuration
        blurRadius = try values.decodeIfPresent(CGFloat.self, forKey: .blurRadius) ?? defaults.blurRadius
        blurFadeExtension = try values.decodeIfPresent(CGFloat.self, forKey: .blurFadeExtension) ?? defaults.blurFadeExtension
        blurTintOpacityTop = try values.decodeIfPresent(CGFloat.self, forKey: .blurTintOpacityTop) ?? defaults.blurTintOpacityTop
        blurTintOpacityMiddle = try values.decodeIfPresent(CGFloat.self, forKey: .blurTintOpacityMiddle) ?? defaults.blurTintOpacityMiddle
        blurAreaHeight = try values.decodeIfPresent(CGFloat.self, forKey: .blurAreaHeight) ?? defaults.blurAreaHeight
        topBlurRevealDistance = try values.decodeIfPresent(CGFloat.self, forKey: .topBlurRevealDistance) ?? defaults.topBlurRevealDistance
        contentTopInset = try values.decodeIfPresent(CGFloat.self, forKey: .contentTopInset) ?? defaults.contentTopInset
        scrimOpacity = try values.decodeIfPresent(CGFloat.self, forKey: .scrimOpacity) ?? defaults.scrimOpacity
    }
}

private func fullScreenSheetPresentationTransaction() -> Transaction {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    return transaction
}

private func fullScreenSheetClampedProgress(_ progress: CGFloat) -> CGFloat {
    min(max(progress, 0), 1)
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
        modifier(
            FullScreenSheetBoolOverlayModifier(
                isPresented: isPresented,
                configuration: configuration,
                sheetContent: content,
                background: background
            )
        )
    }

    @ViewBuilder
    func fullScreenSheet<Item: Identifiable, Content: View, Background: View>(
        item: Binding<Item?>,
        configuration: FullScreenSheetConfiguration = .sheet(),
        @ViewBuilder content: @escaping (Item, UIEdgeInsets) -> Content,
        @ViewBuilder background: @escaping () -> Background
    ) -> some View {
        modifier(
            FullScreenSheetItemOverlayModifier(
                item: item,
                configuration: configuration,
                sheetContent: content,
                background: background
            )
        )
    }

    func fullScreenSheetDragActivationHeight(_ height: CGFloat?) -> some View {
        preference(key: FullScreenSheetDragActivationHeightPreferenceKey.self, value: height)
    }

}

// MARK: - Full Screen Sheet Overlay Modifiers

private struct FullScreenSheetBoolOverlayModifier<SheetContent: View, SheetBackground: View>: ViewModifier {
    @Binding var isPresented: Bool
    let configuration: FullScreenSheetConfiguration
    @ViewBuilder var sheetContent: (UIEdgeInsets) -> SheetContent
    @ViewBuilder var background: () -> SheetBackground

    @State private var isDismissing = false

    private var requiresModalCover: Bool {
        configuration.coversTabBar && !configuration.hidesTabBar
    }

    @ViewBuilder
    func body(content presenterContent: Content) -> some View {
        if requiresModalCover {
            presenterContent
                .fullScreenCover(isPresented: $isPresented) {
                    presentedSheet
                        .presentationBackground(.clear)
                        .interactiveDismissDisabled(true)
                }
        } else {
            presenterContent
                .overlay(alignment: .bottom) {
                    if isPresented {
                        presentedSheet
                            .customTabBarVisibility(configuration.hidesTabBar && !isDismissing ? .hidden : .implicit)
                            .ignoresSafeArea(.container, edges: configuration.ignoresSafeArea ? .all : [])
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .zIndex(1)
                    }
                }
        }
    }

    private var presentedSheet: some View {
        FullScreenSheetContainer<SheetContent, SheetBackground>(
            configuration: configuration,
            onDismissStart: {
                isDismissing = true
            },
            onDismiss: {
                withTransaction(fullScreenSheetPresentationTransaction()) {
                    isPresented = false
                }
            },
            content: sheetContent,
            background: background
        )
        .ignoresSafeArea(.container, edges: configuration.ignoresSafeArea ? .all : [])
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear {
            isDismissing = false
        }
    }
}

private struct FullScreenSheetItemOverlayModifier<Item: Identifiable, SheetContent: View, SheetBackground: View>: ViewModifier {
    @Binding var item: Item?
    let configuration: FullScreenSheetConfiguration
    @ViewBuilder var sheetContent: (Item, UIEdgeInsets) -> SheetContent
    @ViewBuilder var background: () -> SheetBackground

    @State private var isDismissing = false

    private var requiresModalCover: Bool {
        configuration.coversTabBar && !configuration.hidesTabBar
    }

    @ViewBuilder
    func body(content presenterContent: Content) -> some View {
        if requiresModalCover {
            presenterContent
                .fullScreenCover(item: $item) { wrappedItem in
                    presentedSheet(for: wrappedItem)
                        .presentationBackground(.clear)
                        .interactiveDismissDisabled(true)
                }
        } else {
            presenterContent
                .overlay(alignment: .bottom) {
                    if let wrappedItem = item {
                        presentedSheet(for: wrappedItem)
                            .customTabBarVisibility(configuration.hidesTabBar && !isDismissing ? .hidden : .implicit)
                            .ignoresSafeArea(.container, edges: configuration.ignoresSafeArea ? .all : [])
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .zIndex(1)
                    }
                }
        }
    }

    private func presentedSheet(for wrappedItem: Item) -> some View {
        FullScreenSheetContainer<SheetContent, SheetBackground>(
            configuration: configuration,
            onDismissStart: {
                isDismissing = true
            },
            onDismiss: {
                withTransaction(fullScreenSheetPresentationTransaction()) {
                    item = nil
                }
            },
            content: { insets in
                sheetContent(wrappedItem, insets)
            },
            background: background
        )
        .id(wrappedItem.id)
        .ignoresSafeArea(.container, edges: configuration.ignoresSafeArea ? .all : [])
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear {
            isDismissing = false
        }
    }
}

// MARK: - Full Screen Sheet Container

private struct FullScreenSheetContainer<Content: View, Background: View>: View {
    let configuration: FullScreenSheetConfiguration
    let onDismissStart: () -> Void
    let onDismiss: () -> Void
    @ViewBuilder var content: (UIEdgeInsets) -> Content
    @ViewBuilder var background: Background

    @Environment(AppPreferences.self) private var appPreferences
    @Environment(DevelopmentPreferences.self) private var developmentPreferences
    @Environment(\.colorScheme) private var colorScheme

    @State private var offset: CGFloat = 0
    @State private var scrollDisabled = false
    @State private var isAnimatingDismiss = false
    @State private var presentationProgress: CGFloat = 0
    @State private var contentScrollOffset: CGFloat = 0
    @State private var preferredDragActivationHeight: CGFloat? = nil
    @State private var dismissCoordinator = FullScreenSheetDismissCoordinator()

    private var dismissalAnimation: Animation {
        .snappy(duration: UIConstants.Animation.medium, extraBounce: 0)
    }

    private var presentationAnimation: Animation {
        .smooth(duration: UIConstants.Animation.medium * 1.05, extraBounce: 0)
    }

    private var locale: Locale {
        appPreferences.resolvedLocale
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

    private var closeButtonReservedWidth: CGFloat {
        guard configuration.showsCloseButton else { return 0 }
        return UIConstants.Size.actionButton + (UIConstants.Spacing.medium * 2)
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
        let visibleSheetOffset = offset + ((1 - presentationProgress) * containerHeight)
        let visibleSheetProgress = 1 - min(max(visibleSheetOffset / containerHeight, 0), 1)
        let effectiveBackdropProgress = fullScreenSheetClampedProgress(visibleSheetProgress)
        let isFullHeightSheet = sheetTopY <= 0.5
        let backdropRevealHeight = isFullHeightSheet
            ? containerHeight
            : sheetTopY
        let topBlurRevealProgress = resolvedTopBlurRevealProgress(scrollOffset: contentScrollOffset)
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
                rootUpdateKey: hostedContentUpdateKey(contentSafeAreaInsets: contentSafeAreaInsets),
                onScrollOffsetChange: { newOffset in
                    if abs(contentScrollOffset - newOffset) > 0.5 {
                        contentScrollOffset = newOffset
                    }
                },
                makeRootView: {
                    hostedSheetContent(contentSafeAreaInsets: contentSafeAreaInsets)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.fullScreenSheetDragProgress, dragProgress)

            if configuration.showsDefaultTopProgressiveBlur {
                defaultTopProgressiveBlur(
                    contentSafeAreaInsets: contentSafeAreaInsets,
                    revealProgress: topBlurRevealProgress
                )
                .allowsHitTesting(false)
            }

            if configuration.showsCloseButton {
                defaultCloseButton(contentSafeAreaInsets: contentSafeAreaInsets)
            }

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
        .offset(y: visibleSheetOffset)

        let baseView = ZStack(alignment: .bottom) {
            if isFullHeightSheet, configuration.showsBackdropBlur {
                fullScreenBackdropBlurOverlay(revealProgress: effectiveBackdropProgress)
            } else if isFullHeightSheet {
                backgroundView(dragProgress: dragProgress)
                    .opacity(fullScreenSheetRestBackdropOpacity(visibleSheetOffset: visibleSheetOffset))
                    .frame(width: containerWidth, height: containerHeight)
                    .allowsHitTesting(false)
            }

            if !isFullHeightSheet, configuration.showsBackdropBlur && backdropRevealHeight > 0.5 {
                backdropTopBlurOverlay(
                    sheetTopY: backdropRevealHeight,
                    revealProgress: effectiveBackdropProgress
                )
            }

            if !isFullHeightSheet, backdropRevealHeight > 0.5 {
                outsideDismissScrim(
                    sheetTopY: backdropRevealHeight,
                    containerHeight: containerHeight,
                    backdropProgress: effectiveBackdropProgress
                )
            }

            sheetSurface

#if DEBUG
            if developmentPreferences.customSheetTuningEnabled {
                CustomSheetDebugFloatingPanel(
                    settings: Binding(
                        get: { developmentPreferences.customSheetDebugSettings },
                        set: { developmentPreferences.customSheetDebugSettings = $0 }
                    ),
                    onReset: {
                        developmentPreferences.customSheetDebugSettings = .default
                    }
                )
                .padding(.trailing, UIConstants.Spacing.large)
                .padding(.bottom, max(windowSafeAreaInsets.bottom, UIConstants.Spacing.large) + UIConstants.Size.bottomChromeBarHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
#endif
        }
        .frame(width: containerWidth, height: containerHeight, alignment: .bottom)
        .contentShape(.rect)
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
        .onAppear {
            offset = 0
            scrollDisabled = false
            isAnimatingDismiss = false
            presentationProgress = 0
            contentScrollOffset = 0

            Task { @MainActor in
                await Task.yield()
                withAnimation(presentationAnimation) {
                    presentationProgress = 1
                }
            }
        }

        baseView.background {
            SheetPanBridge(
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

    @ViewBuilder
    private func backgroundView(dragProgress: CGFloat) -> some View {
        if configuration.backgroundReceivesDragProgress {
            background
                .environment(\.fullScreenSheetDragProgress, dragProgress)
        } else {
            background
        }
    }

    @ViewBuilder
    private func hostedSheetContent(contentSafeAreaInsets: UIEdgeInsets) -> some View {
        content(contentSafeAreaInsets)
            .environment(
                \.fullScreenSheetTopChromeClearance,
                configuration.showsDefaultTopProgressiveBlur
                    ? resolvedCustomSheetTopChromeClearance(contentSafeAreaInsets: contentSafeAreaInsets)
                    : 0
            )
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private func backdropTopBlurOverlay(
        sheetTopY: CGFloat,
        revealProgress: CGFloat
    ) -> some View {
        TopProgressiveBlurOverlay(
            topHeight: sheetTopY,
            revealProgress: fullScreenSheetClampedProgress(revealProgress),
            tintColor: Color(ThemeColorToken.backgroundPrimary.assetName),
            configuration: backdropTopBlurConfiguration,
            revealAnimation: nil
        )
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func fullScreenBackdropBlurOverlay(revealProgress: CGFloat) -> some View {
        ZStack {
            BackgroundBlurView(radius: resolvedCustomSheetSettings.backdropBlurRadius)
                .ignoresSafeArea()

            Color.black
                .opacity(colorScheme == .dark ? 0.38 : 0.22)
                .ignoresSafeArea()
        }
        .opacity(Double(fullScreenSheetClampedProgress(revealProgress)))
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fullScreenSheetRestBackdropOpacity(visibleSheetOffset: CGFloat) -> Double {
        let fadeDistance = max(windowSize.height * 0.12, 72)
        let progress = min(max(visibleSheetOffset / fadeDistance, 0), 1)
        return Double(1 - progress)
    }

    private func defaultCloseButton(contentSafeAreaInsets: UIEdgeInsets) -> some View {
        ChromeSoftCircleSymbolButton(
            systemName: "xmark",
            accessibilityLabel: localized("Close"),
            action: { animateDismiss(containerHeight: max(windowSize.height, 1)) },
            symbolSize: UIConstants.Size.iconStandard
        )
        .padding(.top, contentSafeAreaInsets.top + UIConstants.Spacing.medium)
        .padding(.trailing, UIConstants.Spacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func defaultDragTopOverlay(dragProgress: CGFloat) -> some View {
        topOverlayTint
            .opacity(topOverlayOpacity(for: dragProgress))
            .mask(topOverlayMask)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func defaultTopProgressiveBlur(
        contentSafeAreaInsets: UIEdgeInsets,
        revealProgress: CGFloat
    ) -> some View {
        TopProgressiveBlurOverlay(
            topHeight: defaultTopProgressiveBlurHeight(contentSafeAreaInsets: contentSafeAreaInsets),
            revealProgress: revealProgress,
            tintColor: Color(ThemeColorToken.backgroundPrimary.assetName),
            configuration: defaultSheetTopBlurConfiguration
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func outsideDismissScrim(
        sheetTopY: CGFloat,
        containerHeight: CGFloat,
        backdropProgress: CGFloat
    ) -> some View {
        ZStack(alignment: .top) {
            Color.black
                .opacity(outsideDismissScrimOpacity(sheetTopY: sheetTopY, containerHeight: containerHeight) * backdropProgress)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            BackdropDismissTouchShield {
                animateDismiss(containerHeight: containerHeight)
            }
            .frame(maxWidth: .infinity)
            .frame(height: min(sheetTopY, containerHeight), alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        onDismissStart()

        withAnimation(dismissalAnimation) {
            offset = containerHeight
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(animationDurationMilliseconds))
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) { onDismiss() }
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

    private func defaultTopProgressiveBlurHeight(
        contentSafeAreaInsets: UIEdgeInsets
    ) -> CGFloat {
        return max(
            contentSafeAreaInsets.top + resolvedCustomSheetSettings.blurAreaHeight,
            1
        )
    }

    private func resolvedCustomSheetTopChromeClearance(
        contentSafeAreaInsets: UIEdgeInsets
    ) -> CGFloat {
        max(
            resolvedCustomSheetSettings.contentTopInset,
            0
        )
    }

    private func resolvedTopBlurRevealProgress(scrollOffset: CGFloat) -> CGFloat {
        guard configuration.showsDefaultTopProgressiveBlur else { return 0 }
        let revealDistance = max(resolvedCustomSheetSettings.topBlurRevealDistance, 1)
        let normalized = min(max(scrollOffset / revealDistance, 0), 1)
        return smoothStep(normalized)
    }

    private var defaultSheetTopBlurConfiguration: ScreenTopProgressiveBlurConfiguration {
        ScreenTopProgressiveBlurConfiguration(
            maxBlurRadius: resolvedCustomSheetSettings.blurRadius,
            fadeExtension: resolvedCustomSheetSettings.blurFadeExtension,
            tintOpacityTop: Double(resolvedCustomSheetSettings.blurTintOpacityTop),
            tintOpacityMiddle: Double(resolvedCustomSheetSettings.blurTintOpacityMiddle)
        )
    }

    private var backdropTopBlurConfiguration: ScreenTopProgressiveBlurConfiguration {
        ScreenTopProgressiveBlurConfiguration(
            maxBlurRadius: resolvedCustomSheetSettings.backdropBlurRadius,
            fadeExtension: max(resolvedCustomSheetSettings.blurFadeExtension * 2, UIConstants.Spacing.extraLarge),
            tintOpacityTop: 0,
            tintOpacityMiddle: 0
        )
    }

    private func outsideDismissScrimOpacity(
        sheetTopY: CGFloat,
        containerHeight: CGFloat
    ) -> Double {
        Double(min(max(resolvedCustomSheetSettings.scrimOpacity, 0), 1))
    }

    private var resolvedCustomSheetSettings: CustomSheetDebugSettings {
        developmentPreferences.customSheetDebugSettings
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

    private func smoothStep(_ value: CGFloat) -> CGFloat {
        let x = min(max(value, 0), 1)
        return x * x * x * (x * ((x * 6) - 15) + 10)
    }

    private func hostedContentUpdateKey(
        contentSafeAreaInsets: UIEdgeInsets
    ) -> HostedSheetContentUpdateKey {
        HostedSheetContentUpdateKey(
            topInset: contentSafeAreaInsets.top,
            leftInset: contentSafeAreaInsets.left,
            bottomInset: contentSafeAreaInsets.bottom,
            rightInset: contentSafeAreaInsets.right,
            topChromeClearance: configuration.showsDefaultTopProgressiveBlur
                ? resolvedCustomSheetTopChromeClearance(contentSafeAreaInsets: contentSafeAreaInsets)
                : 0,
            showsDefaultTopProgressiveBlur: configuration.showsDefaultTopProgressiveBlur
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

// MARK: - Backdrop Touch Shield

private struct BackdropDismissTouchShield: UIViewRepresentable {
    let onTap: () -> Void

    func makeUIView(context: Context) -> ShieldView {
        let view = ShieldView()
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: ShieldView, context: Context) {
        uiView.onTap = onTap
    }

    final class ShieldView: UIView, UIGestureRecognizerDelegate {
        var onTap: (() -> Void)?

        private lazy var tapGesture: UITapGestureRecognizer = {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            gesture.delegate = self
            gesture.cancelsTouchesInView = true
            return gesture
        }()

        private lazy var panGesture: UIPanGestureRecognizer = {
            let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
            gesture.delegate = self
            gesture.cancelsTouchesInView = true
            gesture.maximumNumberOfTouches = 1
            return gesture
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isOpaque = false
            isUserInteractionEnabled = true
            addGestureRecognizer(tapGesture)
            addGestureRecognizer(panGesture)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc private func handleTap() {
            onTap?()
        }

        @objc private func handlePan() {
            // Intentionally consume backdrop drags so iOS 17 does not forward them
            // to the presenting screen's ScrollView.
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
}

// MARK: - Stable Hosted Sheet Content

private struct HostedSheetContentUpdateKey: Equatable {
    let topInset: CGFloat
    let leftInset: CGFloat
    let bottomInset: CGFloat
    let rightInset: CGFloat
    let topChromeClearance: CGFloat
    let showsDefaultTopProgressiveBlur: Bool
}

/// Hosts the heavy SwiftUI sheet content inside a persistent `UIHostingController`
/// so drag offset updates on the outer container do not force the entire content
/// tree to be rebuilt every frame.
private struct StableHostedSheetContent<Root: View>: UIViewControllerRepresentable {
    let topCornerRadius: CGFloat
    let interactionDisabled: Bool
    let rootUpdateKey: HostedSheetContentUpdateKey
    let onScrollOffsetChange: (CGFloat) -> Void
    let makeRootView: () -> Root

    func makeUIViewController(context: Context) -> SheetHostingContainerController {
        let controller = SheetHostingContainerController(
            rootView: hostedRootView,
            topCornerRadius: topCornerRadius,
            rootUpdateKey: rootUpdateKey
        )
        controller.setTrackedScrollOffsetHandler(onScrollOffsetChange)
        return controller
    }

    func updateUIViewController(_ uiViewController: SheetHostingContainerController, context: Context) {
        uiViewController.updateTopCornerRadius(topCornerRadius)
        uiViewController.setSheetInteractionDisabled(interactionDisabled)
        uiViewController.setTrackedScrollOffsetHandler(onScrollOffsetChange)
        uiViewController.updateRootView(hostedRootView, rootUpdateKey: rootUpdateKey)
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
    private var rootUpdateKey: HostedSheetContentUpdateKey

    init(
        rootView: AnyView,
        topCornerRadius: CGFloat,
        rootUpdateKey: HostedSheetContentUpdateKey
    ) {
        self.hostingController = SheetHostingController(rootView: rootView)
        self.rootUpdateKey = rootUpdateKey
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

    func updateRootView(_ rootView: AnyView, rootUpdateKey: HostedSheetContentUpdateKey) {
        guard self.rootUpdateKey != rootUpdateKey else { return }
        self.rootUpdateKey = rootUpdateKey
        hostingController.rootView = rootView
    }

    func setTrackedScrollOffsetHandler(_ handler: ((CGFloat) -> Void)?) {
        hostingController.setTrackedScrollOffsetHandler(handler)
    }
}

private final class SheetHostingController: UIHostingController<AnyView> {
    private struct ScrollState {
        let bounces: Bool
        let alwaysBounceVertical: Bool
    }

    private var preservedScrollStates: [ObjectIdentifier: ScrollState] = [:]
    private var isSheetInteractionDisabled = false
    private weak var trackedScrollView: UIScrollView?
    private var trackedScrollOffsetObservation: NSKeyValueObservation?
    private var trackedScrollOffsetHandler: ((CGFloat) -> Void)?
    private var lastReportedTrackedScrollOffset: CGFloat = -.greatestFiniteMagnitude

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTrackedScrollViewIfNeeded()
    }

    func setSheetInteractionDisabled(_ disabled: Bool) {
        guard disabled != isSheetInteractionDisabled else { return }
        isSheetInteractionDisabled = disabled

        if disabled {
            freezeNestedScrollViews()
        } else {
            restoreNestedScrollViews()
        }
    }

    func setTrackedScrollOffsetHandler(_ handler: ((CGFloat) -> Void)?) {
        trackedScrollOffsetHandler = handler
        updateTrackedScrollViewIfNeeded()

        if let trackedScrollView {
            reportTrackedScrollOffset(from: trackedScrollView)
        } else {
            lastReportedTrackedScrollOffset = 0
            handler?(0)
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

    private func updateTrackedScrollViewIfNeeded() {
        let candidate = nestedVerticalScrollViews(in: view)
            .filter { !$0.isHidden && $0.alpha > 0.01 && $0.bounds.height > 0 }
            .max { lhs, rhs in
                let leftArea = lhs.bounds.width * lhs.bounds.height
                let rightArea = rhs.bounds.width * rhs.bounds.height
                return leftArea < rightArea
            }

        guard candidate !== trackedScrollView else {
            if let trackedScrollView {
                reportTrackedScrollOffset(from: trackedScrollView)
            }
            return
        }

        trackedScrollOffsetObservation = nil
        trackedScrollView = candidate
        lastReportedTrackedScrollOffset = -.greatestFiniteMagnitude

        guard let candidate else {
            trackedScrollOffsetHandler?(0)
            return
        }

        trackedScrollOffsetObservation = candidate.observe(
            \.contentOffset,
            options: [.initial, .new]
        ) { [weak self] scrollView, _ in
            self?.reportTrackedScrollOffset(from: scrollView)
        }
    }

    private func reportTrackedScrollOffset(from scrollView: UIScrollView) {
        let offset = max(scrollView.contentOffset.y + scrollView.adjustedContentInset.top, 0)
        guard abs(offset - lastReportedTrackedScrollOffset) > 0.5 else { return }
        lastReportedTrackedScrollOffset = offset

        guard let trackedScrollOffsetHandler else { return }
        DispatchQueue.main.async {
            trackedScrollOffsetHandler(offset)
        }
    }
}

// MARK: - Sheet Pan Bridge

private struct SheetPanBridge: UIViewRepresentable {
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

            return fullScreenSheetHasDownwardDismissIntent(pan, in: host)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                let host = hostView else { return false }

            guard fullScreenSheetHasDownwardDismissIntent(pan, in: host) else { return false }

            var scrollOffset: CGFloat = 0
            if let collectionView = otherGestureRecognizer.view as? UICollectionView {
                scrollOffset = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
            } else if let scrollView = otherGestureRecognizer.view as? UIScrollView {
                scrollOffset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            }
            return Int(scrollOffset) <= 1
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

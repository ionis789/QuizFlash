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
    private let handler: ((() -> Void)?) -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = { completion in
            handler()
            completion?()
        }
    }

    init(_ handler: @escaping (((() -> Void)?) -> Void)) {
        self.handler = handler
    }

    func callAsFunction() {
        handler(nil)
    }

    func callAsFunction(completion: @escaping () -> Void) {
        handler(completion)
    }
}

// MARK: - Environment Values

private struct FullScreenSheetDismissActionKey: EnvironmentKey {
    static let defaultValue: FullScreenSheetDismissAction? = nil
}

private struct FullScreenSheetDismissCoordinatorKey: EnvironmentKey {
    static let defaultValue: FullScreenSheetDismissCoordinator? = nil
}

private struct FullScreenSheetPresentationCoordinatorKey: EnvironmentKey {
    static let defaultValue: FullScreenSheetPresentationCoordinator? = nil
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

    fileprivate var fullScreenSheetPresentationCoordinator: FullScreenSheetPresentationCoordinator? {
        get { self[FullScreenSheetPresentationCoordinatorKey.self] }
        set { self[FullScreenSheetPresentationCoordinatorKey.self] = newValue }
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
    var onBlockedDismiss: (() -> Void)?
}

@MainActor
private final class FullScreenSheetPresentationCoordinator {
    var childPresentationHandler: ((UUID, Bool) -> Void)?

    func setChildPresentationActive(_ id: UUID, _ isActive: Bool) {
        childPresentationHandler?(id, isActive)
    }
}

// MARK: - Sheet Configuration

/// Available presentation heights for the shared QuizFlash sheet surface.
enum FullScreenSheetHeightMode: Sendable {
    case fullScreen
    case medium
    case small
    case custom(CGFloat)
    case absolute(CGFloat)
    case adaptiveAbsolute(CGFloat, maxFraction: CGFloat)
    case safeAreaAbsolute(CGFloat, maxFraction: CGFloat)

    fileprivate func resolvedHeight(
        in containerHeight: CGFloat,
        bottomSafeAreaInset: CGFloat = 0
    ) -> CGFloat {
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
        case .absolute(let value):
            return min(max(value, containerHeight * 0.22), containerHeight * 0.82)
        case .adaptiveAbsolute(let value, let maxFraction):
            let resolvedMaxFraction = min(max(maxFraction, 0.22), 1)
            return min(max(value, containerHeight * 0.22), containerHeight * resolvedMaxFraction)
        case .safeAreaAbsolute(let value, let maxFraction):
            let resolvedMaxFraction = min(max(maxFraction, 0.22), 1)
            let heightWithSafeArea = max(value, 1) + max(bottomSafeAreaInset, 0)
            return min(heightWithSafeArea, containerHeight * resolvedMaxFraction)
        }

        return max(containerHeight * fraction, 1)
    }

    fileprivate var alignsToWindowBottom: Bool {
        if case .safeAreaAbsolute = self {
            return true
        }
        return false
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
    var avoidsKeyboard: Bool = false
    var appliesDefaultDragTopOverlay: Bool = false
    var hidesTabBar: Bool = true
    var coversTabBar: Bool = false
    var debugIdentifier: String? = nil

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
        avoidsKeyboard: Bool = false,
        hidesTabBar: Bool = true,
        coversTabBar: Bool = false,
        debugIdentifier: String? = nil
    ) -> FullScreenSheetConfiguration {
        var configuration = FullScreenSheetConfiguration(
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
            avoidsKeyboard: avoidsKeyboard,
            appliesDefaultDragTopOverlay: false,
            hidesTabBar: hidesTabBar,
            coversTabBar: coversTabBar
        )
        configuration.debugIdentifier = debugIdentifier
        return configuration
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
        avoidsKeyboard: Bool = false,
        hidesTabBar: Bool = true,
        coversTabBar: Bool = false,
        debugIdentifier: String? = nil
    ) -> FullScreenSheetConfiguration {
        var configuration = FullScreenSheetConfiguration(
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
            avoidsKeyboard: avoidsKeyboard,
            appliesDefaultDragTopOverlay: false,
            hidesTabBar: hidesTabBar,
            coversTabBar: coversTabBar
        )
        configuration.debugIdentifier = debugIdentifier
        return configuration
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

private struct FullScreenSheetWindowMetrics {
    let size: CGSize
    let safeAreaInsets: UIEdgeInsets

    var isUsable: Bool {
        size.width > 10 && size.height > 10
    }
}

#if DEBUG
private struct FullScreenSheetDebugMetrics: Equatable {
    let identifier: String?
    let containerWidth: CGFloat
    let containerHeight: CGFloat
    let sheetHeight: CGFloat
    let sheetTopY: CGFloat
    let sheetRestBottomY: CGFloat
    let sheetVisualBottomY: CGFloat
    let visibleSheetOffset: CGFloat
    let presentationProgress: CGFloat
    let contentSafeTop: CGFloat
    let contentSafeBottom: CGFloat
    let windowSafeBottom: CGFloat
    let keyboardInset: CGFloat
    let sheetBottomOverscan: CGFloat
    let contentScrollOffset: CGFloat
    let hasActiveChildPresentation: Bool

    var summary: String {
        [
            "container=\(format(containerWidth))x\(format(containerHeight))",
            "sheetHeight=\(format(sheetHeight))",
            "sheetTopY=\(format(sheetTopY))",
            "restBottomY=\(format(sheetRestBottomY))",
            "visualBottomY=\(format(sheetVisualBottomY))",
            "visibleOffset=\(format(visibleSheetOffset))",
            "progress=\(format(presentationProgress))",
            "safeTop=\(format(contentSafeTop))",
            "safeBottom=\(format(contentSafeBottom))",
            "windowSafeBottom=\(format(windowSafeBottom))",
            "keyboardInset=\(format(keyboardInset))",
            "overscan=\(format(sheetBottomOverscan))",
            "scrollOffset=\(format(contentScrollOffset))",
            "hasChild=\(hasActiveChildPresentation)"
        ].joined(separator: " ")
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }
}

private struct FullScreenSheetDebugProbe: View {
    let metrics: FullScreenSheetDebugMetrics

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onAppear {
                fullScreenSheetDebugLog(metrics.identifier, "metrics.appear \(metrics.summary)")
            }
            .onChange(of: metrics) { oldMetrics, newMetrics in
                guard oldMetrics.summary != newMetrics.summary else { return }
                fullScreenSheetDebugLog(newMetrics.identifier, "metrics.change \(newMetrics.summary)")
            }
    }
}

private func fullScreenSheetDebugLog(_ identifier: String?, _ message: String) {
    guard let identifier else { return }
    print("AUTH_LAYOUT_DEBUG \(debugTimestamp()) sheet=\(identifier) \(message)")
}

private func debugTimestamp() -> String {
    String(format: "%.3f", Date().timeIntervalSince1970)
}

private func debugFrame(_ frame: CGRect) -> String {
    "x=\(debugFormat(frame.minX)),y=\(debugFormat(frame.minY)),w=\(debugFormat(frame.width)),h=\(debugFormat(frame.height))"
}

private func debugSize(_ size: CGSize) -> String {
    "w=\(debugFormat(size.width)),h=\(debugFormat(size.height))"
}

private func debugTransformSummary(for view: UIView) -> String {
    var parts: [String] = []
    var current: UIView? = view

    while let candidate = current, !(candidate is UIWindow), parts.count < 4 {
        let transform = candidate.transform
        let layer = candidate.layer
        let presentationFrame = layer.presentation()?.frame ?? .null
        parts.append(
            [
                "\(String(describing: type(of: candidate))){",
                "frame=\(debugFrame(candidate.frame))",
                "bounds=\(debugFrame(candidate.bounds))",
                "presentation=\(debugFrame(presentationFrame))",
                "affine=\(debugAffineTransform(transform))",
                "layer=\(debugLayerTransform(layer.transform))"
            ].joined(separator: " ")
            + "}"
        )
        current = candidate.superview
    }

    return "transforms=[" + parts.joined(separator: " -> ") + "]"
}

private func debugAffineTransform(_ transform: CGAffineTransform) -> String {
    [
        "a=\(debugFormat(transform.a))",
        "b=\(debugFormat(transform.b))",
        "c=\(debugFormat(transform.c))",
        "d=\(debugFormat(transform.d))",
        "tx=\(debugFormat(transform.tx))",
        "ty=\(debugFormat(transform.ty))"
    ].joined(separator: ",")
}

private func debugLayerTransform(_ transform: CATransform3D) -> String {
    [
        "m11=\(debugFormat(transform.m11))",
        "m22=\(debugFormat(transform.m22))",
        "m41=\(debugFormat(transform.m41))",
        "m42=\(debugFormat(transform.m42))"
    ].joined(separator: ",")
}

private func debugFormat(_ value: CGFloat) -> String {
    String(format: "%.2f", value)
}
#endif

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

    @State private var tabBarVisibilityRequestID = UUID()
    @State private var presentationID = UUID()
    @State private var isSheetMounted = false
    @State private var externalDismissRequestID = UUID()
    @Environment(\.tabBarSheetVisibilityAction) private var tabBarSheetVisibilityAction
    @Environment(\.fullScreenSheetPresentationCoordinator) private var parentPresentationCoordinator

    private var requiresModalCover: Bool {
        configuration.coversTabBar && !configuration.hidesTabBar
    }

    @ViewBuilder
    func body(content presenterContent: Content) -> some View {
        if requiresModalCover {
            presenterContent
                .onAppear(perform: syncMountedPresentation)
                .onChange(of: isPresented) { _, _ in
                    syncMountedPresentation()
                }
                .fullScreenCover(isPresented: mountedPresentationBinding) {
                    presentedSheet
                        .presentationBackground(.clear)
                        .interactiveDismissDisabled(true)
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                }
        } else {
            presenterContent
                .onAppear(perform: syncMountedPresentation)
                .onChange(of: isPresented) { _, _ in
                    syncMountedPresentation()
                }
                .overlay(alignment: .bottom) {
                    if isSheetMounted {
                        presentedSheet
                            .ignoresSafeArea(.container, edges: configuration.ignoresSafeArea ? .all : [])
                            .ignoresSafeArea(.keyboard, edges: .bottom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .transition(.identity)
                            .zIndex(1)
                    }
                }
        }
    }

    private var presentedSheet: some View {
        FullScreenSheetContainer<SheetContent, SheetBackground>(
            configuration: configuration,
            externalDismissRequestID: externalDismissRequestID,
            onDismissStart: {
                updateSheetTabBarHidden(false)
            },
            onDismiss: {
                withTransaction(fullScreenSheetPresentationTransaction()) {
                    isSheetMounted = false
                    isPresented = false
                }
            },
            content: sheetContent,
            background: background
        )
        .ignoresSafeArea(.container, edges: configuration.ignoresSafeArea ? .all : [])
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear {
            parentPresentationCoordinator?.setChildPresentationActive(presentationID, true)
            updateSheetTabBarHidden(configuration.hidesTabBar)
        }
        .onDisappear {
            if configuration.debugIdentifier == "auth.primary" {
                AuthFlowDebugTrace.record(
                    "presented-sheet.disappear.begin",
                    layer: "full-screen-sheet"
                )
            }
            parentPresentationCoordinator?.setChildPresentationActive(presentationID, false)
            updateSheetTabBarHidden(false)
            if configuration.debugIdentifier == "auth.primary" {
                AuthFlowDebugTrace.record(
                    "presented-sheet.disappear.end",
                    layer: "full-screen-sheet"
                )
            }
        }
    }

    private var mountedPresentationBinding: Binding<Bool> {
        Binding(
            get: { isSheetMounted },
            set: { newValue in
                if newValue {
                    isSheetMounted = true
                } else {
                    requestAnimatedExternalDismiss()
                }
            }
        )
    }

    private func syncMountedPresentation() {
        if isPresented {
            isSheetMounted = true
        } else if isSheetMounted {
            requestAnimatedExternalDismiss()
        }
    }

    private func requestAnimatedExternalDismiss() {
        guard isSheetMounted else { return }
        externalDismissRequestID = UUID()
    }

    private func updateSheetTabBarHidden(_ isHidden: Bool) {
        guard configuration.hidesTabBar else { return }
        tabBarSheetVisibilityAction.setHidden(isHidden, for: tabBarVisibilityRequestID)
        if !isHidden {
            tabBarVisibilityRequestID = UUID()
        }
    }
}

private struct FullScreenSheetItemOverlayModifier<Item: Identifiable, SheetContent: View, SheetBackground: View>: ViewModifier {
    @Binding var item: Item?
    let configuration: FullScreenSheetConfiguration
    @ViewBuilder var sheetContent: (Item, UIEdgeInsets) -> SheetContent
    @ViewBuilder var background: () -> SheetBackground

    @State private var tabBarVisibilityRequestID = UUID()
    @State private var presentationID = UUID()
    @State private var mountedItem: Item?
    @State private var externalDismissRequestID = UUID()
    @Environment(\.tabBarSheetVisibilityAction) private var tabBarSheetVisibilityAction
    @Environment(\.fullScreenSheetPresentationCoordinator) private var parentPresentationCoordinator

    private var requiresModalCover: Bool {
        configuration.coversTabBar && !configuration.hidesTabBar
    }

    @ViewBuilder
    func body(content presenterContent: Content) -> some View {
        if requiresModalCover {
            presenterContent
                .onAppear(perform: syncMountedPresentation)
                .onChange(of: item?.id) { _, _ in
                    syncMountedPresentation()
                }
                .fullScreenCover(item: mountedItemBinding) { wrappedItem in
                    presentedSheet(for: wrappedItem)
                        .presentationBackground(.clear)
                        .interactiveDismissDisabled(true)
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                }
        } else {
            presenterContent
                .onAppear(perform: syncMountedPresentation)
                .onChange(of: item?.id) { _, _ in
                    syncMountedPresentation()
                }
                .overlay(alignment: .bottom) {
                    if let wrappedItem = item ?? mountedItem {
                        presentedSheet(for: wrappedItem)
                            .ignoresSafeArea(.container, edges: configuration.ignoresSafeArea ? .all : [])
                            .ignoresSafeArea(.keyboard, edges: .bottom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .transition(.identity)
                            .zIndex(1)
                    }
                }
        }
    }

    private func presentedSheet(for wrappedItem: Item) -> some View {
        FullScreenSheetContainer<SheetContent, SheetBackground>(
            configuration: configuration,
            externalDismissRequestID: externalDismissRequestID,
            onDismissStart: {
                updateSheetTabBarHidden(false)
            },
            onDismiss: {
                withTransaction(fullScreenSheetPresentationTransaction()) {
                    mountedItem = nil
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
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear {
            parentPresentationCoordinator?.setChildPresentationActive(presentationID, true)
            updateSheetTabBarHidden(configuration.hidesTabBar)
        }
        .onDisappear {
            parentPresentationCoordinator?.setChildPresentationActive(presentationID, false)
            updateSheetTabBarHidden(false)
        }
    }

    private var mountedItemBinding: Binding<Item?> {
        Binding(
            get: { item ?? mountedItem },
            set: { newValue in
                if let newValue {
                    mountedItem = newValue
                } else {
                    requestAnimatedExternalDismiss()
                }
            }
        )
    }

    private func syncMountedPresentation() {
        if let item {
            mountedItem = item
        } else if mountedItem != nil {
            requestAnimatedExternalDismiss()
        }
    }

    private func requestAnimatedExternalDismiss() {
        guard mountedItem != nil else { return }
        externalDismissRequestID = UUID()
    }

    private func updateSheetTabBarHidden(_ isHidden: Bool) {
        guard configuration.hidesTabBar else { return }
        tabBarSheetVisibilityAction.setHidden(isHidden, for: tabBarVisibilityRequestID)
        if !isHidden {
            tabBarVisibilityRequestID = UUID()
        }
    }
}

// MARK: - Full Screen Sheet Container

private struct FullScreenSheetContainer<Content: View, Background: View>: View {
    let configuration: FullScreenSheetConfiguration
    let externalDismissRequestID: UUID
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
    @State private var isHostedContentLaidOut = false
    @State private var hasStartedPresentationAnimation = false
    @State private var dismissCoordinator = FullScreenSheetDismissCoordinator()
    @State private var childPresentationCoordinator = FullScreenSheetPresentationCoordinator()
    @State private var activeChildPresentationIDs: Set<UUID> = []
    @State private var keyboardMonitor = KeyboardMonitor.shared
    @State private var stableWindowMetrics: FullScreenSheetWindowMetrics?

    private var dismissalAnimation: Animation {
        .smooth(duration: UIConstants.Animation.medium * 1.05, extraBounce: 0)
    }

    private var presentationAnimation: Animation {
        .smooth(duration: UIConstants.Animation.medium * 1.05, extraBounce: 0)
    }

    private var keyboardAvoidanceAnimation: Animation {
        .easeInOut(duration: max(keyboardMonitor.animationDuration, UIConstants.Animation.instant))
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
        let keyboardInset = resolvedKeyboardInset(containerHeight: containerHeight)
        let availableContainerHeight = max(containerHeight - keyboardInset, 1)
        let contentBottomSafeArea = keyboardInset > 0 ? 0 : windowSafeAreaInsets.bottom
        let visibleSheetHeight = configuration.heightMode.resolvedHeight(
            in: availableContainerHeight,
            bottomSafeAreaInset: contentBottomSafeArea
        )
        let sheetHeight = min(visibleSheetHeight + keyboardInset, containerHeight)
        let sheetTopY = max(containerHeight - sheetHeight, 0)
        let isFullHeightSheet = sheetTopY <= 0.5
        let dismissalDistance = isFullHeightSheet ? containerHeight : sheetHeight
        let progressDistance = isAnimatingDismiss ? dismissalDistance : containerHeight
        let sheetBottomOverscan = isFullHeightSheet
            || keyboardInset > 0
            || configuration.heightMode.alignsToWindowBottom
            ? 0
            : max(windowSafeAreaInsets.bottom, UIConstants.Size.bottomChromeBarHeight)
        let sheetBottomAlignmentOffset = configuration.ignoresSafeArea
            && configuration.heightMode.alignsToWindowBottom
            ? windowSafeAreaInsets.bottom
            : 0
        let contentSafeAreaInsets = resolvedContentSafeAreaInsets(
            sheetTopY: sheetTopY,
            additionalTopInset: dragIndicatorInset,
            keyboardInset: keyboardInset
        )
        let dragProgress = min(max(offset / max(dismissalDistance, 1), 0), 1)
        let visibleSheetOffset = offset + ((1 - presentationProgress) * containerHeight)
        let visibleSheetProgress = 1 - min(max(visibleSheetOffset / max(progressDistance, 1), 0), 1)
        let effectiveBackdropProgress = fullScreenSheetClampedProgress(visibleSheetProgress)
        let topBlurRevealProgress = resolvedTopBlurRevealProgress(scrollOffset: contentScrollOffset)
        let topChromeDragHeight = resolvedTopChromeDragHeight(contentSafeAreaInsets: contentSafeAreaInsets)
        let hasActiveChildPresentation = !activeChildPresentationIDs.isEmpty
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
                .clipShape(sheetShape)

            if configuration.appliesDefaultDragTopOverlay {
                defaultDragTopOverlay(dragProgress: dragProgress)
                    .clipShape(sheetShape)
                    .allowsHitTesting(false)
            }

            StableHostedSheetContent(
                topCornerRadius: configuration.topCornerRadius,
                interactionDisabled: scrollDisabled,
                rootUpdateKey: hostedContentUpdateKey(contentSafeAreaInsets: contentSafeAreaInsets),
                debugIdentifier: configuration.debugIdentifier,
                onScrollOffsetChange: { newOffset in
                    if abs(contentScrollOffset - newOffset) > 0.5 {
                        contentScrollOffset = newOffset
                    }
                },
                onStableLayout: {
                    isHostedContentLaidOut = true
                },
                makeRootView: {
                    hostedSheetContent(contentSafeAreaInsets: contentSafeAreaInsets)
                }
            )
            .frame(width: containerWidth, height: visibleSheetHeight, alignment: .top)
            .opacity(Double(effectiveBackdropProgress))
            .animation(presentationAnimation, value: presentationProgress)
            .environment(\.fullScreenSheetDragProgress, dragProgress)

            if configuration.showsDefaultTopProgressiveBlur {
                defaultTopProgressiveBlur(
                    contentSafeAreaInsets: contentSafeAreaInsets,
                    revealProgress: topBlurRevealProgress
                )
                .clipShape(sheetShape)
                .allowsHitTesting(false)
            }

            if configuration.showsCloseButton {
                defaultCloseButton(
                    contentSafeAreaInsets: contentSafeAreaInsets,
                    dismissalDistance: dismissalDistance
                )
            }

            if configuration.showsDragIndicator {
                Capsule()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.32))
                    .frame(width: dragIndicatorWidth, height: dragIndicatorHeight)
                    .padding(.top, dragIndicatorTopPadding)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: containerWidth, height: sheetHeight, alignment: .topLeading)
        .animation(keyboardAvoidanceAnimation, value: keyboardInset)
        .background(alignment: .bottom) {
            if sheetBottomOverscan > 0 {
                backgroundView(dragProgress: dragProgress)
                    .frame(width: containerWidth, height: sheetBottomOverscan)
                    .offset(y: sheetBottomOverscan)
                    .allowsHitTesting(false)
            }
        }
        .offset(y: visibleSheetOffset)
        .offset(y: sheetBottomAlignmentOffset)

        let baseView = ZStack(alignment: .bottom) {
            if isFullHeightSheet, configuration.showsBackdropBlur {
                fullScreenBackdropBlurOverlay(revealProgress: effectiveBackdropProgress)
            } else if isFullHeightSheet {
                backgroundView(dragProgress: dragProgress)
                    .opacity(fullScreenSheetRestBackdropOpacity(visibleSheetOffset: visibleSheetOffset))
                    .frame(width: containerWidth, height: containerHeight)
                    .allowsHitTesting(false)
            }

            if !isFullHeightSheet, configuration.showsBackdropBlur {
                fullScreenBackdropBlurOverlay(
                    revealProgress: effectiveBackdropProgress,
                    includesDimOverlay: false
                )
            }

            if !isFullHeightSheet, sheetTopY > 0.5 {
                outsideDismissScrim(
                    sheetTopY: sheetTopY,
                    containerHeight: containerHeight,
                    dismissalDistance: dismissalDistance,
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
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environment(
            \.fullScreenSheetDismiss,
            FullScreenSheetDismissAction { completion in
                animateDismiss(
                    dismissalDistance: dismissalDistance,
                    completion: completion
                )
            }
        )
        .environment(\.fullScreenSheetDismissCoordinator, dismissCoordinator)
        .environment(\.fullScreenSheetPresentationCoordinator, childPresentationCoordinator)
        .onPreferenceChange(FullScreenSheetDragActivationHeightPreferenceKey.self) {
            preferredDragActivationHeight = $0
        }
#if DEBUG
        .background {
            if let debugIdentifier = configuration.debugIdentifier {
                FullScreenSheetDebugProbe(
                    metrics: FullScreenSheetDebugMetrics(
                        identifier: debugIdentifier,
                        containerWidth: containerWidth,
                        containerHeight: containerHeight,
                        sheetHeight: sheetHeight,
                        sheetTopY: sheetTopY,
                        sheetRestBottomY: sheetTopY + sheetHeight,
                        sheetVisualBottomY: sheetTopY + sheetHeight + sheetBottomOverscan,
                        visibleSheetOffset: visibleSheetOffset,
                        presentationProgress: presentationProgress,
                        contentSafeTop: contentSafeAreaInsets.top,
                        contentSafeBottom: contentSafeAreaInsets.bottom,
                        windowSafeBottom: windowSafeAreaInsets.bottom,
                        keyboardInset: keyboardInset,
                        sheetBottomOverscan: sheetBottomOverscan,
                        contentScrollOffset: contentScrollOffset,
                        hasActiveChildPresentation: hasActiveChildPresentation
                    )
                )
            }
        }
#endif
        .onAppear {
#if DEBUG
            fullScreenSheetDebugLog(configuration.debugIdentifier, "container.onAppear")
#endif
            captureStableWindowMetricsIfNeeded()
            offset = 0
            scrollDisabled = false
            isAnimatingDismiss = false
            presentationProgress = 0
            contentScrollOffset = 0
            hasStartedPresentationAnimation = false
            childPresentationCoordinator.childPresentationHandler = { id, isActive in
                if isActive {
                    activeChildPresentationIDs.insert(id)
                } else {
                    activeChildPresentationIDs.remove(id)
                }
            }

            Task { @MainActor in
                await Task.yield()
                guard !hasStartedPresentationAnimation else { return }
                guard isHostedContentLaidOut else {
#if DEBUG
                    fullScreenSheetDebugLog(configuration.debugIdentifier, "presentation.waitingForStableLayout")
#endif
                    return
                }
                startPresentationAnimationIfNeeded()
            }
        }
        .onChange(of: isHostedContentLaidOut) { _, isLaidOut in
            guard isLaidOut else { return }
            startPresentationAnimationIfNeeded()
        }
        .onDisappear {
#if DEBUG
            fullScreenSheetDebugLog(configuration.debugIdentifier, "container.onDisappear")
#endif
            if configuration.debugIdentifier == "auth.primary" {
                AuthFlowDebugTrace.record(
                    "container.disappear.begin",
                    layer: "full-screen-sheet"
                )
            }
            childPresentationCoordinator.childPresentationHandler = nil
            activeChildPresentationIDs.removeAll()
            if configuration.debugIdentifier == "auth.primary" {
                AuthFlowDebugTrace.record(
                    "container.disappear.end",
                    layer: "full-screen-sheet"
                )
            }
        }
        .onChange(of: hasActiveChildPresentation) { _, hasActiveChildPresentation in
            guard hasActiveChildPresentation else { return }
            offset = 0
            scrollDisabled = false
        }
        .onChange(of: externalDismissRequestID) { _, _ in
            Task { @MainActor in
                await Task.yield()
                animateDismiss(dismissalDistance: dismissalDistance)
            }
        }

        baseView.background {
            SheetPanBridge(
                isEnabled: !hasActiveChildPresentation,
                sheetTopY: sheetTopY,
                activationHeight: resolvedDragActivationHeight(sheetHeight: sheetHeight),
                alwaysActiveTopHeight: topChromeDragHeight
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
                        dismissalDistance: dismissalDistance
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

    private func startPresentationAnimationIfNeeded() {
        guard !hasStartedPresentationAnimation else { return }
        hasStartedPresentationAnimation = true
#if DEBUG
        fullScreenSheetDebugLog(configuration.debugIdentifier, "presentation.animation.start")
#endif
        Task { @MainActor in
            await Task.yield()
            guard hasStartedPresentationAnimation, !isAnimatingDismiss else { return }
            withAnimation(presentationAnimation) {
                presentationProgress = 1
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

    private func fullScreenBackdropBlurOverlay(
        revealProgress: CGFloat,
        includesDimOverlay: Bool = true
    ) -> some View {
        ZStack {
            BackgroundBlurView(radius: resolvedCustomSheetSettings.backdropBlurRadius)
                .ignoresSafeArea()

            if includesDimOverlay {
                Color.black
                    .opacity(colorScheme == .dark ? 0.38 : 0.22)
                    .ignoresSafeArea()
            }
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

    private func defaultCloseButton(
        contentSafeAreaInsets: UIEdgeInsets,
        dismissalDistance: CGFloat
    ) -> some View {
        ChromeSoftCircleSymbolButton(
            systemName: "xmark",
            accessibilityLabel: localized("Close"),
            action: { animateDismiss(dismissalDistance: dismissalDistance) }
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
        dismissalDistance: CGFloat,
        backdropProgress: CGFloat
    ) -> some View {
        ZStack(alignment: .top) {
            Color.black
                .opacity(outsideDismissScrimOpacity(sheetTopY: sheetTopY, containerHeight: containerHeight) * backdropProgress)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            BackdropDismissTouchShield {
                handleBackdropTap(dismissalDistance: dismissalDistance)
            }
            .frame(maxWidth: .infinity)
            .frame(height: min(sheetTopY, containerHeight), alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Dismiss Logic

    private func handleBackdropTap(dismissalDistance: CGFloat) {
        guard !keyboardMonitor.isVisible else {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
            return
        }

        animateDismiss(dismissalDistance: dismissalDistance)
    }

    private func finalizeDrag(
        translation: CGFloat,
        predictedEnd: CGFloat,
        dismissalDistance: CGFloat,
        completion: (() -> Void)?
    ) {
        if predictedEnd > dismissalDistance * 0.28 {
            animateDismiss(dismissalDistance: dismissalDistance, completion: completion)
        } else {
            withAnimation(dismissalAnimation) { offset = 0 }
            if translation < dismissalDistance * 0.05 {
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
        dismissalDistance: CGFloat,
        completion: (() -> Void)? = nil
    ) {
        guard !isAnimatingDismiss else { return }
        guard dismissCoordinator.shouldAllowDismiss?() ?? true else {
            dismissCoordinator.onBlockedDismiss?()
            withAnimation(dismissalAnimation) { offset = 0 }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(animationDurationMilliseconds))
                scrollDisabled = false
                completion?()
            }
            return
        }
        isAnimatingDismiss = true
        scrollDisabled = true
        onDismissStart()

        withAnimation(dismissalAnimation) {
            offset = dismissalDistance
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

    private func resolvedTopChromeDragHeight(
        contentSafeAreaInsets: UIEdgeInsets
    ) -> CGFloat {
        guard configuration.showsDefaultTopProgressiveBlur else { return 0 }

        return defaultTopProgressiveBlurHeight(contentSafeAreaInsets: contentSafeAreaInsets)
            + max(defaultSheetTopBlurConfiguration.fadeExtension, 0)
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
        return 1
    }

    private var defaultSheetTopBlurConfiguration: ScreenTopProgressiveBlurConfiguration {
        ScreenTopProgressiveBlurConfiguration(
            maxBlurRadius: resolvedCustomSheetSettings.blurRadius,
            fadeExtension: resolvedCustomSheetSettings.blurFadeExtension,
            tintOpacityTop: Double(resolvedCustomSheetSettings.blurTintOpacityTop),
            tintOpacityMiddle: Double(resolvedCustomSheetSettings.blurTintOpacityMiddle)
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
        additionalTopInset: CGFloat,
        keyboardInset: CGFloat
    ) -> UIEdgeInsets {
        UIEdgeInsets(
            top: (sheetTopY <= windowSafeAreaInsets.top + 1 ? windowSafeAreaInsets.top : 0) + additionalTopInset,
            left: windowSafeAreaInsets.left,
            bottom: keyboardInset > 0 ? 0 : windowSafeAreaInsets.bottom,
            right: windowSafeAreaInsets.right
        )
    }

    private func resolvedKeyboardInset(containerHeight: CGFloat) -> CGFloat {
        guard configuration.avoidsKeyboard, keyboardMonitor.isVisible else { return 0 }

        let requestedInset = keyboardMonitor.visibleHeight + windowSafeAreaInsets.bottom
        let maximumInset = max(containerHeight - windowSafeAreaInsets.top - 1, 0)
        return min(max(requestedInset, 0), maximumInset)
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
        stableWindowMetrics?.size ?? liveWindowMetrics.size
    }

    private var windowSafeAreaInsets: UIEdgeInsets {
        stableWindowMetrics?.safeAreaInsets ?? liveWindowMetrics.safeAreaInsets
    }

    private var liveWindowMetrics: FullScreenSheetWindowMetrics {
        if let keyWindow,
           keyWindow.bounds.width > 10,
           keyWindow.bounds.height > 10 {
            return FullScreenSheetWindowMetrics(
                size: keyWindow.bounds.size,
                safeAreaInsets: keyWindow.safeAreaInsets
            )
        }

        return FullScreenSheetWindowMetrics(
            size: activeWindowScene?.coordinateSpace.bounds.size
                ?? activeWindowScene?.screen.bounds.size
                ?? .zero,
            safeAreaInsets: .zero
        )
    }

    private func captureStableWindowMetricsIfNeeded() {
        guard stableWindowMetrics == nil else { return }
        let metrics = liveWindowMetrics
        guard metrics.isUsable else { return }
        stableWindowMetrics = metrics
    }

    private var activeWindowScene: UIWindowScene? {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        return windowScenes.first(where: { $0.activationState == .foregroundActive })
            ?? windowScenes.first(where: { $0.activationState == .foregroundInactive })
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
    let debugIdentifier: String?
    let onScrollOffsetChange: (CGFloat) -> Void
    let onStableLayout: () -> Void
    let makeRootView: () -> Root

    func makeUIViewController(context: Context) -> SheetHostingContainerController {
        let controller = SheetHostingContainerController(
            rootView: hostedRootView,
            topCornerRadius: topCornerRadius,
            rootUpdateKey: rootUpdateKey,
            debugIdentifier: debugIdentifier,
            onStableLayout: onStableLayout
        )
        controller.setTrackedScrollOffsetHandler(onScrollOffsetChange)
        return controller
    }

    func updateUIViewController(_ uiViewController: SheetHostingContainerController, context: Context) {
        uiViewController.updateTopCornerRadius(topCornerRadius)
        uiViewController.setSheetInteractionDisabled(interactionDisabled)
        uiViewController.setTrackedScrollOffsetHandler(onScrollOffsetChange)
        uiViewController.updateRootViewIfNeeded(rootUpdateKey: rootUpdateKey) {
            hostedRootView
        }
    }

    static func dismantleUIViewController(
        _ uiViewController: SheetHostingContainerController,
        coordinator: Void
    ) {
        if uiViewController.traceDebugIdentifier == "auth.primary" {
            AuthFlowDebugTrace.record(
                "hosting-controller.dismantle",
                layer: "full-screen-sheet"
            )
        }
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
                .ignoresSafeArea(.keyboard, edges: .bottom)
        )
    }
}

private final class SheetHostingContainerController: UIViewController {
    private let hostingController: SheetHostingController
    private var rootUpdateKey: HostedSheetContentUpdateKey
    private let debugIdentifier: String?
    var traceDebugIdentifier: String? { debugIdentifier }
    private let onStableLayout: () -> Void
    private var hasReportedStableLayout = false
#if DEBUG
    private var lastLayoutDebugSummary: String?
#endif

    init(
        rootView: AnyView,
        topCornerRadius: CGFloat,
        rootUpdateKey: HostedSheetContentUpdateKey,
        debugIdentifier: String?,
        onStableLayout: @escaping () -> Void
    ) {
        self.hostingController = SheetHostingController(rootView: rootView)
        self.rootUpdateKey = rootUpdateKey
        self.debugIdentifier = debugIdentifier
        self.onStableLayout = onStableLayout
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reportStableLayoutIfNeeded()
#if DEBUG
        let summary = [
            "containerBounds=\(debugFrame(view.bounds))",
            "containerFrame=\(debugFrame(view.frame))",
            "hostFrame=\(debugFrame(hostingController.view.frame))",
            debugTransformSummary(for: view),
            hostingController.debugTrackedScrollSummary()
        ].joined(separator: " ")
        if summary != lastLayoutDebugSummary {
            lastLayoutDebugSummary = summary
            fullScreenSheetDebugLog(debugIdentifier, "hosting.layout \(summary)")
        }
#endif
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

    private func reportStableLayoutIfNeeded() {
        guard !hasReportedStableLayout else { return }
        guard view.window != nil else { return }
        guard view.bounds.width > 1, view.bounds.height > 1 else { return }
        guard abs(hostingController.view.bounds.width - view.bounds.width) <= 0.5,
              abs(hostingController.view.bounds.height - view.bounds.height) <= 0.5 else {
            return
        }
        hasReportedStableLayout = true
        DispatchQueue.main.async { [onStableLayout] in
            onStableLayout()
        }
    }

    func updateRootViewIfNeeded(
        rootUpdateKey: HostedSheetContentUpdateKey,
        makeRootView: () -> AnyView
    ) {
        guard self.rootUpdateKey != rootUpdateKey else { return }
        self.rootUpdateKey = rootUpdateKey
        hostingController.rootView = makeRootView()
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

        if let trackedScrollView {
            reportTrackedScrollOffset(from: trackedScrollView)
        } else {
            updateTrackedScrollViewIfNeeded()
        }

        if trackedScrollView == nil {
            reportTrackedScrollOffset(0)
        }
    }

#if DEBUG
    func debugTrackedScrollSummary() -> String {
        guard let trackedScrollView else {
            return "scrollView=nil"
        }

        return [
            "scrollFrame=\(debugFrame(trackedScrollView.frame))",
            "scrollBounds=\(debugFrame(trackedScrollView.bounds))",
            "contentSize=\(debugSize(trackedScrollView.contentSize))",
            "contentOffsetY=\(debugFormat(trackedScrollView.contentOffset.y))",
            "adjustedInsetTop=\(debugFormat(trackedScrollView.adjustedContentInset.top))",
            "adjustedInsetBottom=\(debugFormat(trackedScrollView.adjustedContentInset.bottom))"
        ].joined(separator: " ")
    }
#endif

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
        if let trackedScrollView,
           trackedScrollView.isDescendant(of: view),
           isEffectivelyVisible(trackedScrollView, within: view),
           trackedScrollView.bounds.height > 0,
           trackedScrollView.contentSize.height > trackedScrollView.bounds.height + 1
               || trackedScrollView.alwaysBounceVertical {
            reportTrackedScrollOffset(from: trackedScrollView)
            return
        }

        let candidate = nestedVerticalScrollViews(in: view)
            .filter { isEffectivelyVisible($0, within: view) && $0.bounds.height > 0 }
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
            reportTrackedScrollOffset(0)
            return
        }

        trackedScrollOffsetObservation = candidate.observe(
            \.contentOffset,
            options: [.initial, .new]
        ) { [weak self] scrollView, _ in
            self?.reportTrackedScrollOffset(from: scrollView)
        }
    }

    private func isEffectivelyVisible(_ candidate: UIView, within root: UIView) -> Bool {
        var current: UIView? = candidate
        while let currentView = current {
            guard !currentView.isHidden, currentView.alpha > 0.01 else { return false }
            if currentView === root { return true }
            current = currentView.superview
        }
        return false
    }

    private func reportTrackedScrollOffset(from scrollView: UIScrollView) {
        let offset = max(scrollView.contentOffset.y + scrollView.adjustedContentInset.top, 0)
        reportTrackedScrollOffset(offset)
    }

    private func reportTrackedScrollOffset(_ offset: CGFloat) {
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
    let isEnabled: Bool
    let sheetTopY: CGFloat
    let activationHeight: CGFloat?
    let alwaysActiveTopHeight: CGFloat
    let onPan: (UIPanGestureRecognizer) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isDismissGestureEnabled = isEnabled
        view.sheetTopY = sheetTopY
        view.activationHeight = activationHeight
        view.alwaysActiveTopHeight = alwaysActiveTopHeight
        view.onPan = onPan
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.isDismissGestureEnabled = isEnabled
        uiView.sheetTopY = sheetTopY
        uiView.activationHeight = activationHeight
        uiView.alwaysActiveTopHeight = alwaysActiveTopHeight
        uiView.onPan = onPan
    }

    final class ProbeView: UIView, UIGestureRecognizerDelegate {
        var sheetTopY: CGFloat = 0
        var activationHeight: CGFloat?
        var alwaysActiveTopHeight: CGFloat = 0
        var onPan: ((UIPanGestureRecognizer) -> Void)?
        var isDismissGestureEnabled = true {
            didSet {
                guard oldValue != isDismissGestureEnabled else { return }
                panGesture.isEnabled = isDismissGestureEnabled
            }
        }

        private weak var hostView: UIView?
        private var panBeganInAlwaysActiveTopArea = false
        private lazy var panGesture: TopChromeSheetPanGestureRecognizer = {
            let gesture = TopChromeSheetPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
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
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                panBeganInAlwaysActiveTopArea = false
                panGesture.beganInAlwaysActiveTopArea = false
            }
            onPan?(gesture)
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isDismissGestureEnabled else { return false }
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                let host = hostView else { return false }

            let location = pan.location(in: host)
            guard location.y >= sheetTopY else { return false }
            let beginsInAlwaysActiveTopArea = isInAlwaysActiveTopArea(locationY: location.y)
            if !beginsInAlwaysActiveTopArea,
               let activationHeight,
               location.y > sheetTopY + activationHeight {
                return false
            }

            let hasDismissIntent = fullScreenSheetHasDownwardDismissIntent(pan, in: host)
            panBeganInAlwaysActiveTopArea = beginsInAlwaysActiveTopArea && hasDismissIntent
            panGesture.beganInAlwaysActiveTopArea = panBeganInAlwaysActiveTopArea
            return hasDismissIntent
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                let host = hostView else { return false }

            guard fullScreenSheetHasDownwardDismissIntent(pan, in: host) else { return false }

            if panBeganInAlwaysActiveTopArea {
                return false
            }

            var scrollOffset: CGFloat = 0
            if let collectionView = otherGestureRecognizer.view as? UICollectionView {
                scrollOffset = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
            } else if let scrollView = otherGestureRecognizer.view as? UIScrollView {
                scrollOffset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            }
            return Int(scrollOffset) <= 1
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        private func isInAlwaysActiveTopArea(locationY: CGFloat) -> Bool {
            alwaysActiveTopHeight > 0 &&
            locationY >= sheetTopY &&
            locationY <= sheetTopY + alwaysActiveTopHeight
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

    final class TopChromeSheetPanGestureRecognizer: UIPanGestureRecognizer {
        var beganInAlwaysActiveTopArea = false

        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
            if beganInAlwaysActiveTopArea,
               preventingGestureRecognizer.view is UIScrollView {
                return false
            }
            return super.canBePrevented(by: preventingGestureRecognizer)
        }
    }
}

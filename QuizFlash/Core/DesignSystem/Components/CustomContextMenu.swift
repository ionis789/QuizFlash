//
//  CustomContextMenu.swift
//  QuizFlash
//
//  Lightweight reusable custom context-menu infrastructure.
//

import SwiftUI
import UIKit

// MARK: - Action Model

/// Semantic role for one custom context-menu action.
enum CustomContextMenuActionRole {
    case normal
    case destructive
}

/// One row rendered inside the custom context-menu card.
struct CustomContextMenuAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let role: CustomContextMenuActionRole
    let action: @MainActor () -> Void
}

// MARK: - Config

/// Visual and interaction tuning for the reusable custom context-menu system.
struct CustomContextMenuConfig {
    var longPressDuration: Double = 0.42
    var allowableMovement: CGFloat = 16
    var menuGap: CGFloat = 16
    var horizontalPadding: CGFloat = 12
    var bottomPadding: CGFloat = 12
    var bottomReservedSpace: CGFloat = UIConstants.Size.bottomChromeBarHeight
        + UIConstants.Layout.bottomChromeBottomPadding
        + UIConstants.Layout.bottomChromeVisualBottomOffset
        + 16
    var pressScale: CGFloat = 0.95
    var liftOvershootScale: CGFloat = 1.04
    var finalPreviewScale: CGFloat = 1
    var backgroundDimOpacity: Double = 0.20
    var menuInitialScale: CGFloat = 0.94
    var menuRevealDelay: Double = 0.05
    var rowStagger: Double = 0.018
    var menuCornerRadius: CGFloat = 32
    var isLoggingEnabled = true
}

enum CustomContextMenuPhase: Equatable {
    case idle
    case pressing
    case lifting
    case expanded
    case dismissing
}

// MARK: - Placement

/// Placement mode chosen for the context menu relative to the source view.
enum CustomContextMenuPlacementMode {
    case anchoredBelowTrailing
    case pushedUpToFitBelowTrailing
    case pushedDownToClearTopSafeArea
    case adjustedBetweenTopAndBottomConstraints
}

/// Resolved geometry for one active menu presentation.
struct CustomContextMenuResolvedLayout {
    let mode: CustomContextMenuPlacementMode
    let menuFrame: CGRect
    let previewOffset: CGSize
    let debug: DebugPayload

    struct DebugPayload {
        let screenBounds: CGRect
        let safeInsets: UIEdgeInsets
        let safeFrame: CGRect
        let menuSize: CGSize
        let anchoredTrailingX: CGFloat
        let bottomLimitWithReserved: CGFloat
        let bottomLimitWithoutReserved: CGFloat
        let topLimit: CGFloat
        let idealPreviewY: CGFloat
        let idealMenuBottom: CGFloat
        let requiredLiftWithReserved: CGFloat
        let requiredLiftWithoutReserved: CGFloat
        let appliedRequiredLift: CGFloat
        let previewYAfterBottomLift: CGFloat
        let requiredTopPush: CGFloat
        let clampedPreviewOrigin: CGPoint
        let menuOrigin: CGPoint
    }
}

// MARK: - Coordinator

/// Main-actor coordinator that owns the one active custom context-menu presentation.
@MainActor
@Observable
final class CustomContextMenuCoordinator {

    /// Active menu payload rendered by the global host.
    struct Presentation: Identifiable {
        let id = UUID()
        let sourceID: AnyHashable
        let sourceFrame: CGRect
        let preview: AnyView
        let actions: [CustomContextMenuAction]
        let menuSize: CGSize
        let config: CustomContextMenuConfig
        let layout: CustomContextMenuResolvedLayout
    }

    /// Input used to resolve geometry and create a presentation payload.
    struct Request {
        let sourceID: AnyHashable
        let sourceFrame: CGRect
        let preview: AnyView
        let actions: [CustomContextMenuAction]
        let measuredMenuSize: CGSize
        let config: CustomContextMenuConfig
    }

    var presentation: Presentation?
    var phase: CustomContextMenuPhase = .idle

    @ObservationIgnored
    private var dismissTask: Task<Void, Never>?

    @ObservationIgnored
    private var phaseTask: Task<Void, Never>?

    func setIsPressing(_ isPressing: Bool) {
        guard presentation == nil else { return }
        phase = isPressing ? .pressing : .idle
    }

    /// Presents a new context menu and animates it into place.
    func present(_ request: Request) {
        guard request.sourceFrame != .zero else { return }
        guard !request.actions.isEmpty else { return }

        dismissTask?.cancel()
        phaseTask?.cancel()

        let layout = Self.resolveLayout(
            sourceFrame: request.sourceFrame,
            measuredMenuSize: request.measuredMenuSize,
            config: request.config
        )

        Self.logPresentationDebug(request: request, layout: layout)
        Self.emitRevealHaptic()

        presentation = Presentation(
            sourceID: request.sourceID,
            sourceFrame: request.sourceFrame,
            preview: request.preview,
            actions: request.actions,
            menuSize: request.measuredMenuSize,
            config: request.config,
            layout: layout
        )

        phase = .lifting

        let presentationID = presentation?.id
        phaseTask = Task { @MainActor in
            try? await Task.sleep(
                for: .seconds(request.config.menuRevealDelay + 0.28)
            )
            guard !Task.isCancelled else { return }
            guard presentation?.id == presentationID else { return }
            phase = .expanded
        }
    }

    /// Dismisses the active context menu with the shared spring and clears it afterwards.
    func dismiss() {
        dismiss(after: nil)
    }

    /// Dismisses the active menu and then executes one action after the reverse animation.
    func performAction(_ action: @escaping @MainActor () -> Void) {
        dismiss(after: action)
    }

    /// Returns true while the given source view should remain visually hidden in-place.
    func isSourceHidden<ID: Hashable>(_ id: ID) -> Bool {
        guard let presentation else { return false }
        return presentation.sourceID == AnyHashable(id)
    }

    private func dismiss(after action: (@MainActor () -> Void)?) {
        guard presentation != nil else { return }

        dismissTask?.cancel()
        phaseTask?.cancel()

        let presentationID = presentation?.id
        phase = .dismissing

        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            guard presentation?.id == presentationID else { return }
            let pendingAction = action
            presentation = nil
            phase = .idle
            pendingAction?()
        }
    }

    private static func resolveLayout(
        sourceFrame: CGRect,
        measuredMenuSize: CGSize,
        config: CustomContextMenuConfig
    ) -> CustomContextMenuResolvedLayout {
        let windowBounds = currentWindowBounds()
        let safeInsets = currentSafeAreaInsets()
        let safeFrame = windowBounds.inset(by: safeInsets)
        let menuSize = measuredMenuSize == .zero ? CGSize(width: 255, height: 234) : measuredMenuSize

        let anchoredTrailingX = min(
            max(safeFrame.minX + config.horizontalPadding, sourceFrame.maxX - menuSize.width),
            safeFrame.maxX - menuSize.width - config.horizontalPadding
        )

        let bottomLimitWithReserved = safeFrame.maxY - config.bottomReservedSpace
        let bottomLimitWithoutReserved = safeFrame.maxY - config.bottomPadding
        let topLimit = safeFrame.minY
        let idealPreviewY = sourceFrame.minY
        let idealMenuBottom = sourceFrame.maxY + config.menuGap + menuSize.height
        let requiredLiftWithReserved = max(0, idealMenuBottom - bottomLimitWithReserved)
        let requiredLiftWithoutReserved = max(0, idealMenuBottom - bottomLimitWithoutReserved)
        let unconstrainedLift = requiredLiftWithoutReserved
        let maxLiftBeforeTopCollision = max(0, sourceFrame.minY - safeFrame.minY)
        let appliedRequiredLift = min(unconstrainedLift, maxLiftBeforeTopCollision)
        let previewYAfterBottomLift = idealPreviewY - appliedRequiredLift
        let requiredTopPush = max(0, topLimit - previewYAfterBottomLift)

        let clampedPreviewOrigin = CGPoint(
            x: sourceFrame.minX,
            y: previewYAfterBottomLift + requiredTopPush
        )

        let menuOrigin = CGPoint(
            x: anchoredTrailingX,
            y: clampedPreviewOrigin.y + sourceFrame.height + config.menuGap
        )

        let mode: CustomContextMenuPlacementMode
        if appliedRequiredLift > 0, requiredTopPush > 0 {
            mode = .adjustedBetweenTopAndBottomConstraints
        } else if appliedRequiredLift > 0 {
            mode = .pushedUpToFitBelowTrailing
        } else if requiredTopPush > 0 {
            mode = .pushedDownToClearTopSafeArea
        } else {
            mode = .anchoredBelowTrailing
        }

        return CustomContextMenuResolvedLayout(
            mode: mode,
            menuFrame: CGRect(origin: menuOrigin, size: menuSize),
            previewOffset: CGSize(
                width: clampedPreviewOrigin.x - sourceFrame.minX,
                height: clampedPreviewOrigin.y - sourceFrame.minY
            ),
            debug: .init(
                screenBounds: windowBounds,
                safeInsets: safeInsets,
                safeFrame: safeFrame,
                menuSize: menuSize,
                anchoredTrailingX: anchoredTrailingX,
                bottomLimitWithReserved: bottomLimitWithReserved,
                bottomLimitWithoutReserved: bottomLimitWithoutReserved,
                topLimit: topLimit,
                idealPreviewY: idealPreviewY,
                idealMenuBottom: idealMenuBottom,
                requiredLiftWithReserved: requiredLiftWithReserved,
                requiredLiftWithoutReserved: requiredLiftWithoutReserved,
                appliedRequiredLift: appliedRequiredLift,
                previewYAfterBottomLift: previewYAfterBottomLift,
                requiredTopPush: requiredTopPush,
                clampedPreviewOrigin: clampedPreviewOrigin,
                menuOrigin: menuOrigin
            )
        )
    }

    private static func logPresentationDebug(
        request: Request,
        layout: CustomContextMenuResolvedLayout
    ) {
        guard request.config.isLoggingEnabled else { return }
        let d = layout.debug
        let previewFrame = CGRect(origin: d.clampedPreviewOrigin, size: request.sourceFrame.size)
        let message = """
[CustomContextMenu][LayoutDebug]
sourceFrame=(x:\(fmt(request.sourceFrame.minX)), y:\(fmt(request.sourceFrame.minY)), w:\(fmt(request.sourceFrame.width)), h:\(fmt(request.sourceFrame.height)))
screen=(w:\(fmt(d.screenBounds.width)), h:\(fmt(d.screenBounds.height)))
safeInsets=(top:\(fmt(d.safeInsets.top)), left:\(fmt(d.safeInsets.left)), bottom:\(fmt(d.safeInsets.bottom)), right:\(fmt(d.safeInsets.right)))
safeFrame=(x:\(fmt(d.safeFrame.minX)), y:\(fmt(d.safeFrame.minY)), w:\(fmt(d.safeFrame.width)), h:\(fmt(d.safeFrame.height)))
menuSize=(w:\(fmt(d.menuSize.width)), h:\(fmt(d.menuSize.height)))
anchoredTrailingX=\(fmt(d.anchoredTrailingX))
bottomLimitWithReserved=\(fmt(d.bottomLimitWithReserved))
bottomLimitWithoutReserved=\(fmt(d.bottomLimitWithoutReserved))
topLimit=\(fmt(d.topLimit))
idealPreviewY=\(fmt(d.idealPreviewY))
idealMenuBottom=\(fmt(d.idealMenuBottom))
requiredLiftWithReserved=\(fmt(d.requiredLiftWithReserved))
requiredLiftWithoutReserved=\(fmt(d.requiredLiftWithoutReserved))
appliedRequiredLift=\(fmt(d.appliedRequiredLift))
previewYAfterBottomLift=\(fmt(d.previewYAfterBottomLift))
requiredTopPush=\(fmt(d.requiredTopPush))
resolvedMode=\(layout.mode)
previewOrigin=(x:\(fmt(d.clampedPreviewOrigin.x)), y:\(fmt(d.clampedPreviewOrigin.y)))
previewFrame=(x:\(fmt(previewFrame.minX)), y:\(fmt(previewFrame.minY)), w:\(fmt(previewFrame.width)), h:\(fmt(previewFrame.height)))
previewOffset=(dx:\(fmt(layout.previewOffset.width)), dy:\(fmt(layout.previewOffset.height)))
menuOrigin=(x:\(fmt(d.menuOrigin.x)), y:\(fmt(d.menuOrigin.y)))
menuFrame=(x:\(fmt(layout.menuFrame.minX)), y:\(fmt(layout.menuFrame.minY)), w:\(fmt(layout.menuFrame.width)), h:\(fmt(layout.menuFrame.height)))
"""
        debugLog(message)
    }

    private static func fmt(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private static func currentWindowBounds() -> CGRect {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .bounds ?? UIScreen.main.bounds
    }

    private static func currentSafeAreaInsets() -> UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }

    private static func emitRevealHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 1)
    }

    private static func debugLog(_ message: String) {
#if DEBUG
        print(message)
#endif
    }
}

// MARK: - Host

/// Global overlay host that renders the active preview, background, and action card.
struct CustomContextMenuHost: View {
    @Environment(CustomContextMenuCoordinator.self) private var coordinator

    var body: some View {
        if let presentation = coordinator.presentation {
            CustomContextMenuOverlay(
                presentation: presentation,
                phase: coordinator.phase,
                onDismiss: {
                    if presentation.config.isLoggingEnabled {
#if DEBUG
                        print("[CustomContextMenu][Dismiss] reason=backgroundTap")
#endif
                    }
                    coordinator.dismiss()
                },
                onSelect: { action in
                    coordinator.performAction(action.action)
                }
            )
            .zIndex(100)
            .transition(.identity)
        }
    }
}

private struct CustomContextMenuOverlay: View {
    let presentation: CustomContextMenuCoordinator.Presentation
    let phase: CustomContextMenuPhase
    let onDismiss: () -> Void
    let onSelect: (CustomContextMenuAction) -> Void

    @State private var backdropMaterialOpacity = 0.0
    @State private var backdropWashOpacity = 0.0
    @State private var previewScale: CGFloat = 1
    @State private var previewOffset: CGSize = .zero
    @State private var previewShadowOpacity = 0.08
    @State private var previewShadowRadius: CGFloat = 12
    @State private var previewShadowYOffset: CGFloat = 4
    @State private var menuOpacity = 0.0
    @State private var menuScale: CGFloat = 1
    @State private var menuOffsetY: CGFloat = 10
    @State private var revealedActionIDs: Set<UUID> = []
    @State private var liftTask: Task<Void, Never>?
    @State private var rowRevealTask: Task<Void, Never>?
    @State private var dismissAnimationTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            let hostFrame = proxy.frame(in: .global)
            let localSourceFrame = CGRect(
                x: presentation.sourceFrame.minX - hostFrame.minX,
                y: presentation.sourceFrame.minY - hostFrame.minY,
                width: presentation.sourceFrame.width,
                height: presentation.sourceFrame.height
            )
            let localMenuFrame = CGRect(
                x: presentation.layout.menuFrame.minX - hostFrame.minX,
                y: presentation.layout.menuFrame.minY - hostFrame.minY,
                width: presentation.layout.menuFrame.width,
                height: presentation.layout.menuFrame.height
            )

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .opacity(backdropMaterialOpacity)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                Rectangle()
                    .fill(Color.black)
                    .ignoresSafeArea()
                    .opacity(presentation.config.backgroundDimOpacity * backdropWashOpacity)
                    .allowsHitTesting(false)

                presentation.preview
                    .frame(
                        width: localSourceFrame.width,
                        height: localSourceFrame.height,
                        alignment: .topLeading
                    )
                    .scaleEffect(previewScale)
                    .shadow(
                        color: .black.opacity(previewShadowOpacity),
                        radius: previewShadowRadius,
                        y: previewShadowYOffset
                    )
                    .position(
                        x: localSourceFrame.midX,
                        y: localSourceFrame.midY
                    )
                    .offset(
                        x: previewOffset.width,
                        y: previewOffset.height
                    )
                    .allowsHitTesting(false)

                CustomContextMenuMenuCard(
                    actions: presentation.actions,
                    cornerRadius: presentation.config.menuCornerRadius,
                    revealedActionIDs: revealedActionIDs,
                    isInteractive: phase == .expanded
                ) { action in
                    onSelect(action)
                }
                .fixedSize(horizontal: true, vertical: true)
                .position(
                    x: localMenuFrame.midX,
                    y: localMenuFrame.midY
                )
                .opacity(menuOpacity)
                .scaleEffect(menuScale, anchor: .topTrailing)
                .offset(y: menuOffsetY)
                .allowsHitTesting(phase == .expanded)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            prepareInitialState()
            update(for: phase)
        }
        .onChange(of: phase) { _, newPhase in
            update(for: newPhase)
        }
        .onDisappear {
            cancelAnimationTasks()
        }
    }

    private func prepareInitialState() {
        backdropMaterialOpacity = 0
        backdropWashOpacity = 0
        previewScale = presentation.config.pressScale
        previewOffset = .zero
        previewShadowOpacity = 0.08
        previewShadowRadius = 12
        previewShadowYOffset = 4
        menuOpacity = 0
        menuScale = presentation.config.menuInitialScale
        menuOffsetY = 10
        revealedActionIDs = []
    }

    private func update(for phase: CustomContextMenuPhase) {
        switch phase {
        case .idle, .pressing:
            break
        case .lifting:
            runLiftSequence()
        case .expanded:
            break
        case .dismissing:
            runDismissSequence()
        }
    }

    private func runLiftSequence() {
        cancelAnimationTasks()
        prepareInitialState()

        withAnimation(.contextMenuLiftSpring) {
            backdropMaterialOpacity = 1
            backdropWashOpacity = 1
            previewScale = presentation.config.liftOvershootScale
            previewOffset = presentation.layout.previewOffset
            previewShadowOpacity = 0.24
            previewShadowRadius = 28
            previewShadowYOffset = 14
        }

        liftTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            withAnimation(.contextMenuSettleSpring) {
                previewScale = presentation.config.finalPreviewScale
                previewShadowOpacity = 0.18
                previewShadowRadius = 20
                previewShadowYOffset = 10
            }

            try? await Task.sleep(for: .seconds(presentation.config.menuRevealDelay))
            guard !Task.isCancelled else { return }

            withAnimation(.contextMenuMenuSpring) {
                menuOpacity = 1
                menuScale = 1
                menuOffsetY = 0
            }

            rowRevealTask = Task { @MainActor in
                for (index, action) in presentation.actions.enumerated() {
                    if index > 0 {
                        try? await Task.sleep(for: .seconds(presentation.config.rowStagger))
                    }
                    guard !Task.isCancelled else { return }
                    withAnimation(.contextMenuMenuSpring) {
                        _ = revealedActionIDs.insert(action.id)
                    }
                }
            }
        }
    }

    private func runDismissSequence() {
        liftTask?.cancel()
        rowRevealTask?.cancel()
        dismissAnimationTask?.cancel()

        withAnimation(.contextMenuMenuSpring) {
            revealedActionIDs = []
        }

        dismissAnimationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }

            withAnimation(.contextMenuDismissSpring) {
                menuOpacity = 0
                menuScale = presentation.config.menuInitialScale
                menuOffsetY = 10
                backdropMaterialOpacity = 0
                backdropWashOpacity = 0
                previewScale = 1
                previewOffset = .zero
                previewShadowOpacity = 0.08
                previewShadowRadius = 12
                previewShadowYOffset = 4
            }
        }
    }

    private func cancelAnimationTasks() {
        liftTask?.cancel()
        rowRevealTask?.cancel()
        dismissAnimationTask?.cancel()
    }
}

private struct CustomContextMenuInteractiveState: Equatable {
    var isPressing = false
    var didTriggerMenu = false
}

private struct CustomContextMenuPressGesture: ViewModifier {
    let isEnabled: Bool
    let config: CustomContextMenuConfig
    let onSuccess: () -> Void

    @Environment(CustomContextMenuCoordinator.self) private var coordinator
    @State private var interactionState = CustomContextMenuInteractiveState()

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .scaleEffect(
                    interactionState.isPressing && !interactionState.didTriggerMenu
                        ? config.pressScale
                        : 1
                )
                .animation(.contextMenuPressSpring, value: interactionState)
                .onLongPressGesture(
                    minimumDuration: config.longPressDuration,
                    maximumDistance: config.allowableMovement
                ) {
                    interactionState.didTriggerMenu = true
                    interactionState.isPressing = false
                    coordinator.setIsPressing(false)
                    onSuccess()
                } onPressingChanged: { isPressing in
                    if !isPressing {
                        interactionState.didTriggerMenu = false
                    }
                    interactionState.isPressing = isPressing
                    coordinator.setIsPressing(isPressing)
                }
        } else {
            content
        }
    }
}

// MARK: - Modifier

/// View modifier that measures the source view and presents the custom context menu on long press.
private struct CustomContextMenuModifier<ID: Hashable, Preview: View>: ViewModifier {
    let id: ID
    let isEnabled: Bool
    let actions: [CustomContextMenuAction]
    let config: CustomContextMenuConfig
    let preview: () -> Preview

    @Environment(CustomContextMenuCoordinator.self) private var coordinator
    @State private var globalFrame: CGRect = .zero
    @State private var measuredMenuSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .opacity(coordinator.isSourceHidden(id) ? 0 : 1)
            .transaction { transaction in
                transaction.animation = nil
            }
            .background {
                Color.clear
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { newFrame in
                        if shouldUpdateGlobalFrame(with: newFrame) {
                            globalFrame = newFrame
                        }
                    }
            }
            .background(alignment: .topLeading) {
                CustomContextMenuMenuMeasure(actions: actions) { newSize in
                    if shouldUpdateMenuSize(with: newSize) {
                        measuredMenuSize = newSize
                    }
                }
                .hidden()
                .allowsHitTesting(false)
            }
            .modifier(
                CustomContextMenuPressGesture(
                    isEnabled: isEnabled && !actions.isEmpty,
                    config: config,
                    onSuccess: presentMenu
                )
            )
    }

    private func presentMenu() {
        guard isEnabled else { return }
        guard !actions.isEmpty else { return }
        let triggerMessage = """
[CustomContextMenu][TriggerDebug]
sourceID=\(String(describing: id))
sourceFrame=(x:\(String(format: "%.1f", globalFrame.minX)), y:\(String(format: "%.1f", globalFrame.minY)), w:\(String(format: "%.1f", globalFrame.width)), h:\(String(format: "%.1f", globalFrame.height)))
measuredMenuSize=(w:\(String(format: "%.1f", measuredMenuSize.width)), h:\(String(format: "%.1f", measuredMenuSize.height)))
actionsCount=\(actions.count)
"""
        if config.isLoggingEnabled {
#if DEBUG
            print(triggerMessage)
#endif
        }
        coordinator.present(
            .init(
                sourceID: AnyHashable(id),
                sourceFrame: globalFrame,
                preview: AnyView(preview()),
                actions: actions,
                measuredMenuSize: measuredMenuSize,
                config: config
            )
        )
    }

    private func shouldUpdateGlobalFrame(with newFrame: CGRect) -> Bool {
        abs(globalFrame.minX - newFrame.minX) > 0.5 ||
        abs(globalFrame.minY - newFrame.minY) > 0.5 ||
        abs(globalFrame.width - newFrame.width) > 0.5 ||
        abs(globalFrame.height - newFrame.height) > 0.5
    }

    private func shouldUpdateMenuSize(with newSize: CGSize) -> Bool {
        abs(measuredMenuSize.width - newSize.width) > 0.5 ||
        abs(measuredMenuSize.height - newSize.height) > 0.5
    }
}

extension View {
    /// Attaches the reusable custom context-menu system to one source view.
    func customContextMenu<ID: Hashable, Preview: View>(
        id: ID,
        isEnabled: Bool = true,
        actions: [CustomContextMenuAction],
        config: CustomContextMenuConfig = .init(),
        @ViewBuilder preview: @escaping () -> Preview
    ) -> some View {
        modifier(
            CustomContextMenuModifier(
                id: id,
                isEnabled: isEnabled,
                actions: actions,
                config: config,
                preview: preview
            )
        )
    }
}

// MARK: - Shared Card

/// The visible action card used by the custom context-menu host.
private struct CustomContextMenuMenuCard: View {
    let actions: [CustomContextMenuAction]
    let cornerRadius: CGFloat
    let revealedActionIDs: Set<UUID>
    let isInteractive: Bool
    let onSelect: (CustomContextMenuAction) -> Void

    private var normalActions: [CustomContextMenuAction] {
        actions.filter { $0.role == .normal }
    }

    private var destructiveActions: [CustomContextMenuAction] {
        actions.filter { $0.role == .destructive }
    }

    private var shouldShowDivider: Bool {
        !normalActions.isEmpty &&
        !destructiveActions.isEmpty &&
        normalActions.allSatisfy { revealedActionIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(normalActions) { action in
                row(for: action)
            }

            if !normalActions.isEmpty && !destructiveActions.isEmpty {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.horizontal, 20)
                    .opacity(shouldShowDivider ? 1 : 0)
                    .offset(y: shouldShowDivider ? 0 : 6)
                    .animation(.contextMenuMenuSpring, value: shouldShowDivider)
            }

            ForEach(destructiveActions) { action in
                row(for: action)
            }
        }
        .padding(.vertical, 8)
        .fixedSize(horizontal: true, vertical: true)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        .allowsHitTesting(isInteractive)
    }

    @ViewBuilder
    private func row(for action: CustomContextMenuAction) -> some View {
        let isRevealed = revealedActionIDs.contains(action.id)

        Button {
            debugLogSelection(for: action)
            emitSelectionHaptic(for: action.role)
            onSelect(action)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 20, alignment: .center)

                Text(action.title)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: true)
            .foregroundStyle(action.role == .destructive ? Color.red : Color.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .opacity(isRevealed ? 1 : 0)
        .offset(y: isRevealed ? 0 : 8)
        .scaleEffect(isRevealed ? 1 : 0.98, anchor: .topTrailing)
        .animation(.contextMenuMenuSpring, value: isRevealed)
    }

    private func emitSelectionHaptic(for role: CustomContextMenuActionRole) {
        switch role {
        case .normal:
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.prepare()
            generator.impactOccurred(intensity: 0.62)
        case .destructive:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.warning)
        }
    }

    private func debugLogSelection(for action: CustomContextMenuAction) {
#if DEBUG
        print("[CustomContextMenu][Action] title=\(action.title) role=\(action.role)")
#endif
    }
}

/// Hidden measure surface that gives source views the real menu card size before presentation.
private struct CustomContextMenuMenuMeasure: View {
    let actions: [CustomContextMenuAction]
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        CustomContextMenuMenuCard(
            actions: actions,
            cornerRadius: 32,
            revealedActionIDs: Set(actions.map(\.id)),
            isInteractive: false,
            onSelect: { _ in }
        )
        .background {
            Color.clear
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newSize in
                    onSizeChange(newSize)
                }
        }
    }
}

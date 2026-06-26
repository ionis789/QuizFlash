//
//  CustomContextMenuOverlay.swift
//  QuizFlash
//
//  Global host, overlay, and shared menu surface for the custom context-menu system.
//

import SwiftUI
import UIKit

// MARK: - Host

/// Global overlay host that renders the active preview, background, and action card.
struct CustomContextMenuHost: View {
    @Environment(CustomContextMenuCoordinator.self) private var coordinator
    @Environment(CustomContextMenuSourceRegistry.self) private var sourceRegistry

    var body: some View {
        ZStack {
            CustomContextMenuTouchTrackerAttachment(
                sourceRegistry: sourceRegistry,
                menuCoordinator: coordinator
            )
            .allowsHitTesting(false)

            if let presentation = coordinator.presentation {
                CustomContextMenuOverlay(
                    presentation: presentation,
                    phase: coordinator.phase,
                    onDismiss: {
                        CustomContextMenuDebugConsole.log(
                            enabled: presentation.config.isLoggingEnabled,
                            sourceID: String(describing: presentation.sourceID),
                            event: "DismissBackgroundTap"
                        )
                        if presentation.config.isLoggingEnabled {
                            CustomContextMenuLog.debug(
                                "[CustomContextMenu][Dismiss] reason=backgroundTap"
                            )
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
}

struct CustomContextMenuOverlay: View {
    let presentation: CustomContextMenuCoordinator.Presentation
    let phase: CustomContextMenuPhase
    let onDismiss: () -> Void
    let onSelect: (CustomContextMenuAction) -> Void

    @State private var backdropMaterialOpacity = 0.0
    @State private var backdropWashOpacity = 0.0
    @State private var previewScale: CGFloat = 1
    @State private var previewOffset: CGSize = .zero
    @State private var menuOpacity = 0.0
    @State private var menuScale: CGFloat = 1
    @State private var revealedActionIDs: Set<UUID> = []
    @State private var liftTask: Task<Void, Never>?

    private var sourceDescription: String {
        String(describing: presentation.sourceID)
    }

    private var menuRevealInitialScale: CGFloat {
        min(presentation.config.menuInitialScale, 0.16)
    }

    private var resolvedPreviewFrame: CGRect {
        presentation.sourceFrame.offsetBy(
            dx: presentation.layout.previewOffset.width,
            dy: presentation.layout.previewOffset.height
        )
    }

    private var menuRevealAnchor: UnitPoint {
        let menuFrame = presentation.layout.menuFrame
        let previewFrame = resolvedPreviewFrame
        let overlapMinX = max(menuFrame.minX, previewFrame.minX)
        let overlapMaxX = min(menuFrame.maxX, previewFrame.maxX)
        let overlapCenterX: CGFloat

        if overlapMaxX > overlapMinX {
            overlapCenterX = (overlapMinX + overlapMaxX) * 0.5
        } else {
            overlapCenterX = min(
                max(previewFrame.midX, menuFrame.minX),
                menuFrame.maxX
            )
        }

        let anchorX = min(
            max((overlapCenterX - menuFrame.minX) / max(menuFrame.width, 1), 0),
            1
        )

        return UnitPoint(x: anchorX, y: 0)
    }

    private var previewPushAnimation: Animation {
        let previewOffset = presentation.layout.previewOffset
        let hasPositionPush = abs(previewOffset.width) > 0.5 || abs(previewOffset.height) > 0.5
        return hasPositionPush ? .contextMenuPreviewPushSpring : .contextMenuLiftSpring
    }

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
                    .compositingGroup()
                    .scaleEffect(previewScale, anchor: .topLeading)
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
                    infoRows: presentation.infoRows,
                    actions: presentation.actions,
                    cornerRadius: presentation.config.menuCornerRadius,
                    revealedActionIDs: revealedActionIDs,
                    isInteractive: phase == .expanded,
                    showsChrome: true
                ) { action in
                    onSelect(action)
                }
                .fixedSize(horizontal: true, vertical: true)
                .frame(
                    width: localMenuFrame.width,
                    height: localMenuFrame.height,
                    alignment: .topLeading
                )
                .opacity(menuOpacity)
                .scaleEffect(menuScale, anchor: menuRevealAnchor)
                .offset(
                    x: localMenuFrame.minX,
                    y: localMenuFrame.minY
                )
                .allowsHitTesting(phase == .expanded)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            prepareInitialState()
            logTimeline("OverlayAppear", details: "phase=\(phase)")
            update(for: phase)
        }
        .onChange(of: phase) { _, newPhase in
            logTimeline("OverlayPhaseObserved", details: "phase=\(newPhase)")
            update(for: newPhase)
        }
        .onDisappear {
            logTimeline("OverlayDisappear")
            cancelAnimationTasks()
        }
    }

    private func prepareInitialState() {
        backdropMaterialOpacity = 0
        backdropWashOpacity = 0
        previewScale = presentation.config.pressScale
        previewOffset = .zero
        menuOpacity = 0
        menuScale = menuRevealInitialScale
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
        logTimeline(
            "LiftSequenceStart",
            details: "previewScaleFrom=\(fmt(presentation.config.pressScale)) previewScaleTo=\(fmt(presentation.config.finalPreviewScale)) previewOffset=(dx:\(fmt(presentation.layout.previewOffset.width)), dy:\(fmt(presentation.layout.previewOffset.height)))"
        )

        withAnimation(.easeOut(duration: 0.08)) {
            backdropMaterialOpacity = presentation.config.backdropMaterialMaxOpacity * 0.34
            backdropWashOpacity = 0.22
        }

        withAnimation(.contextMenuPreviewScaleBackSpring) {
            previewScale = presentation.config.finalPreviewScale
        }

        withAnimation(previewPushAnimation) {
            previewOffset = presentation.layout.previewOffset
        }

        liftTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(54))
            guard !Task.isCancelled else { return }
            logTimeline("BackdropIntensifyStart")

            withAnimation(.easeOut(duration: 0.14)) {
                backdropMaterialOpacity = presentation.config.backdropMaterialMaxOpacity
                backdropWashOpacity = 1
            }

            try? await Task.sleep(for: .seconds(presentation.config.menuRevealDelay))
            guard !Task.isCancelled else { return }
            logTimeline(
                "MenuRevealStart",
                details: "delay=\(String(format: "%.3f", presentation.config.menuRevealDelay)) anchorX=\(fmt(menuRevealAnchor.x))"
            )

            logTimeline(
                "MenuActionsRevealAll",
                details: "count=\(presentation.actions.count)"
            )

            withAnimation(.contextMenuMenuPopSpring) {
                menuOpacity = 1
                menuScale = 1
                revealedActionIDs = Set(presentation.actions.map(\.id))
            }
        }
    }

    private func runDismissSequence() {
        liftTask?.cancel()
        logTimeline(
            "DismissSequenceStart",
            details: "targetScale=\(fmt(menuRevealInitialScale)) anchorX=\(fmt(menuRevealAnchor.x))"
        )

        withAnimation(.contextMenuMenuPopSpring) {
            menuScale = menuRevealInitialScale
        }

        withAnimation(.easeOut(duration: 0.18)) {
            menuOpacity = 0
        }

        withAnimation(.easeOut(duration: 0.18)) {
            backdropMaterialOpacity = 0
            backdropWashOpacity = 0
        }

        withAnimation(previewPushAnimation) {
            previewOffset = .zero
        }
    }

    private func cancelAnimationTasks() {
        liftTask?.cancel()
    }

    private func logTimeline(_ event: String, details: String = "") {
        CustomContextMenuDebugConsole.log(
            enabled: presentation.config.isLoggingEnabled,
            sourceID: sourceDescription,
            event: event,
            details: details
        )
    }

    private func fmt(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}

// MARK: - Shared Card

/// The visible action card used by the custom context-menu host.
struct CustomContextMenuMenuCard: View {
    let infoRows: [CustomContextMenuInfoRow]
    let actions: [CustomContextMenuAction]
    let cornerRadius: CGFloat
    let revealedActionIDs: Set<UUID>
    let isInteractive: Bool
    let showsChrome: Bool
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
        VStack(alignment: .leading, spacing: 0) {
            if !infoRows.isEmpty {
                infoSection

                if !actions.isEmpty {
                    Divider()
                        .overlay(Color.white.opacity(0.08))
                        .padding(.horizontal, 20)
                }
            }

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .modifier(
            CustomContextMenuCardChrome(
                cornerRadius: cornerRadius,
                isEnabled: showsChrome
            )
        )
        .allowsHitTesting(isInteractive)
    }

    private var infoSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(infoRows) { row in
                    infoChip(for: row)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 214, height: 58, alignment: .leading)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func infoChip(for row: CustomContextMenuInfoRow) -> some View {
        VStack(spacing: 2) {
            Text(row.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.56))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)

            Text(row.value)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 72)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    @ViewBuilder
    private func row(for action: CustomContextMenuAction) -> some View {
        let isRevealed = revealedActionIDs.contains(action.id)

        Button {
            debugLogSelection(for: action)
            emitSelectionHaptic(for: action.role)
            onSelect(action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 18, alignment: .center)

                Text(action.title)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(action.role == .destructive ? Color.red : Color.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isRevealed ? 1 : 0)
        .offset(x: isRevealed ? 0 : 5, y: isRevealed ? 0 : 12)
        .scaleEffect(isRevealed ? 1 : 0.95, anchor: .topLeading)
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
        CustomContextMenuLog.debug(
            "[CustomContextMenu][Action] title=\(action.title) role=\(action.role)"
        )
    }
}

private struct CustomContextMenuCardChrome: ViewModifier {
    let cornerRadius: CGFloat
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        } else {
            content
        }
    }
}

/// Hidden measure surface that gives source views the real menu card size before presentation.
struct CustomContextMenuMenuMeasure: View {
    let infoRows: [CustomContextMenuInfoRow]
    let actions: [CustomContextMenuAction]
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        CustomContextMenuMenuCard(
            infoRows: infoRows,
            actions: actions,
            cornerRadius: 32,
            revealedActionIDs: Set(actions.map(\.id)),
            isInteractive: false,
            showsChrome: false,
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

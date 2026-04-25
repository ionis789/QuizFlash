//
//  CustomContextMenu.swift
//  QuizFlash
//
//  Public modifier entry point for the split custom context-menu infrastructure.
//

import SwiftUI

// MARK: - Modifier

/// View modifier that measures the source view and presents the custom context menu on long press.
private struct CustomContextMenuModifier<ID: Hashable, Preview: View>: ViewModifier {
    let id: ID
    let isEnabled: Bool
    let infoRows: () -> [CustomContextMenuInfoRow]
    let actions: () -> [CustomContextMenuAction]
    let config: CustomContextMenuConfig
    let preview: () -> Preview

    @Environment(CustomContextMenuCoordinator.self) private var coordinator
    @Environment(CustomContextMenuSourceRegistry.self) private var sourceRegistry
    @State private var measuredMenuSize: CGSize = .zero
    @State private var isPressing = false

    private var hiddenSourceOpacity: Double {
        coordinator.isSourceHidden(id) ? 0 : 1
    }

    private var menuSizeCacheKey: String {
        CustomContextMenuMenuSizeCache.key(for: actions(), infoRows: infoRows())
    }

    private var resolvedMenuSize: CGSize {
        if let estimatedMenuSize = config.estimatedMenuSize {
            return estimatedMenuSize
        }

        if measuredMenuSize != .zero {
            return measuredMenuSize
        }

        return CustomContextMenuMenuSizeCache.size(for: menuSizeCacheKey) ?? .zero
    }

    func body(content: Content) -> some View {
        content
            .opacity(hiddenSourceOpacity)
            .transaction { transaction in
                transaction.animation = nil
            }
            .scaleEffect(isPressing ? config.pressScale : 1, anchor: .topLeading)
            .background(alignment: .topLeading) {
                if config.estimatedMenuSize == nil, resolvedMenuSize == .zero {
                    CustomContextMenuMenuMeasure(
                        infoRows: infoRows(),
                        actions: actions()
                    ) { newSize in
                        if shouldUpdateMenuSize(with: newSize) {
                            measuredMenuSize = newSize
                            CustomContextMenuMenuSizeCache.store(newSize, for: menuSizeCacheKey)
                        }
                    }
                    .hidden()
                    .allowsHitTesting(false)
                }
            }
            .background {
                CustomContextMenuSourceAttachment(
                    id: AnyHashable(id),
                    sourceDescription: String(describing: id),
                    isEnabled: isEnabled,
                    config: config,
                    sourceRegistry: sourceRegistry,
                    onPressingChange: { newValue in
                        if isPressing != newValue {
                            withAnimation(newValue ? .contextMenuPressIn : .contextMenuPressOut) {
                                isPressing = newValue
                            }
                        }
                    },
                    onActivate: { sourceGlobalFrame in
                        presentMenu(sourceGlobalFrame: sourceGlobalFrame)
                    }
                )
            }
            .onChange(of: coordinator.presentation?.id) { _, newPresentationID in
                if newPresentationID == nil {
                    CustomContextMenuDebugConsole.log(
                        enabled: config.isLoggingEnabled,
                        sourceID: String(describing: id),
                        event: "GestureObservedPresentationCleared"
                    )
                    isPressing = false
                }
            }
            .onChange(of: coordinator.phase) { _, newPhase in
                CustomContextMenuDebugConsole.log(
                    enabled: config.isLoggingEnabled,
                    sourceID: String(describing: id),
                    event: "GestureObservedPhase",
                    details: "phase=\(newPhase)"
                )
                if newPhase == .lifting || newPhase == .expanded || newPhase == .dismissing || newPhase == .idle {
                    isPressing = false
                }
            }
    }

    @MainActor
    private func presentMenu(sourceGlobalFrame: CGRect) {
        let resolvedInfoRows = infoRows()
        let resolvedActions = actions()
        guard isEnabled else { return }
        guard !resolvedActions.isEmpty else { return }
        guard sourceGlobalFrame != .zero else { return }
        CustomContextMenuDebugConsole.log(
            enabled: config.isLoggingEnabled,
            sourceID: String(describing: id),
            event: "ModifierPresentMenu",
            details: "actionsCount=\(resolvedActions.count)"
        )
        let triggerMessage = """
[CustomContextMenu][TriggerDebug]
sourceID=\(String(describing: id))
sourceFrame=(x:\(String(format: "%.1f", sourceGlobalFrame.minX)), y:\(String(format: "%.1f", sourceGlobalFrame.minY)), w:\(String(format: "%.1f", sourceGlobalFrame.width)), h:\(String(format: "%.1f", sourceGlobalFrame.height)))
measuredMenuSize=(w:\(String(format: "%.1f", resolvedMenuSize.width)), h:\(String(format: "%.1f", resolvedMenuSize.height)))
actionsCount=\(resolvedActions.count)
"""
        if config.isLoggingEnabled {
            CustomContextMenuLog.debug(triggerMessage)
        }
        coordinator.present(
            .init(
                sourceID: AnyHashable(id),
                sourceFrame: sourceGlobalFrame,
                preview: AnyView(preview()),
                infoRows: resolvedInfoRows,
                actions: resolvedActions,
                measuredMenuSize: resolvedMenuSize,
                config: config
            )
        )
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
        infoRows: @autoclosure @escaping () -> [CustomContextMenuInfoRow] = [],
        actions: @autoclosure @escaping () -> [CustomContextMenuAction],
        config: CustomContextMenuConfig = .init(),
        @ViewBuilder preview: @escaping () -> Preview
    ) -> some View {
        modifier(
            CustomContextMenuModifier(
                id: id,
                isEnabled: isEnabled,
                infoRows: infoRows,
                actions: actions,
                config: config,
                preview: preview
            )
        )
    }
}

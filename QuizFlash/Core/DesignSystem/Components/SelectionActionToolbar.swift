//
//  SelectionActionToolbar.swift
//  QuizFlash
//
//  Shared bottom toolbar and top selection-menu transition controls.
//

import SwiftUI
import UIKit

enum SelectionActionToolbarTint {
    case primary
    case accent
    case destructive
}

struct SelectionActionToolbarAction: Identifiable {
    enum Presentation {
        case icon(systemName: String, title: String? = nil, showsProgress: Bool = false)
        case text(String)
    }

    let id: String
    let presentation: Presentation
    let accessibilityLabel: String
    var isEnabled: Bool = true
    var tint: SelectionActionToolbarTint = .primary
    var action: () -> Void

    static func icon(
        id: String,
        systemName: String,
        title: String? = nil,
        accessibilityLabel: String,
        isEnabled: Bool = true,
        showsProgress: Bool = false,
        tint: SelectionActionToolbarTint = .primary,
        action: @escaping () -> Void
    ) -> SelectionActionToolbarAction {
        SelectionActionToolbarAction(
            id: id,
            presentation: .icon(systemName: systemName, title: title, showsProgress: showsProgress),
            accessibilityLabel: accessibilityLabel,
            isEnabled: isEnabled,
            tint: tint,
            action: action
        )
    }

    static func text(
        id: String,
        title: String,
        accessibilityLabel: String,
        isEnabled: Bool = true,
        tint: SelectionActionToolbarTint = .accent,
        action: @escaping () -> Void
    ) -> SelectionActionToolbarAction {
        SelectionActionToolbarAction(
            id: id,
            presentation: .text(title),
            accessibilityLabel: accessibilityLabel,
            isEnabled: isEnabled,
            tint: tint,
            action: action
        )
    }
}

struct SelectionActionToolbar: View {
    @Environment(ThemeManager.self) private var themeManager

    let selectedCount: Int
    let actions: [SelectionActionToolbarAction]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(actions) { action in
                actionButton(action)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: UIConstants.Size.bottomChromeBarHeight)
        .contentShape(Rectangle())
        .animation(.selectionToolbarSpring, value: selectedCount)
    }

    @ViewBuilder
    private func actionButton(_ action: SelectionActionToolbarAction) -> some View {
        switch action.presentation {
        case let .icon(systemName, title, showsProgress):
            Button(action: action.action) {
                VStack(spacing: 5) {
                    if showsProgress {
                        ProgressView()
                            .scaleEffect(0.82)
                            .tint(tintColor(for: action))
                            .frame(height: 23)
                    } else {
                        Image(systemName: systemName)
                            .font(.system(size: 22, weight: .semibold))
                            .frame(height: 23)
                    }

                    if let title {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .foregroundStyle(tintColor(for: action))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(!action.isEnabled)
            .opacity(action.isEnabled ? 1 : 0.42)
            .accessibilityLabel(action.accessibilityLabel)

        case let .text(title):
            Button(action: action.action) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(tintColor(for: action))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(!action.isEnabled)
            .opacity(action.isEnabled ? 1 : 0.42)
            .accessibilityLabel(action.accessibilityLabel)
        }
    }

    private func tintColor(for action: SelectionActionToolbarAction) -> Color {
        guard action.isEnabled else { return themeManager.textSecondary }

        switch action.tint {
        case .primary:
            return themeManager.textPrimary
        case .accent:
            return themeManager.accentColor.color
        case .destructive:
            return themeManager.dangerPrimary
        }
    }
}

enum SelectionModeMenuElement {
    static func action(
        title: String,
        systemImage: String,
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        state: UIMenuElement.State = .off,
        handler: @escaping @MainActor () -> Void
    ) -> UIAction {
        var attributes: UIMenuElement.Attributes = []
        if !isEnabled {
            attributes.insert(.disabled)
        }
        if isDestructive {
            attributes.insert(.destructive)
        }

        return UIAction(
            title: title,
            image: UIImage(systemName: systemImage),
            attributes: attributes,
            state: state
        ) { _ in
            MainActor.assumeIsolated {
                handler()
            }
        }
    }
}

struct SelectionModeMenuButton: View {
    let isSelecting: Bool
    let menuAccessibilityLabel: String
    let doneAccessibilityLabel: String
    let onDone: () -> Void
    let menu: (@escaping () -> Void, @escaping () -> Void) -> UIMenu

    @State private var visualSelectionOverride = false
    @State private var isMenuPresented = false

    private var isVisuallySelecting: Bool {
        isSelecting || visualSelectionOverride
    }

    var body: some View {
        ZStack {
            ChromeSoftCircleSymbol(
                systemName: "ellipsis",
                size: UIConstants.Size.actionButton,
                symbolSize: UIConstants.Size.iconStandard
            )
            .opacity(isVisuallySelecting || shouldHideMenuButtonWhilePresented ? 0 : 1)
            .scaleEffect(isVisuallySelecting ? 0.86 : 1)
            .accessibilityHidden(isVisuallySelecting)
            .allowsHitTesting(false)

            ChromeSoftCircleSymbol(
                systemName: "checkmark",
                size: UIConstants.Size.actionButton,
                symbolSize: UIConstants.Size.iconStandard
            )
            .opacity(isVisuallySelecting ? 1 : 0)
            .scaleEffect(isVisuallySelecting ? 1 : 0.86)
            .accessibilityHidden(!isVisuallySelecting)
            .allowsHitTesting(false)

            if isVisuallySelecting {
                Button(action: onDone) {
                    Color.clear
                        .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(doneAccessibilityLabel)
            } else {
                SelectionModeUIKitMenuHost(
                    accessibilityLabel: menuAccessibilityLabel,
                    menu: menu(prepareSelectionVisual, finishMenuInteraction),
                    onMenuPresented: showMenuInteraction,
                    onMenuDismissed: finishMenuInteraction
                )
                .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
            }
        }
        .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
        .animation(.snappy(duration: 0.18, extraBounce: 0), value: isVisuallySelecting || shouldHideMenuButtonWhilePresented)
        .onChange(of: isSelecting) { _, newValue in
            if newValue {
                isMenuPresented = false
                visualSelectionOverride = false
            } else if visualSelectionOverride {
                visualSelectionOverride = false
            }
        }
    }

    private var shouldHideMenuButtonWhilePresented: Bool {
        if #available(iOS 26.0, *) {
            return isMenuPresented
        }
        return false
    }

    private func showMenuInteraction() {
        guard #available(iOS 26.0, *) else { return }
        guard !isSelecting else { return }
        isMenuPresented = true
    }

    private func finishMenuInteraction() {
        isMenuPresented = false
    }

    private func prepareSelectionVisual() {
        guard !isSelecting else { return }
        isMenuPresented = false
        withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
            visualSelectionOverride = true
        }
    }
}

private struct SelectionModeUIKitMenuHost: UIViewRepresentable {
    let accessibilityLabel: String
    let menu: UIMenu
    let onMenuPresented: () -> Void
    let onMenuDismissed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onMenuPresented: onMenuPresented,
            onMenuDismissed: onMenuDismissed
        )
    }

    func makeUIView(context: Context) -> UIButton {
        let button = SelectionModeMenuControl(type: .custom)
        button.backgroundColor = .clear
        button.showsMenuAsPrimaryAction = true
        button.accessibilityTraits = .button
        button.accessibilityLabel = accessibilityLabel
        button.onMenuPresented = context.coordinator.menuPresented
        button.onMenuDismissed = context.coordinator.menuDismissed
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = accessibilityLabel
        context.coordinator.onMenuPresented = onMenuPresented
        context.coordinator.onMenuDismissed = onMenuDismissed
        if let button = button as? SelectionModeMenuControl {
            button.onMenuPresented = context.coordinator.menuPresented
            button.onMenuDismissed = context.coordinator.menuDismissed
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onMenuPresented: () -> Void
        var onMenuDismissed: () -> Void

        init(
            onMenuPresented: @escaping () -> Void,
            onMenuDismissed: @escaping () -> Void
        ) {
            self.onMenuPresented = onMenuPresented
            self.onMenuDismissed = onMenuDismissed
        }

        func menuPresented() {
            onMenuPresented()
        }

        func menuDismissed() {
            onMenuDismissed()
        }
    }

    @MainActor
    final class SelectionModeMenuControl: UIButton {
        var onMenuPresented: (() -> Void)?
        var onMenuDismissed: (() -> Void)?
        private var menuDismissTask: Task<Void, Never>?
        private var menuPresentationGeneration = 0

        deinit {
            menuDismissTask?.cancel()
        }

        override func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willDisplayMenuFor configuration: UIContextMenuConfiguration,
            animator: UIContextMenuInteractionAnimating?
        ) {
            super.contextMenuInteraction(
                interaction,
                willDisplayMenuFor: configuration,
                animator: animator
            )
            if #available(iOS 26.0, *) {
                menuPresentationGeneration += 1
                menuDismissTask?.cancel()
                menuDismissTask = nil
                onMenuPresented?()
            }
        }

        override func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willEndFor configuration: UIContextMenuConfiguration,
            animator: UIContextMenuInteractionAnimating?
        ) {
            super.contextMenuInteraction(
                interaction,
                willEndFor: configuration,
                animator: animator
            )
            if #available(iOS 26.0, *) {
                menuPresentationGeneration += 1
                let dismissGeneration = menuPresentationGeneration
                menuDismissTask?.cancel()
                menuDismissTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    guard
                        !Task.isCancelled,
                        let self,
                        self.menuPresentationGeneration == dismissGeneration
                    else { return }

                    self.onMenuDismissed?()
                    self.menuDismissTask = nil
                }
            }
        }
    }
}

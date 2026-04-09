//
//  CustomContextMenuLayout.swift
//  QuizFlash
//
//  Layout calculator for placing the custom context menu relative to its source.
//

import UIKit

// MARK: - Placement

/// Placement mode chosen for the context menu relative to the source view.
enum CustomContextMenuPlacementMode: Equatable {
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

/// Resolves the on-screen geometry for one active custom context-menu presentation.
@MainActor
enum CustomContextMenuLayoutResolver {
    static func resolveLayout(
        sourceFrame: CGRect,
        measuredMenuSize: CGSize,
        config: CustomContextMenuConfig
    ) -> CustomContextMenuResolvedLayout {
        let windowBounds = currentWindowBounds()
        let safeInsets = currentSafeAreaInsets()
        return resolveLayout(
            sourceFrame: sourceFrame,
            measuredMenuSize: measuredMenuSize,
            config: config,
            windowBounds: windowBounds,
            safeInsets: safeInsets
        )
    }

    static func resolveLayout(
        sourceFrame: CGRect,
        measuredMenuSize: CGSize,
        config: CustomContextMenuConfig,
        windowBounds: CGRect,
        safeInsets: UIEdgeInsets
    ) -> CustomContextMenuResolvedLayout {
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

    private static func currentWindowBounds() -> CGRect {
        activeWindow()?.bounds
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .coordinateSpace.bounds
            ?? .zero
    }

    private static func currentSafeAreaInsets() -> UIEdgeInsets {
        activeWindow()?.safeAreaInsets ?? .zero
    }

    private static func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
    }
}

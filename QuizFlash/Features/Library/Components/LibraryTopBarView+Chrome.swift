//
//  LibraryTopBarView+Chrome.swift
//  QuizFlash
//
//  Single-chrome composition for LibraryTopBarView.
//

import SwiftUI

extension LibraryTopBarView {
    var chromeRow: some View {
        GeometryReader { proxy in
            let isSearchChromeVisible = viewModel.isSearching || searchProgress > 0.001
            let availableWidth = max(
                0,
                proxy.size.width - (UIConstants.Layout.compactScreenEdgeInset * 2)
            )
            let resolvedTrailingWidth = max(
                trailingControlWidth,
                LibraryTopBarChromeMetrics.expandedHitTargetSize
            )
            let searchTrailingVisualOverlap = isSearchChromeVisible
                ? ((LibraryTopBarChromeMetrics.expandedHitTargetSize - UIConstants.Size.actionButton) / 2)
                : 0
            let maxLeadingSearchWidth = max(
                UIConstants.Size.actionButton,
                availableWidth - resolvedTrailingWidth + searchTrailingVisualOverlap
            )
            let sideReserve = max(leadingControlWidth, resolvedTrailingWidth)
            let maxCenterWidth = max(
                UIConstants.Size.capsuleHeight,
                availableWidth - (sideReserve * 2) - (UIConstants.Spacing.medium * 2)
            )

            ZStack(alignment: .center) {
                CollapsibleTitlePill(
                    title: title,
                    maxWidth: maxCenterWidth,
                    isVisible: shouldShowCollapsedTitlePill,
                    animateVisibility: animateCollapsedTitleVisibility
                        && !(viewModel.isSearching || searchProgress > 0.001),
                    fallbackTitle: titleFallback,
                    visibilityAnimation: compactChromeVisibilityAnimation,
                    coordinateSpaceName: coordinateSpaceName,
                    onContentFrameChange: onCollapsedTitleFrameChange
                )
                .offset(y: CollapsibleTitleChromeMetrics.floatingTitleVerticalOffset)
                .allowsHitTesting(false)

                HStack(alignment: .center) {
                    leadingControl(maxSearchFieldWidth: maxLeadingSearchWidth)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.width
                        } action: { newWidth in
                            if abs(leadingControlWidth - newWidth) > 0.5 {
                                leadingControlWidth = newWidth
                            }
                        }

                    Spacer(minLength: 0)

                    trailingControl
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.width
                        } action: { newWidth in
                            if abs(trailingControlWidth - newWidth) > 0.5 {
                                trailingControlWidth = newWidth
                            }
                        }
                }
            }
        }
        .frame(height: UIConstants.Size.capsuleHeight)
    }

    var shouldShowCollapsedTitlePill: Bool {
        isCollapsedTitleVisible
            && isCompactChromeRecoveryVisible
            && !viewModel.isSearching
            && searchProgress <= 0.001
    }

    @ViewBuilder
    func leadingControl(maxSearchFieldWidth: CGFloat) -> some View {
        if let onBackAction = onBack {
            LibraryTopBarBackButton(
                label: backLabel,
                action: onBackAction
            )
            .id("topbar.leading.back")
        } else {
            searchLeadingControl(maxWidth: maxSearchFieldWidth)
                .id("topbar.leading.search")
        }
    }

    @ViewBuilder
    var trailingControl: some View {
        if viewModel.isSearching || searchProgress > 0.001 {
            dismissSearchButton
        } else {
            moreSettingsButton
        }
    }

    var moreSettingsButton: some View {
        LibraryTopBarMoreSettingsButton {
            LibraryTopBarMenuContent(viewModel: viewModel) {
                withBottomChromeAnimation {
                    viewModel.enterSelectionMode()
                }
            }
        }
    }
}

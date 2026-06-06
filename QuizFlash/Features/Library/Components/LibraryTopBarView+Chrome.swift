//
//  LibraryTopBarView+Chrome.swift
//  QuizFlash
//
//  Single-chrome composition for LibraryTopBarView.
//

import SwiftUI
import UIKit

extension LibraryTopBarView {
    var chromeRow: some View {
        GeometryReader { proxy in
            let availableWidth = max(0, proxy.size.width)
            let resolvedTrailingWidth = max(
                trailingControlWidth,
                LibraryTopBarChromeMetrics.expandedHitTargetSize
            )
            let maxLeadingSearchWidth = max(
                UIConstants.Size.actionButton,
                availableWidth - resolvedTrailingWidth
            )
            let sideReserve = max(leadingControlWidth, resolvedTrailingWidth)
            let titleSideReserve = searchProgress > 0.001 || viewModel.isSearching
                ? resolvedTrailingWidth
                : sideReserve
            let maxCenterWidth = max(
                UIConstants.Size.capsuleHeight,
                availableWidth - (titleSideReserve * 2) - (UIConstants.Spacing.medium * 2)
            )

            ZStack(alignment: .center) {
                CollapsibleTitlePill(
                    title: title,
                    maxWidth: maxCenterWidth,
                    isVisible: shouldShowCollapsedTitlePill,
                    animateVisibility: animateCollapsedTitleVisibility,
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
        ZStack {
            moreSettingsButton
                .opacity(1 - searchProgress)
                .scaleEffect(1 - (0.14 * searchProgress))
                .allowsHitTesting(!viewModel.isSearching && searchProgress <= 0.001)

            dismissSearchButton
                .opacity(searchProgress)
                .scaleEffect(0.86 + (0.14 * searchProgress))
                .allowsHitTesting(viewModel.isSearching || searchProgress > 0.999)
        }
        .animation(searchChromeTransition, value: searchProgress)
    }

    var moreSettingsButton: some View {
        LibraryTopBarMoreSettingsButton(
            isSelecting: viewModel.isSelecting,
            onDoneSelecting: {
                withBottomChromeAnimation {
                    viewModel.exitSelectionMode()
                }
            },
            menu: { prepareSelectionVisual, finishMenuInteraction in
                UIMenu(children: [
                    SelectionModeMenuElement.action(
                        title: AppLocalization.string("Select", locale: locale),
                        systemImage: "checkmark.circle",
                        isEnabled: !viewModel.isSelecting && !viewModel.isSearching
                    ) {
                        prepareSelectionVisual()
                        withBottomChromeAnimation {
                            viewModel.enterSelectionMode()
                        }
                    },
                    SelectionModeMenuElement.action(
                        title: AppLocalization.string("Import Deck", locale: locale),
                        systemImage: "square.and.arrow.down"
                    ) {
                        finishMenuInteraction()
                        viewModel.showFileImporter = true
                    },
                    librarySortMenu(finishMenuInteraction: finishMenuInteraction),
                    UIMenu(
                        title: AppLocalization.string("Group By", locale: locale),
                        image: UIImage(systemName: "arrow.up.arrow.down"),
                        children: []
                    )
                ])
            }
        )
    }

    private func librarySortMenu(finishMenuInteraction: @escaping () -> Void) -> UIMenu {
        UIMenu(
            title: AppLocalization.string("Sort By", locale: locale),
            image: UIImage(systemName: "arrow.up.arrow.down"),
            children: SortOrder.allCases.map { order in
                SelectionModeMenuElement.action(
                    title: order.localizedTitle(locale: locale),
                    systemImage: viewModel.sortOrder == order ? "checkmark" : order.icon,
                    state: viewModel.sortOrder == order ? .on : .off
                ) {
                    finishMenuInteraction()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        viewModel.sortOrder = order
                    }
                }
            }
        )
    }
}

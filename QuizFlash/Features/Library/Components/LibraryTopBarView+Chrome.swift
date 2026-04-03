//
//  LibraryTopBarView+Chrome.swift
//  QuizFlash
//
//  Idle chrome composition for LibraryTopBarView.
//

import SwiftUI

extension LibraryTopBarView {
    var idleChromeRow: some View {
        CollapsibleTitleNavigationBar(
            coordinateSpaceName: coordinateSpaceName,
            onBottomChange: onBottomChange
        ) {
            leadingControl
                .fixedSize()
        } center: { maxTitleWidth in
            CollapsibleTitlePill(
                title: title,
                maxWidth: maxTitleWidth,
                isVisible: isCollapsedTitleVisible,
                fallbackTitle: "Library",
                coordinateSpaceName: coordinateSpaceName,
                onContentFrameChange: onCollapsedTitleFrameChange
            )
        } trailing: {
            ZStack {
                ChromeCirclePlaceholder()
                    .frame(width: moreSettingsSlotSize, height: moreSettingsSlotSize)

                if showsEllipsis {
                    moreSettingsButton
                        .opacity(ellipsisOpacity)
                        .allowsHitTesting(!viewModel.isSearching && ellipsisOpacity > 0.01)
                        .accessibilityHidden(viewModel.isSearching)
                        .transition(.identity)
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                }
            }
            .frame(width: moreSettingsSlotSize, height: moreSettingsSlotSize)
            .contentShape(Circle())
        }
    }

    @ViewBuilder
    var leadingControl: some View {
        if let onBackAction = onBack {
            LibraryTopBarBackButton(
                accent: accent,
                label: backLabel,
                action: onBackAction
            )
            .id("topbar.leading.back")
        } else {
            LibraryTopBarSearchIconButton(
                accent: accent,
                namespace: searchTransitionNamespace,
                isSearching: viewModel.isSearching,
                backgroundScale: searchIconBackgroundScale,
                action: activateSearch
            )
            .id("topbar.leading.search")
        }
    }

    var moreSettingsButton: some View {
        LibraryTopBarMoreSettingsButton(accent: accent) {
            LibraryTopBarMenuContent(viewModel: viewModel) {
                withBottomChromeAnimation {
                    viewModel.enterSelectionMode()
                }
            }
        }
    }

    var moreSettingsSlotSize: CGFloat {
        UIConstants.Size.actionButton + 16
    }
}

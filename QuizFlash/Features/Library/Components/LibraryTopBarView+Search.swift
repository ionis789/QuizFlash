//
//  LibraryTopBarView+Search.swift
//  QuizFlash
//
//  Search control composition for LibraryTopBarView.
//

import SwiftUI

extension LibraryTopBarView {
    private var localizedSearchPrompt: String {
        localized("Search for decks")
    }

    @ViewBuilder
    func searchLeadingControl(maxWidth: CGFloat) -> some View {
        if viewModel.isSearching || searchProgress > 0.001 {
            searchFieldVisual(maxWidth: maxWidth)
                .frame(width: searchFieldContainerWidth(maxWidth: maxWidth), alignment: .leading)
                .contentShape(Capsule())
        } else {
            Button(action: activateSearch) {
                searchFieldVisual(maxWidth: maxWidth)
                    .frame(width: searchFieldContainerWidth(maxWidth: maxWidth), alignment: .leading)
                    .contentShape(Capsule())
            }
            .buttonStyle(LibraryTopBarNoHighlightButtonStyle())
            .accessibilityLabel(localized("Search"))
        }
    }

    func searchFieldVisual(maxWidth: CGFloat) -> some View {
        HStack(spacing: UIConstants.Spacing.small + 2) {
            LibraryTopBarSearchGlyph(color: accent)
                .frame(
                    width: UIConstants.Size.actionButton,
                    height: searchFieldVisualHeight
                )

            searchFieldContent
                .frame(maxWidth: .infinity, alignment: .leading)

            trailingAccessory
        }
        .padding(.trailing, UIConstants.Spacing.standard)
        .frame(
            width: searchFieldVisualWidth(maxWidth: maxWidth),
            height: searchFieldVisualHeight,
            alignment: .leading
        )
        .background {
            LibraryTopBarSearchFieldBackground()
        }
        .clipShape(Capsule())
    }

    func searchFieldVisualWidth(maxWidth: CGFloat) -> CGFloat {
        let expandedWidth = max(UIConstants.Size.actionButton, maxWidth)
        return UIConstants.Size.actionButton
            + ((expandedWidth - UIConstants.Size.actionButton) * searchProgress)
    }

    var searchFieldVisualHeight: CGFloat {
        UIConstants.Size.actionButton
            + ((UIConstants.Size.capsuleHeight - UIConstants.Size.actionButton) * searchProgress)
    }

    func searchFieldContainerWidth(maxWidth: CGFloat) -> CGFloat {
        searchFieldVisualWidth(maxWidth: maxWidth)
            + ((LibraryTopBarChromeMetrics.expandedHitTargetSize - UIConstants.Size.actionButton) * (1 - searchProgress))
    }

    @ViewBuilder
    var searchFieldContent: some View {
        if viewModel.isSearching && isSearchFieldInteractive {
            ZStack(alignment: .leading) {
                if viewModel.searchText.isEmpty {
                    Text(localizedSearchPrompt)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                }

                TextField("", text: $viewModel.searchText)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .tint(accent)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(!isSearchFieldInteractive)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            Text(localizedSearchPrompt)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
        }
    }

    var dismissSearchButton: some View {
        LibraryTopBarDismissSearchButton(
            action: dismissSearch
        )
    }

    @ViewBuilder
    var trailingAccessory: some View {
        LibraryTopBarTrailingAccessory(
            searchText: viewModel.searchText,
            isSearchFocused: isSearchFocused,
            clearAction: {
                withAnimation(.easeInOut(duration: UIConstants.Animation.instant)) {
                    viewModel.searchText = ""
                }
            }
        )
    }
}

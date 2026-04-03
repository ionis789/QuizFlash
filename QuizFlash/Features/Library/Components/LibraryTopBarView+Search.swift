//
//  LibraryTopBarView+Search.swift
//  QuizFlash
//
//  Search-mode composition and transitions for LibraryTopBarView.
//

import SwiftUI

extension LibraryTopBarView {
    var searchBar: some View {
        HStack(spacing: UIConstants.Spacing.small + 2) {
            searchField
            cancelButton
        }
        .frame(maxWidth: .infinity)
        .topNavigationChrome()
        .sensoryFeedback(.selection, trigger: isSearchFocused)
    }

    var searchField: some View {
        HStack(spacing: UIConstants.Spacing.small + 2) {
            LibraryTopBarSearchGlyph(
                color: isSearchFocused ? accent : Color.secondary,
                namespace: searchTransitionNamespace,
                isSource: viewModel.isSearching
            )

            searchFieldContent

            trailingAccessory
        }
        .padding(.horizontal, UIConstants.Spacing.standard)
        .frame(height: UIConstants.Size.capsuleHeight)
        .contentShape(Capsule())
        .background {
            LibraryTopBarSearchFieldBackground(
                namespace: searchTransitionNamespace,
                isSource: viewModel.isSearching
            )
        }
        .clipShape(Capsule())
        .compositingGroup()
    }

    @ViewBuilder
    var searchFieldContent: some View {
        if viewModel.isSearching {
            TextField("Search decks, cards, answers", text: $viewModel.searchText)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .tint(accent)
        } else {
            Text(viewModel.searchText.isEmpty ? "Search decks, cards, answers" : viewModel.searchText)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(viewModel.searchText.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .allowsHitTesting(false)
        }
    }

    var cancelButton: some View {
        Button {
            dismissSearch()
        } label: {
            Text("Cancel")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(accent)
                .padding(.horizontal, UIConstants.Spacing.standard)
                .frame(minWidth: 84, minHeight: UIConstants.Size.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .opacity(cancelOpacity)
        .allowsHitTesting(cancelOpacity > 0.01)
        .transition(.opacity)
        .accessibilityLabel("Cancel search")
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

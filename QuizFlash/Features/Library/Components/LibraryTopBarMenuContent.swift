//
//  LibraryTopBarMenuContent.swift
//  QuizFlash
//
//  Overflow actions for the Library top bar.
//

import SwiftUI

// MARK: - Menu Content

struct LibraryTopBarMenuContent: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Bindable var viewModel: LibraryViewModel
    let enterSelectionMode: () -> Void

    private var locale: Locale { appPreferences.resolvedLocale }

    var body: some View {
        Button(action: enterSelectionMode) {
            Label(AppLocalization.string("Select", locale: locale), systemImage: "checkmark.circle")
        }
        .disabled(viewModel.isSelecting || viewModel.isSearching)

        Button {
            viewModel.showFileImporter = true
        } label: {
            Label(AppLocalization.string("Import Deck", locale: locale), systemImage: "square.and.arrow.down")
        }

        Divider()

        Menu {
            ForEach(SortOrder.allCases, id: \.self) { order in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        viewModel.sortOrder = order
                    }
                } label: {
                    if viewModel.sortOrder == order {
                        Label(order.localizedTitle(locale: locale), systemImage: "checkmark")
                    } else {
                        Label(order.localizedTitle(locale: locale), systemImage: order.icon)
                    }
                }
            }
        } label: {
            Label(AppLocalization.string("Sort By", locale: locale), systemImage: "arrow.up.arrow.down")
        }

        Menu {

        } label: {
            Label(AppLocalization.string("Group By", locale: locale), systemImage: "arrow.up.arrow.down")
        }
    }
}

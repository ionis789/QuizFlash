//
//  LibraryTopBarMenuContent.swift
//  QuizFlash
//
//  Overflow actions for the Library top bar.
//

import SwiftUI

// MARK: - Menu Content

struct LibraryTopBarMenuContent: View {
    @Bindable var viewModel: LibraryViewModel
    let enterSelectionMode: () -> Void

    var body: some View {
        Button {
            viewModel.showFileImporter = true
        } label: {
            Label("Import Deck", systemImage: "square.and.arrow.down")
        }

        Button(action: enterSelectionMode) {
            Label("Select", systemImage: "checkmark.circle")
        }
        .disabled(viewModel.isSelecting || viewModel.isSearching)

        Divider()

        Menu {
            ForEach(SortOrder.allCases, id: \.self) { order in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        viewModel.sortOrder = order
                    }
                } label: {
                    if viewModel.sortOrder == order {
                        Label(order.rawValue, systemImage: "checkmark")
                    } else {
                        Label(order.rawValue, systemImage: order.icon)
                    }
                }
            }
        } label: {
            Label("Sort By", systemImage: "arrow.up.arrow.down")
        }

        Menu {

        } label: {
            Label("Group By", systemImage: "arrow.up.arrow.down")
        }
    }
}

//
//  LibraryTopBarView.swift
//  QuizFlash
//
//  Design language: iOS 26 floating-element style.
//
//  Layout (non-search):
//    ┌─────────────────────────────────────┐
//    │ [N Decks]    Library    [🔍  ···]   │
//    └─────────────────────────────────────┘
//
//  • Deck-count → standalone dark capsule, left-anchored.
//  • Title       → plain text, true-centered in ZStack.
//  • Actions     → search + menu grouped inside a single dark pill, right-anchored.
//    This mirrors the iOS 26 grouped-icon pill pattern (see reference screenshot).
//
//  Dark-frosted fill: .ultraThinMaterial + black tint overlay — produces the
//  near-black semi-transparent look native to iOS 26 controls without
//  requiring a custom UIVisualEffectView wrapper.

import SwiftUI

// MARK: - LibraryTopBarView

struct LibraryTopBarView: View {
    let title: String
    let deckCount: Int
    @Bindable var viewModel: LibraryViewModel
    @Binding var searchText: String
    @Binding var isSearching: Bool

    var isScrolled: Bool = false

    @FocusState private var isSearchFocused: Bool
    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        VStack(spacing: 0) {
            if isSearching {
                searchBar
            } else {
                titleRow
            }
        }
        .onChange(of: isSearching) { _, active in
            if active { isSearchFocused = true }
        }
    }

    // MARK: - Title Row

    private var titleRow: some View {
        ZStack(alignment: .center) {
            // Left: deck count — standalone dark capsule
            HStack {
                deckCountPill
                Spacer()
            }

            // Center: screen title
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            // Right: search + menu grouped in a single pill (iOS 26 pattern)
            HStack {
                Spacer()
                actionGroupPill
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            // Dark-frosted search field matching the pill aesthetic
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)

                TextField("Search decks & cards…", text: $searchText)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .font(.system(size: 15))
                    .padding(.vertical, 10)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.trailing, 12)
                }
            }
            .background(darkPillBackground(cornerRadius: 14))

            Button("Cancel") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearching = false
                    searchText = ""
                    isSearchFocused = false
                }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(accent)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    // MARK: - Subviews

    /// Deck count badge — standalone dark capsule, left-anchored.
    private var deckCountPill: some View {
        Text(deckCount == 0 ? "No Decks" : "\(deckCount) Deck\(deckCount == 1 ? "" : "s")")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(height: 50)
            .background(darkPillBackground(cornerRadius: 20))
    }

    /// Search + menu icons grouped inside a single pill — mirrors the
    /// iOS 26 center-control pill but placed on the trailing side.
    private var actionGroupPill: some View {
        HStack(spacing: 0) {
            // Search icon
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearching = true
                    isSearchFocused = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3.bold())
                    .foregroundStyle(accent)
                    .frame(width: 46, height: 46)
            }

            // Menu icon
            Menu { menuContent } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.bold())
                    .foregroundStyle(accent)
                    .frame(width: 52, height: 52)
            }
        }
        .background(darkPillBackground(cornerRadius: 18))
    }

    // MARK: - Shared Dark-Frosted Background

    /// iOS 26-style dark frosted fill used by all floating elements.
    /// Layer order:
    ///   1. .ultraThinMaterial — live blur of content behind the pill.
    ///   2. Black tint overlay  — darkens to near-black, matching iOS 26 tone.
    ///   3. Hairline stroke     — top-edge highlight that gives glass depth.
    private func darkPillBackground(cornerRadius: CGFloat) -> some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .fill(accent.opacity(0.15))
            )
    }

    // MARK: - Menu Content

    @ViewBuilder
    private var menuContent: some View {
        Button { viewModel.showFileImporter = true } label: {
            Label("Import Deck", systemImage: "square.and.arrow.down")
        }

        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                viewModel.isSelecting = true
            }
        } label: {
            Label("Select", systemImage: "checkmark.circle")
        }
        .disabled(viewModel.isSelecting || isSearching)

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
    }
}

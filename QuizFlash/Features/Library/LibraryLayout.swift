//
//  LibraryLayout.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

// MARK: - Preference Key
struct LibraryScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Layout
struct LibraryLayout: View {

    let decks: [DeckModel]
    @Bindable var viewModel: LibraryViewModel
    let router: NavigationManager

    let onCardTap: (PersistentIdentifier) -> Void
    let onDeckNavigate: (DeckModel) -> Void
    let onDeleteSelected: () -> Void

    @State private var scrollOffset: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy? = nil

    private let topAnchorID = "LIBRARY_TOP_ANCHOR"
    private var accent: Color { ThemeManager.shared.accentColor.color }

    // Arrow is visible once user scrolls down more than 80pt
    private var showScrollToTop: Bool { scrollOffset < -80 }

    private var groupedDecks: [DeckSection] {
        LibraryGrouping.sections(decks: decks, sortOrder: viewModel.sortOrder)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {

            // ── Main scroll area ──────────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Zero-height anchor at the very top — reliable scroll target
                        Color.clear
                            .frame(height: 0)
                            .id(topAnchorID)

                        if viewModel.isSearching {
                            searchResultsLayer
                        } else if decks.isEmpty {
                            LibraryEmptyStateView()
                        } else {
                            LibraryListView(
                                groupedDecks: groupedDecks,
                                viewModel: viewModel,
                                onNavigate: onDeckNavigate
                            )
                        }
                    }
                    .padding(.top, 8)
                    .safeAreaInset(edge: .bottom) {
                        Color.clear
                            .frame(height: viewModel.isSelecting ? 150 : 60)
                            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isSelecting)
                    }
                    // Scroll offset tracking
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: LibraryScrollOffsetKey.self,
                                value: geo.frame(in: .named("libraryScroll")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "libraryScroll")
                .onPreferenceChange(LibraryScrollOffsetKey.self) { value in
                    scrollOffset = value
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard viewModel.isSelecting else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.exitSelectionMode()
                    }
                }
                .safeAreaInset(edge: .top) {
                    LibraryTopBarView(viewModel: viewModel, deckCount: decks.count)
                }
                // Store proxy so the FAB can use it
                .onAppear { scrollProxy = proxy }
            }

            // ── Scroll-to-top FAB (lives in the outer ZStack, always visible) ─
            if showScrollToTop && !viewModel.isSelecting {
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        scrollProxy?.scrollTo(topAnchorID, anchor: .top)
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.trailing, 16)
                .padding(.bottom, 80) // clears the tab bar
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .zIndex(5)
            }

            // ── Selection bottom bar ──────────────────────────────────────────
            if viewModel.isSelecting && !viewModel.isSearching {
                LibrarySelectionBarView(
                    viewModel: viewModel,
                    decks: decks,
                    onDeleteTap: { viewModel.showDeleteConfirmation = true }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }

            // ── Loading overlay ───────────────────────────────────────────────
            if viewModel.isImporting || viewModel.isExporting {
                LibraryLoadingOverlay(
                    message: viewModel.isImporting
                        ? "Importing…"
                        : "Exporting \(viewModel.selectedDecks.count) deck\(viewModel.selectedDecks.count == 1 ? "" : "s")…"
                )
                .zIndex(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity) // fill screen
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: showScrollToTop)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isSelecting)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSearching)
    }

    // MARK: - Search layer
    private var searchResultsLayer: some View {
        SearchResultsView(
            results: viewModel.searchResults,
            query: viewModel.searchText,
            onCardTap: onCardTap
        )
        .overlay {
            if viewModel.isSearchLoading {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    ProgressView().scaleEffect(1.3).tint(accent)
                }
                .transition(.opacity)
            }
        }
    }
}

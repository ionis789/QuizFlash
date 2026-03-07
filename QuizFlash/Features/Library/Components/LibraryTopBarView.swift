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

//  requiring a custom UIVisualEffectView wrapper.

import SwiftUI

// MARK: - LibraryTopBarView

/// A floating top navigation bar tailored for the Library view and its derived contexts.
/// Mimics the iOS 26 grouped-icon aesthetics with robust multi-layer interactions.
struct LibraryTopBarView: View {
    let title: String
    let deckCount: Int
    @Bindable var viewModel: LibraryViewModel
    
    var isScrolled: Bool = false
    /// When non-nil, a back button is shown on the left instead of the deck-count pill.
    var onBack: (() -> Void)? = nil
    /// Text shown inside the back button pill. Only used when onBack != nil.
    var backLabel: String = "Library"

    @FocusState private var isSearchFocused: Bool
    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isSearching {
                searchBar
            } else {
                titleRow
            }
        }
            .onChange(of: viewModel.isSearching) { _, active in
            if active { isSearchFocused = true }
        }
    }

    // MARK: - Title Row

    private var titleRow: some View {
        ZStack(alignment: .center) {

            // Center layer: title + deck count, absolutely centred in the ZStack.
            // This layer is intentionally excluded from the HStack below so its
            // position is never shifted by the varying widths of the sidebar controls.
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                deckCountPill
            }

            // Sidebar layer: a single HStack owns BOTH the leading and trailing
            // controls. This is the direct fix for two bugs caused by the previous
            // two-layer approach (.frame(maxWidth: .infinity) on each side):
            //
            // Bug 1 — Text truncation ("H..."):
            //   Two separate maxWidth:infinity layers inside a ZStack each resolve
            //   independently to the ZStack's proposed width. During a NavigationStack
            //   interactive swipe-back, SwiftUI repeatedly proposes an intermediate
            //   compressed width. Both layers momentarily race to claim that narrow
            //   width, collapsing the leading Group to near-zero before fixedSize can
            //   correct it. A single HStack+Spacer makes one coherent layout pass and
            //   never proposes zero to either child.
            //
            // Bug 2 — Leading control flicker/overlap:
            //   Without explicit .id() tags, SwiftUI's reconciler treats the Group at
            //   the same ZStack slot in the pushed view (backButton) and the root view
            //   (searchIcon) as the same view, attempting to morph between them during
            //   the slide transition. Stable identity tags force a clean insert/remove.
            HStack(spacing: 0) {
                leadingControl
                // Guarantees the leading view is always proposed its ideal width,
                // even if the ZStack receives a compressed proposal mid-transition.
                .fixedSize()
                Spacer(minLength: 0)
                moreSettingsButton
            }
        }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)
    }

    // MARK: - Leading Control

    /// Resolves to a back button (folder context) or a search icon (root context).
    ///
    /// Explicit `.id()` tags are required to prevent SwiftUI from cross-fading
    /// between the two variants during a NavigationStack slide transition. Without
    /// them, the reconciler sees the same structural position in both the pushed
    /// and root LibraryTopBarView instances and tries to animate one shape into the
    /// other — producing a visible overlap glitch at the start of the gesture.
    @ViewBuilder
    private var leadingControl: some View {
        if let onBackAction = onBack {
            backButton(action: onBackAction)
                .id("topbar.leading.back")
        } else {
            searchIcon
                .id("topbar.leading.search")
        }
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

                TextField("Search decks & cards…", text: $viewModel.searchText)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .font(.system(size: 15))
                    .padding(.vertical, 10)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.clearSearch()
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
                    viewModel.clearSearch()
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
            .font(.system(size: 13, weight: .bold))
            .fontDesign(.rounded)
            .foregroundStyle(.secondary)
    }

    private var searchIcon: some View {
        // Search icon
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.isSearching = true
                isSearchFocused = true
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.title3.bold())
                .foregroundStyle(accent)
        }
            .frame(width: 50, height: 50)
            .contentShape(Circle())
            .background {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                Circle()
                    .fill(Color.white.opacity(0.35))
                    .blur(radius: 10)
                    .mask(Capsule().stroke(lineWidth: 4))
                    .blendMode(.overlay)
            }
        }
    }

    private var moreSettingsButton: some View {
        // Menu icon
        Menu { menuContent } label: {
            Image(systemName: "ellipsis")
                .font(.title3.bold())
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
            .frame(width: 50, height: 50)
            .contentShape(Circle())
            .background {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                Circle()
                    .fill(Color.white.opacity(0.35))
                    .blur(radius: 10)
                    .mask(Capsule().stroke(lineWidth: 4))
                    .blendMode(.overlay)
            }
        }
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

    // MARK: - Back Button

    /// Pill-shaped back button shown when the view is pushed (folder context).
    /// Mirrors the deck-count pill dimensions so the layout stays balanced.
    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.compact.left")
                    .font(.system(size: 24, weight: .bold))
                Text(backLabel)
                    .font(.system(size: 13, weight: .semibold))
            }
            // Secondary guard: keeps the label from collapsing in edge-case
            // layout passes where the Button itself receives a narrow proposal.
            .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(height: 50)
                .foregroundStyle(accent)
                .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .blur(radius: 10)
                        .mask(Capsule().stroke(lineWidth: 4))
                        .blendMode(.overlay)
                }
            }
        }
            .buttonStyle(.plain)
    }
}

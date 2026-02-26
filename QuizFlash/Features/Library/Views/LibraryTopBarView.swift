import SwiftUI

struct LibraryTopBarView: View {
    @Bindable var viewModel: LibraryViewModel

    @Binding var isMenuExpanded: Bool
    @Binding var menuPosition: CGRect
    let showInlineTitle: Bool

    @Binding var isSearching: Bool
    @Binding var searchText: String
    @FocusState private var isSearchFocused: Bool

    // ── Stare pentru spinner-ul butonului X ──
    @State private var isSpinning: Bool = false

    let decksCount: Int
    let onHeaderTap: () -> Void

    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        HStack(spacing: 12) {
            if isSearching {
                searchModeView
            } else {
                defaultModeView
            }
        }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { if !isSearching { onHeaderTap() } }
            .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(showInlineTitle || isSearching ? 1 : 0)
                .ignoresSafeArea(edges: .top)
        )
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSearching)
    }

    // MARK: - Search Mode View
    @ViewBuilder
    private var searchModeView: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.headline.bold())
                .foregroundStyle(accent)

            TextField("Search decks & cards...", text: $searchText)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .focused($isSearchFocused)
                .submitLabel(.search)
                .tint(accent)

            if !searchText.isEmpty {
                clearSearchButton
                    .transition(.scale.combined(with: .opacity))
            }
        }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())

        Button("Cancel") {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isSearching = false
                searchText = ""
                isSearchFocused = false
            }
        }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(accent)
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .onAppear {
            isSearchFocused = true
        }
    }

    @ViewBuilder
    private var clearSearchButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                searchText = ""
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2.bold())
                .foregroundStyle(Color.accentColor.opacity(0.7))
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(
                isSpinning
                    ? .linear(duration: 0.25).repeatForever(autoreverses: false) // ⚡️ Mai rapid (0.25s o rotație completă)
                : .easeOut(duration: 0.3),
                value: isSpinning
            )
                .onChange(of: viewModel.isSearchLoading) { oldValue, newValue in
                if newValue {
                    isSpinning = true // Începe rotația imediat
                } else {
                    // ⏳ Adăugăm o întârziere de 0.3 secunde ca să se vadă efectul
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isSpinning = false
                    }
                }
            }
                .onAppear {
                isSpinning = viewModel.isSearchLoading
            }
        }
    }

    // MARK: - Default Mode View
    @ViewBuilder
    private var defaultModeView: some View {
        if showInlineTitle {
            VStack(alignment: .leading, spacing: 0) {
                Text("Library")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(decksCount == 0 ? "No Decks" : "\(decksCount) Deck\(decksCount == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
                .transition(
                    .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 12)),
                    removal: .opacity.combined(with: .offset(y: 12))
                )
            )
        }

        Spacer()

        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isSearching = true
            }
        } label: {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "magnifyingglass")
                    .font(.headline.bold())
                    .foregroundStyle(.primary)
            }
        }

        Button {
            withAnimation(.smooth) { isMenuExpanded.toggle() }
        } label: {
            ZStack {
                Circle()
                    .fill(accent.opacity(isMenuExpanded ? 1.0 : 0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "ellipsis")
                    .font(.headline.bold())
                    .foregroundStyle(isMenuExpanded ? .white : accent)
            }
        }
            .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { newValue in
            menuPosition = newValue
        }
    }
}

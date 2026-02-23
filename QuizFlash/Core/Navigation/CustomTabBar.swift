import SwiftUI

struct CustomTabBar: View {
    @Binding var activeTab: AppTab
    @Binding var searchText: String
    var onSearchBarExpanded: (Bool) -> ()
    var onSearchTextFieldActive: (Bool) -> ()
    private var accent: Color { ThemeManager.shared.accentColor.color }

    @GestureState private var isActive: Bool = false
    @State private var isInitialOffsetSet: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var lastDragOffset: CGFloat?

    @State private var isSearchExpanded: Bool = false
    @FocusState private var isKeyboardActive: Bool

    // Helper to check for iPad
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let tabs = AppTab.allCases
            let tabItemWidth = max(min(size.width / CGFloat(tabs.count + 1), 90), 60)
            let tabItemHeight: CGFloat = 56

            ZStack {
                if isInitialOffsetSet {
                    let mainLayout = isSearchExpanded ? AnyLayout(ZStackLayout(alignment: .leading)) : AnyLayout(HStackLayout(spacing: 12))

                    mainLayout {
                        let tabLayout = isSearchExpanded ? AnyLayout(ZStackLayout()) : AnyLayout(HStackLayout(spacing: 0))

                        tabLayout {
                            ForEach(tabs, id: \.rawValue) { tab in
                                TabItemView(
                                    tab,
                                    width: isSearchExpanded ? 45 : tabItemWidth,
                                    height: isSearchExpanded ? 45 : tabItemHeight
                                )
                                    .opacity(isSearchExpanded ? (activeTab == tab ? 1 : 0) : 1)
                            }
                        }
                            .background(alignment: .leading) {
                            ZStack {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.15))

                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    .opacity(isActive ? 1 : 0)
                            }
                                .compositingGroup()
                                .frame(width: tabItemWidth, height: tabItemHeight)
                                .scaleEffect(isActive ? 1.3 : 1)
                                .offset(x: isSearchExpanded ? 0 : dragOffset)
                                .opacity(isSearchExpanded ? 0 : 1)
                        }
                            .padding(3)
                            .background(TabBarBackground())
                            .overlay {
                            if isSearchExpanded {
                                Capsule()
                                    .foregroundStyle(.clear)
                                    .contentShape(.capsule)
                                    .onTapGesture {
                                    withAnimation(.bouncy) {
                                        isSearchExpanded = false
                                        isKeyboardActive = false
                                    }
                                }
                            }
                        }
                            .opacity(isSearchExpanded ? 0 : 1)

                        ExpandableSearchBar(height: isSearchExpanded ? 45 : tabItemHeight)
                    }
                        .geometryGroup()
                }
            }
            // CHANGED: Use .bottomTrailing if iPad, otherwise .bottom (center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isIPad ? .bottomTrailing : .bottom)
                .onAppear {
                guard !isInitialOffsetSet else { return }
                dragOffset = CGFloat(activeTab.index) * tabItemWidth
                isInitialOffsetSet = true
            }
        }
            .frame(height: 56)
            .padding(.horizontal, 25)
            .padding(.bottom, isSearchExpanded ? 10 : 0)
            .animation(.bouncy, value: dragOffset)
            .animation(.bouncy, value: isActive)
            .animation(.smooth, value: activeTab)
            .animation(.easeInOut(duration: 0.25), value: isSearchExpanded)
            .onChange(of: isKeyboardActive) { _, newValue in onSearchTextFieldActive(newValue) }
            .onChange(of: isSearchExpanded) { _, newValue in onSearchBarExpanded(newValue) }

    }

// ... TabItemView, TabBarBackground, and ExpandableSearchBar remain the same
// (Ensure you keep the rest of your original implementation below)

    @ViewBuilder
    private func TabItemView(_ tab: AppTab, width: CGFloat, height: CGFloat) -> some View {
        let tabs = AppTab.allCases
        let tabCount = tabs.count - 1

        VStack(spacing: 6) {
            Image(systemName: tab.symbol)
                .font(.title2)
                .symbolVariant(.fill)

            if !isSearchExpanded {
                Text(tab.rawValue)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(
            activeTab == tab && !isSearchExpanded ? accent : Color.primary
        )
            .frame(width: width, height: height)
            .contentShape(.capsule)
            .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isActive) { _, out, _ in out = true }
                .onChanged { value in
                let xOffset = value.translation.width
                if let lastDragOffset {
                    let newDragOffset = xOffset + lastDragOffset
                    dragOffset = max(min(newDragOffset, CGFloat(tabCount) * width), 0)
                } else {
                    lastDragOffset = dragOffset
                }
            }
                .onEnded { value in
                lastDragOffset = nil
                let landingIndex = Int((dragOffset / width).rounded())
                if tabs.indices.contains(landingIndex) {
                    dragOffset = CGFloat(landingIndex) * width
                    activeTab = tabs[landingIndex]
                }
            }
        )
            .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                activeTab = tab
                dragOffset = CGFloat(tab.index) * width
            }
        )
            .geometryGroup()
    }

    @ViewBuilder
    private func TabBarBackground() -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func ExpandableSearchBar(height: CGFloat) -> some View {
        let searchLayout = isSearchExpanded ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(ZStackLayout(alignment: .trailing))

        searchLayout {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.bouncy) {
                        isSearchExpanded = true
                        isKeyboardActive = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(isSearchExpanded ? .body : .title2)
                        .foregroundStyle(isSearchExpanded ? .gray : Color.primary)
                        .frame(width: isSearchExpanded ? nil : height, height: height)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .allowsHitTesting(!isSearchExpanded)

                if isSearchExpanded {
                    TextField("Search...", text: $searchText)
                        .focused($isKeyboardActive)
                        .onAppear {
                        isKeyboardActive = true
                    }
                }
            }
                .padding(.horizontal, isSearchExpanded ? 15 : 0)
                .background(TabBarBackground())
                .geometryGroup()
                .zIndex(1)

            if isSearchExpanded {
                Button {
                    withAnimation(.bouncy) {
                        searchText = ""
                        isKeyboardActive = false
                        isSearchExpanded = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundStyle(Color.primary)
                        .frame(width: height, height: height)
                        .contentShape(Rectangle())
                        .background(TabBarBackground())
                }
                    .buttonStyle(.plain)
                    .transition(.opacity)
            }
        }
    }
}

import SwiftUI

struct CustomTabBar: View {
    @Binding var activeTab: AppTabBar
    private var accent: Color { ThemeManager.shared.accentColor.color }

    @GestureState private var isActive: Bool = false
    @State private var isInitialOffsetSet: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var lastDragOffset: CGFloat?
    @State private var tabTriggers: [AppTabBar: Int] = [.library: 0, .create: 0, .home: 0]

    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let tabs = AppTabBar.allCases
            let tabItemWidth = max(min(size.width / CGFloat(tabs.count), 90), 60)
            let tabItemHeight: CGFloat = 56

            ZStack {
                if isInitialOffsetSet {
                    HStack(spacing: 0) {
                        ForEach(tabs, id: \.rawValue) { tab in
                            TabItemView(tab, width: tabItemWidth, height: tabItemHeight)
                        }
                    }
                        .background(alignment: .leading) {
                        ZStack {
                            Capsule(style: .continuous).fill(Color.white.opacity(0.15))
                            Capsule(style: .continuous).stroke(Color.white.opacity(0.3), lineWidth: 1)
                                .opacity(isActive ? 1 : 0)
                        }
                        .frame(width: tabItemWidth, height: tabItemHeight)
                        .scaleEffect(isActive ? 1.3 : 1)
                        .offset(x: dragOffset)
                        .animation(.easeInOut(duration: UIConstants.Animation.instant), value: isActive)
                    }
                        .padding(3)
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
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isIPad ? .bottomTrailing : .bottom)
                .onAppear {
                guard !isInitialOffsetSet else { return }
                dragOffset = CGFloat(activeTab.index) * tabItemWidth
                isInitialOffsetSet = true
            }
                .onChange(of: activeTab) { _, newTab in
                guard lastDragOffset == nil else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    dragOffset = CGFloat(newTab.index) * tabItemWidth
                }
            }
        }
            .frame(height: 56)
            .padding(.horizontal, 25)
    }

    @ViewBuilder
    private func TabItemView(_ tab: AppTabBar, width: CGFloat, height: CGFloat) -> some View {
        let tabs = AppTabBar.allCases
        let tabCount = tabs.count - 1

        VStack(spacing: 6) {
            Image(systemName: tab.symbol)
                .font(.title2)
                .symbolVariant(.fill)
                .symbolEffect(.bounce.up.byLayer, value: tabTriggers[tab, default: 0])

            Text(tab.rawValue)
                .font(.caption2)
                .lineLimit(1)
        }
            .foregroundStyle(activeTab == tab ? accent : Color.primary)
            .frame(width: width, height: height)
            .contentShape(.capsule)
            .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isActive) { _, out, _ in out = true }
                .onChanged { value in
                let xOffset = value.translation.width
                if let lastDragOffset {
                    dragOffset = max(min(xOffset + lastDragOffset, CGFloat(tabCount) * width), 0)
                } else { lastDragOffset = dragOffset }
            }
                .onEnded { value in
                lastDragOffset = nil
                let landingIndex = Int((dragOffset / width).rounded())
                if tabs.indices.contains(landingIndex) {
                    let newTab = tabs[landingIndex]
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        dragOffset = CGFloat(landingIndex) * width
                    }
                    if activeTab != newTab {
                        activeTab = newTab
                        tabTriggers[newTab, default: 0] += 1
                    }
                }
            }
        )
            .simultaneousGesture(
            TapGesture().onEnded { _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    dragOffset = CGFloat(tab.index) * width
                }
                activeTab = tab
                tabTriggers[tab, default: 0] += 1
            }
        )
    }
}

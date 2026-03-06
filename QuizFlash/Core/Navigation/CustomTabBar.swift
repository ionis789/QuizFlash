import SwiftUI

struct CustomTabBar: View {
    @Binding var activeTab: AppTab
    private var accent: Color { ThemeManager.shared.accentColor.color }

    @GestureState private var isActive: Bool = false
    @State private var isInitialOffsetSet: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var lastDragOffset: CGFloat?
    @State private var tabTriggers: [AppTab: Int] = [.library: 0, .create: 0, .home: 0]

    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let tabs = AppTab.allCases
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
                            .compositingGroup()
                            .frame(width: tabItemWidth, height: tabItemHeight)
                            .scaleEffect(isActive ? 1.3 : 1)
                            .offset(x: dragOffset)
                    }
                        .padding(3)
                    // MARK: Tabbar Background
//                    .background(Capsule().fill(.ultraThinMaterial))
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
                        .geometryGroup()
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isIPad ? .bottomTrailing : .bottom)
                .onAppear {
                guard !isInitialOffsetSet else { return }
                dragOffset = CGFloat(activeTab.index) * tabItemWidth
                isInitialOffsetSet = true
            }
        }
            .frame(height: 56)
            .padding(.horizontal, 25)
            .animation(.bouncy, value: dragOffset)
            .animation(.bouncy, value: isActive)
            .animation(.smooth, value: activeTab)
    }

    @ViewBuilder
    private func TabItemView(_ tab: AppTab, width: CGFloat, height: CGFloat) -> some View {
        let tabs = AppTab.allCases
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
                    dragOffset = CGFloat(landingIndex) * width
                    if activeTab != newTab {
                        activeTab = newTab
                        tabTriggers[newTab, default: 0] += 1
                    }
                }
            }
        )
            .simultaneousGesture(
            TapGesture().onEnded { _ in
                activeTab = tab
                dragOffset = CGFloat(tab.index) * width
                tabTriggers[tab, default: 0] += 1
            }
        )
    }
}

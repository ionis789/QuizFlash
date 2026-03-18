//
//  CustomTabBar.swift
//  QuizFlash
//
//  SwiftUI-owned tab bar UI backed by a UIKit capsule animator.
//

import SwiftUI

/// The floating app tab bar.
///
/// SwiftUI owns the visual layout so the bar can be restyled locally, while a
/// UIKit-backed capsule animator keeps the selection motion smooth when the
/// destination `TabView` screen is expensive to render.
struct CustomTabBar: View {
    let activeTab: AppTabBar
    var onTabSelection: (AppTabBar) -> Void

    @GestureState private var isActive = false
    @State private var isInitialOffsetSet = false
    @State private var visualTab: AppTabBar = .home
    @State private var dragOffset: CGFloat = 0
    @State private var lastDragOffset: CGFloat?
    @State private var pendingTargetTab: AppTabBar?
    @State private var pendingCommitTask: Task<Void, Never>?

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let tabs = AppTabBar.allCases
            let tabItemWidth = max(min(size.width / CGFloat(tabs.count), 90), 60)
            let tabItemHeight = UIConstants.Size.bottomChromeControl
            let chromeHorizontalPadding = UIConstants.Layout.bottomChromeInnerHorizontalPadding / 2
            let chromeVerticalPadding = UIConstants.Layout.bottomChromeInnerVerticalPadding

            ZStack {
                if isInitialOffsetSet {
                    HStack(spacing: 0) {
                        ForEach(tabs, id: \.rawValue) { tab in
                            tabItemView(tab, width: tabItemWidth, height: tabItemHeight)
                        }
                    }
                    .background(alignment: .leading) {
                        UIKitTabBarSelectionAnimator(
                            offset: dragOffset,
                            itemWidth: tabItemWidth,
                            itemHeight: tabItemHeight,
                            isInteracting: isActive
                        )
                    }
                    .padding(.horizontal, chromeHorizontalPadding)
                    .padding(.vertical, chromeVerticalPadding)
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
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: isIPad ? .bottomTrailing : .bottom
            )
            .onAppear {
                guard !isInitialOffsetSet else { return }
                syncVisualState(to: activeTab, width: tabItemWidth)
                isInitialOffsetSet = true
            }
            .onChange(of: activeTab) { _, newValue in
                if pendingTargetTab == newValue {
                    pendingCommitTask?.cancel()
                    pendingCommitTask = nil
                    pendingTargetTab = nil
                }

                syncVisualState(to: newValue, width: tabItemWidth)
            }
            .onDisappear {
                pendingCommitTask?.cancel()
                pendingCommitTask = nil
                pendingTargetTab = nil
            }
        }
        .frame(height: UIConstants.Size.bottomChromeBarHeight)
        .padding(.horizontal, 25)
        .animation(.smooth, value: visualTab)
        .animation(.bouncy, value: isActive)
    }

    @ViewBuilder
    private func tabItemView(_ tab: AppTabBar, width: CGFloat, height: CGFloat) -> some View {
        let tabs = AppTabBar.allCases
        let tabCount = tabs.count - 1

        VStack(spacing: 6) {
            Image(systemName: tab.symbol)
                .font(.title2)
                .symbolVariant(.fill)

            Text(tab.title)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(visualTab == tab ? accent : Color.primary)
        .frame(width: width, height: height)
        .contentShape(.capsule)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isActive) { _, out, _ in out = true }
                .onChanged { value in
                    let xOffset = value.translation.width
                    if let lastDragOffset {
                        dragOffset = max(min(xOffset + lastDragOffset, CGFloat(tabCount) * width), 0)
                    } else {
                        lastDragOffset = dragOffset
                    }

                    let hoveredIndex = Int((dragOffset / width).rounded())
                    if tabs.indices.contains(hoveredIndex) {
                        visualTab = tabs[hoveredIndex]
                    }
                }
                .onEnded { _ in
                    lastDragOffset = nil

                    let landingIndex = Int((dragOffset / width).rounded())
                    guard tabs.indices.contains(landingIndex) else { return }

                    let newTab = tabs[landingIndex]
                    dragOffset = CGFloat(landingIndex) * width
                    visualTab = newTab

                    if newTab == activeTab {
                        pendingCommitTask?.cancel()
                        pendingCommitTask = nil
                        pendingTargetTab = nil
                        return
                    }

                    scheduleCommit(for: newTab)
                }
        )
        .simultaneousGesture(
            TapGesture().onEnded { _ in
                if pendingTargetTab != nil, tab == activeTab {
                    pendingCommitTask?.cancel()
                    pendingCommitTask = nil
                    pendingTargetTab = nil
                    syncVisualState(to: activeTab, width: width)
                    return
                }

                visualTab = tab
                dragOffset = CGFloat(tab.index) * width

                if tab == activeTab {
                    pendingCommitTask?.cancel()
                    pendingCommitTask = nil
                    pendingTargetTab = nil
                    onTabSelection(tab)
                    return
                }

                scheduleCommit(for: tab)
            }
        )
    }

    private func syncVisualState(to tab: AppTabBar, width: CGFloat) {
        visualTab = tab
        dragOffset = CGFloat(tab.index) * width
    }

    private func scheduleCommit(for tab: AppTabBar) {
        pendingCommitTask?.cancel()
        pendingTargetTab = tab
        emitSwitchHaptic()

        pendingCommitTask = Task { @MainActor in
            let delayNanoseconds = UInt64(UIConstants.Animation.tabBarCommitDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }

            pendingCommitTask = nil
            pendingTargetTab = nil
            onTabSelection(tab)
        }
    }

    private func emitSwitchHaptic() {
        let feedback = UIImpactFeedbackGenerator(style: .soft)
        feedback.prepare()
        feedback.impactOccurred(intensity: 0.5)
    }
}

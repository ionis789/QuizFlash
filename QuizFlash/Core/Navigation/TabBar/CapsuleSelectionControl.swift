//
//  CapsuleSelectionControl.swift
//  QuizFlash
//
//  Reusable capsule selector that shares the custom tab bar's motion system.
//

import SwiftUI

/// A reusable capsule selector powered by the same delayed commit and UIKit-backed
/// selection motion used by the app tab bar.
struct CapsuleSelectionControl<Option: Hashable, Label: View>: View {
    @Environment(ThemeManager.self) private var themeManager

    let options: [Option]
    let selection: Option
    var onSelection: (Option) -> Void
    var onReselect: ((Option) -> Void)? = nil
    var itemHeight: CGFloat = UIConstants.Size.bottomChromeControl
    var controlHeight: CGFloat = UIConstants.Size.bottomChromeBarHeight
    var minItemWidth: CGFloat = 60
    var maxItemWidth: CGFloat = 90
    var horizontalPadding: CGFloat = UIConstants.Layout.bottomChromeInnerHorizontalPadding / 2
    var verticalPadding: CGFloat = UIConstants.Layout.bottomChromeInnerVerticalPadding
    @ViewBuilder var label: (Option, Bool) -> Label

    @GestureState private var isActive = false
    @State private var isInitialOffsetSet = false
    @State private var dragOffset: CGFloat = 0
    @State private var lastDragOffset: CGFloat?
    @State private var pendingTarget: Option?
    @State private var pendingCommitTask: Task<Void, Never>?

    init(
        options: [Option],
        selection: Option,
        onSelection: @escaping (Option) -> Void,
        onReselect: ((Option) -> Void)? = nil,
        itemHeight: CGFloat = UIConstants.Size.bottomChromeControl,
        controlHeight: CGFloat = UIConstants.Size.bottomChromeBarHeight,
        minItemWidth: CGFloat = 60,
        maxItemWidth: CGFloat = 90,
        horizontalPadding: CGFloat = UIConstants.Layout.bottomChromeInnerHorizontalPadding / 2,
        verticalPadding: CGFloat = UIConstants.Layout.bottomChromeInnerVerticalPadding,
        @ViewBuilder label: @escaping (Option, Bool) -> Label
    ) {
        self.options = options
        self.selection = selection
        self.onSelection = onSelection
        self.onReselect = onReselect
        self.itemHeight = itemHeight
        self.controlHeight = controlHeight
        self.minItemWidth = minItemWidth
        self.maxItemWidth = maxItemWidth
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.label = label
    }

    var body: some View {
        GeometryReader { proxy in
            let availableRowWidth = max(0, proxy.size.width - (horizontalPadding * 2))
            let itemWidth = resolvedItemWidth(availableWidth: availableRowWidth)

            ZStack {
                if isInitialOffsetSet {
                    ZStack {
                        displayRow(width: itemWidth, height: itemHeight, usesSelectedStyle: false)
                        displayRow(width: itemWidth, height: itemHeight, usesSelectedStyle: true)
                            .mask(alignment: .leading) {
                                selectionCapsule(fillColor: .white, width: itemWidth)
                            }
                        interactionRow(width: itemWidth, height: itemHeight)
                    }
                    .background(alignment: .leading) {
                        selectionCapsule(
                            fillColor: themeManager.roleColor(.tabSelectionFill),
                            width: itemWidth
                        )
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .background {
                        Capsule()
                            .fill(themeManager.roleColor(.tabBarTrackFill))
                    }
                    .geometryGroup()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .onAppear {
                guard !isInitialOffsetSet else { return }
                syncVisualState(to: selection, width: itemWidth)
                isInitialOffsetSet = true
            }
            .onChange(of: selection) { _, newValue in
                if pendingTarget == newValue {
                    pendingCommitTask?.cancel()
                    pendingCommitTask = nil
                    pendingTarget = nil
                }

                syncVisualState(to: newValue, width: itemWidth)
            }
            .onDisappear {
                pendingCommitTask?.cancel()
                pendingCommitTask = nil
                pendingTarget = nil
            }
        }
        .frame(height: controlHeight)
    }

    private func displayRow(
        width: CGFloat,
        height: CGFloat,
        usesSelectedStyle: Bool
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { item in
                label(item.element, usesSelectedStyle)
                    .frame(width: width, height: height)
                    .allowsHitTesting(false)
            }
        }
    }

    private func interactionRow(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { item in
                interactionHitTarget(
                    option: item.element,
                    index: item.offset,
                    width: width,
                    height: height
                )
            }
        }
    }

    @ViewBuilder
    private func interactionHitTarget(
        option: Option,
        index: Int,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        Color.clear
            .frame(width: width, height: height)
            .contentShape(.capsule)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isActive) { _, out, _ in out = true }
                    .onChanged { value in
                        let xOffset = value.translation.width
                        if let lastDragOffset {
                            dragOffset = clampedOffset(xOffset + lastDragOffset, width: width)
                        } else {
                            lastDragOffset = dragOffset
                        }
                    }
                    .onEnded { _ in
                        lastDragOffset = nil

                        let landingIndex = Int((dragOffset / width).rounded())
                        guard options.indices.contains(landingIndex) else { return }

                        let newSelection = options[landingIndex]
                        dragOffset = CGFloat(landingIndex) * width

                        if newSelection == selection {
                            pendingCommitTask?.cancel()
                            pendingCommitTask = nil
                            pendingTarget = nil
                            return
                        }

                        scheduleCommit(for: newSelection)
                    }
            )
            .simultaneousGesture(
                TapGesture().onEnded { _ in
                    if pendingTarget != nil, option == selection {
                        pendingCommitTask?.cancel()
                        pendingCommitTask = nil
                        pendingTarget = nil
                        syncVisualState(to: selection, width: width)
                        return
                    }

                    dragOffset = CGFloat(index) * width

                    if option == selection {
                        pendingCommitTask?.cancel()
                        pendingCommitTask = nil
                        pendingTarget = nil
                        onReselect?(option)
                        return
                    }

                    scheduleCommit(for: option)
                }
            )
    }

    private func selectionCapsule(fillColor: Color, width: CGFloat) -> some View {
        UIKitTabBarSelectionAnimator(
            offset: dragOffset,
            itemWidth: width,
            itemHeight: itemHeight,
            isInteracting: isActive,
            fillColor: fillColor
        )
    }

    private func resolvedItemWidth(availableWidth: CGFloat) -> CGFloat {
        guard !options.isEmpty else { return minItemWidth }
        return max(min(availableWidth / CGFloat(options.count), maxItemWidth), minItemWidth)
    }

    private func clampedOffset(_ offset: CGFloat, width: CGFloat) -> CGFloat {
        let maximumOffset = CGFloat(max(options.count - 1, 0)) * width
        return max(min(offset, maximumOffset), 0)
    }

    private func syncVisualState(to option: Option, width: CGFloat) {
        guard let index = options.firstIndex(of: option) else { return }
        dragOffset = CGFloat(index) * width
    }

    private func scheduleCommit(for option: Option) {
        pendingCommitTask?.cancel()
        pendingTarget = option
        emitSwitchHaptic()

        pendingCommitTask = Task { @MainActor in
            let delayNanoseconds = UInt64(UIConstants.Animation.tabBarCommitDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }

            pendingCommitTask = nil
            pendingTarget = nil
            onSelection(option)
        }
    }

    private func emitSwitchHaptic() {
        let feedback = UIImpactFeedbackGenerator(style: .soft)
        feedback.prepare()
        feedback.impactOccurred(intensity: 0.5)
    }
}

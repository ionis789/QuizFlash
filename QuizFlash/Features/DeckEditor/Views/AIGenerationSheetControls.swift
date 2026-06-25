//
//  AIGenerationSheetControls.swift
//  QuizFlash
//
//  Manual allocation and slider controls for the AI generation sheet.
//

import SwiftUI
import UIKit

struct ManualAllocationCard: View {
    let allocation: AISourceRangeAllocation
    let upperBound: Int
    let maximumEndIndex: Int
    let cardCountUpperBound: Int
    let canRemove: Bool
    let onEndChange: (Int) -> Void
    let onCardCountChange: (Int) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            if canRemove {
                HStack {
                    Spacer()
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: 30, height: 30)
                            .background(Color.red.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            SourceRangeTickPicker(
                startIndex: allocation.startIndex,
                endIndex: allocation.endIndex,
                upperBound: max(maximumEndIndex, allocation.startIndex),
                sourceUpperBound: max(upperBound, 1),
                onEndChange: onEndChange
            )

            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                TickCardCountPicker(
                    value: allocation.cardCount,
                    range: 1 ... max(cardCountUpperBound, 1),
                    onChange: onCardCountChange
                )
            }
        }
        .padding(UIConstants.Spacing.standard)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }
}

struct SourceRangeTickPicker: View {
    let startIndex: Int
    let endIndex: Int
    let upperBound: Int
    let sourceUpperBound: Int
    let onEndChange: (Int) -> Void

    private var safeStart: Int {
        min(max(startIndex, 1), max(sourceUpperBound, 1))
    }

    private var safeUpperBound: Int {
        max(min(upperBound, max(sourceUpperBound, 1)), safeStart)
    }

    private var safeEnd: Int {
        min(max(endIndex, safeStart), safeUpperBound)
    }

    private var selectionBinding: Binding<Int> {
        Binding {
            safeEnd - safeStart
        } set: { newSelection in
            let nextValue = safeStart + newSelection
            onEndChange(min(max(nextValue, safeStart), safeUpperBound))
        }
    }

    private var pickerConfig: TickPickerConfig {
        TickPickerConfig(
            tickWidth: 2,
            tickHeight: 28,
            tickHPadding: 8,
            inActiveHeightProgress: 0.46,
            interactionHeight: 72,
            tickAreaTopPadding: 10,
            activeTint: ThemeManager.shared.accentColor.color,
            inActiveTint: .primary,
            alignment: .center
        )
    }

    var body: some View {
        VStack(spacing: UIConstants.Spacing.tiny) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.standard) {
                Text("\(safeStart)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(width: 44, alignment: .leading)

                TickPicker(
                    count: safeUpperBound - safeStart,
                    config: pickerConfig,
                    selection: selectionBinding,
                    highlightedRange: 0 ... max(safeEnd - safeStart, 0)
                )

                Text("\(safeUpperBound)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(safeUpperBound < sourceUpperBound ? .tertiary : .secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, UIConstants.Spacing.tiny)
    }
}

struct TickCardCountPicker: View {
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    private var selectionBinding: Binding<Int> {
        Binding {
            max(min(value, range.upperBound), range.lowerBound) - range.lowerBound
        } set: { newSelection in
            let nextValue = range.lowerBound + newSelection
            onChange(max(min(nextValue, range.upperBound), range.lowerBound))
        }
    }

    private var pickerConfig: TickPickerConfig {
        TickPickerConfig(
            tickWidth: 2,
            tickHeight: 34,
            tickHPadding: 4,
            inActiveHeightProgress: 0.48,
            interactionHeight: 76,
            tickAreaTopPadding: 8,
            activeTint: ThemeManager.shared.accentColor.color,
            inActiveTint: .primary,
            alignment: .bottom
        )
    }

    var body: some View {
        VStack(spacing: UIConstants.Spacing.small) {
            Text("\(max(min(value, range.upperBound), range.lowerBound))")
                .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(height: 42)
                .statusTextMotion(trigger: value)

            Circle()
                .fill(Color.primary.opacity(0.20))
                .frame(width: 7, height: 7)

            TickPicker(
                count: range.upperBound - range.lowerBound,
                config: pickerConfig,
                selection: selectionBinding,
                highlightedRange: nil
            )
        }
        .padding(.horizontal, UIConstants.Spacing.tiny)
        .padding(.top, UIConstants.Spacing.small)
    }
}

/// Stable integer picker for AI card counts. It avoids slider snapping issues
/// when ranges are small and keeps manual allocation edits predictable.
struct CardCountControl: View {
    let value: Int
    let range: ClosedRange<Int>
    let presets: [Int]
    let onChange: (Int) -> Void

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    private var filteredPresets: [Int] {
        presets
            .filter { range.contains($0) }
            .reduce(into: [Int]()) { result, preset in
                if !result.contains(preset) {
                    result.append(preset)
                }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack(spacing: UIConstants.Spacing.small) {
                StepperButton(symbol: "minus", isEnabled: value > range.lowerBound) {
                    onChange(max(value - 1, range.lowerBound))
                }

                Text("\(value)")
                    .font(.system(size: 32, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .statusTextMotion(trigger: value)

                StepperButton(symbol: "plus", isEnabled: value < range.upperBound) {
                    onChange(min(value + 1, range.upperBound))
                }
            }
            .padding(.horizontal, UIConstants.Spacing.small)
            .padding(.vertical, UIConstants.Spacing.tiny)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }

            if !filteredPresets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: UIConstants.Spacing.tiny) {
                        ForEach(filteredPresets, id: \.self) { preset in
                            Button {
                                onChange(preset)
                            } label: {
                                Text("\(preset)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(value == preset ? .primary : .secondary)
                                    .frame(minWidth: 38)
                                    .padding(.vertical, 8)
                                    .background(
                                        value == preset ? accent.opacity(0.16) : Color.white.opacity(0.05),
                                        in: Capsule(style: .continuous)
                                    )
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .stroke(value == preset ? accent.opacity(0.42) : Color.white.opacity(0.06), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

struct TickPickerConfig {
    var tickWidth: CGFloat = 3
    var tickHeight: CGFloat = 30
    var tickHPadding: CGFloat = 3
    var inActiveHeightProgress: CGFloat = 0.55
    var interactionHeight: CGFloat = 60
    var tickAreaTopPadding: CGFloat = 0
    var activeTint: Color = .yellow
    var inActiveTint: Color = .primary
    var alignment: Alignment = .bottom

    enum Alignment {
        case top
        case bottom
        case center
    }
}

struct TickPicker: View {
    var count: Int
    var config: TickPickerConfig
    @Binding var selection: Int
    var highlightedRange: ClosedRange<Int>? = nil

    var body: some View {
        TickPickerScrollView(
            count: count,
            config: config,
            selection: $selection,
            highlightedRange: highlightedRange
        )
        .frame(height: config.interactionHeight)
    }
}

private struct TickPickerScrollView: UIViewRepresentable {
    var count: Int
    var config: TickPickerConfig
    @Binding var selection: Int
    var highlightedRange: ClosedRange<Int>?

    var tickStride: CGFloat {
        config.tickWidth + (config.tickHPadding * 2)
    }

    func makeUIView(context: Context) -> TickUIScrollView {
        let scrollView = TickUIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.addSubview(context.coordinator.contentView)
        scrollView.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
            guard let scrollView else { return }
            coordinator?.configure(scrollView)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: TickUIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.configure(scrollView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: TickPickerScrollView
        let contentView = UIView()

        private var tickViews: [UIView] = []
        private var scrollIndex = 0
        private var animationRange: ClosedRange<Int> = 0 ... 0
        private var didCompleteInitialLayout = false
        private var isWaitingForInitialScroll = false
        private var isApplyingProgrammaticScroll = false
        private var lastLayoutWidth: CGFloat = 0
        private var lastTickStride: CGFloat = 0
        private let feedbackGenerator = UISelectionFeedbackGenerator()

        init(parent: TickPickerScrollView) {
            self.parent = parent
        }

        func configure(_ scrollView: UIScrollView) {
            guard scrollView.bounds.width > 0 else { return }

            let safeSelection = clamped(parent.selection)
            synchronizeTickCount()
            let layoutChanged = applyLayout(in: scrollView)

            if !didCompleteInitialLayout {
                scrollIndex = safeSelection
                animationRange = safeSelection ... safeSelection
                updateTickAppearance(in: scrollView, animated: false)

                if !isWaitingForInitialScroll {
                    isWaitingForInitialScroll = true
                    isApplyingProgrammaticScroll = true

                    DispatchQueue.main.async { [weak self, weak scrollView] in
                        guard let self, let scrollView else { return }

                        _ = self.applyLayout(in: scrollView)
                        self.updateTickAppearance(in: scrollView, animated: false)
                        self.scrollToIndex(safeSelection, in: scrollView, animated: false)
                        self.didCompleteInitialLayout = true
                        self.isWaitingForInitialScroll = false
                    }
                }

                return
            }

            updateTickAppearance(in: scrollView, animated: false)

            if layoutChanged {
                scrollToIndex(scrollIndex, in: scrollView, animated: false)
            }

            let userIsScrolling = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
            if !userIsScrolling && safeSelection != scrollIndex {
                scrollIndex = safeSelection
                animationRange = safeSelection ... safeSelection
                updateTickAppearance(in: scrollView, animated: true)
                scrollToIndex(safeSelection, in: scrollView, animated: true)
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            animationRange = scrollIndex ... scrollIndex
            updateTickAppearance(in: scrollView, animated: false)
            feedbackGenerator.prepare()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard didCompleteInitialLayout, !isApplyingProgrammaticScroll else { return }
            let newIndex = nearestIndex(in: scrollView)
            guard newIndex != scrollIndex else { return }

            let previousIndex = scrollIndex
            scrollIndex = newIndex
            animationRange = min(previousIndex, newIndex) ... max(previousIndex, newIndex)
            updateTickAppearance(in: scrollView, animated: true)
            feedbackGenerator.selectionChanged()
            feedbackGenerator.prepare()

            if parent.selection != newIndex {
                parent.selection = newIndex
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                snapToNearestIndex(in: scrollView)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            snapToNearestIndex(in: scrollView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            let newIndex = nearestIndex(in: scrollView)
            scrollIndex = newIndex
            animationRange = newIndex ... newIndex
            updateTickAppearance(in: scrollView, animated: true)

            if parent.selection != newIndex {
                parent.selection = newIndex
            }
        }

        private func synchronizeTickCount() {
            let neededCount = max(parent.count + 1, 0)

            if tickViews.count < neededCount {
                for _ in tickViews.count ..< neededCount {
                    let tickView = UIView()
                    tickView.layer.masksToBounds = true
                    contentView.addSubview(tickView)
                    tickViews.append(tickView)
                }
            } else if tickViews.count > neededCount {
                tickViews[neededCount...].forEach { $0.removeFromSuperview() }
                tickViews.removeLast(tickViews.count - neededCount)
            }
        }

        private func applyLayout(in scrollView: UIScrollView) -> Bool {
            let tickStride = parent.tickStride
            let contentWidth = CGFloat(tickViews.count) * tickStride
            let horizontalInset = max((scrollView.bounds.width - tickStride) / 2, 0)
            let layoutChanged = abs(lastLayoutWidth - scrollView.bounds.width) > 0.5 || abs(lastTickStride - tickStride) > 0.5

            lastLayoutWidth = scrollView.bounds.width
            lastTickStride = tickStride

            scrollView.contentInset = UIEdgeInsets(
                top: 0,
                left: horizontalInset,
                bottom: 0,
                right: horizontalInset
            )
            scrollView.contentSize = CGSize(width: contentWidth, height: scrollView.bounds.height)
            contentView.frame = CGRect(
                x: 0,
                y: 0,
                width: contentWidth,
                height: scrollView.bounds.height
            )

            for (index, tickView) in tickViews.enumerated() {
                tickView.frame = frameForTick(at: index, in: scrollView, fullHeight: animationRange.contains(index))
            }

            return layoutChanged
        }

        private func updateTickAppearance(in scrollView: UIScrollView, animated: Bool) {
            let updates = {
                for (index, tickView) in self.tickViews.enumerated() {
                    let isInside = self.activeHighlightedRange(in: scrollView)?.contains(index) ?? self.animationRange.contains(index)
                    let color = index == self.scrollIndex
                        ? self.parent.config.activeTint
                        : self.parent.config.inActiveTint.opacity(isInside ? 1 : 0.4)

                    tickView.backgroundColor = UIColor(color)
                    tickView.layer.cornerRadius = self.parent.config.tickWidth / 2
                    tickView.frame = self.frameForTick(at: index, in: scrollView, fullHeight: isInside)
                }
            }

            if animated {
                UIView.animate(
                    withDuration: 0.3,
                    delay: 0,
                    usingSpringWithDamping: 1,
                    initialSpringVelocity: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState],
                    animations: updates
                )
            } else {
                UIView.performWithoutAnimation(updates)
            }
        }

        private func frameForTick(at index: Int, in scrollView: UIScrollView, fullHeight: Bool) -> CGRect {
            let height = parent.config.tickHeight * (fullHeight ? 1 : parent.config.inActiveHeightProgress)
            let tickAreaHeight = parent.config.tickHeight
            let tickAreaY = min(
                max(parent.config.tickAreaTopPadding, 0),
                max(scrollView.bounds.height - tickAreaHeight, 0)
            )
            let y: CGFloat

            switch parent.config.alignment {
            case .top:
                y = tickAreaY
            case .bottom:
                y = tickAreaY + tickAreaHeight - height
            case .center:
                y = tickAreaY + ((tickAreaHeight - height) / 2)
            }

            return CGRect(
                x: (CGFloat(index) * parent.tickStride) + parent.config.tickHPadding,
                y: y,
                width: parent.config.tickWidth,
                height: height
            )
        }

        private func snapToNearestIndex(in scrollView: UIScrollView) {
            let index = nearestIndex(in: scrollView)
            scrollIndex = index
            animationRange = index ... index
            updateTickAppearance(in: scrollView, animated: true)
            scrollToIndex(index, in: scrollView, animated: true)

            if parent.selection != index {
                parent.selection = index
            }
        }

        private func scrollToIndex(_ index: Int, in scrollView: UIScrollView, animated: Bool) {
            let safeIndex = clamped(index)
            let xOffset = (CGFloat(safeIndex) * parent.tickStride) - scrollView.contentInset.left

            isApplyingProgrammaticScroll = true
            scrollView.setContentOffset(CGPoint(x: xOffset, y: 0), animated: animated)

            if animated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.isApplyingProgrammaticScroll = false
                }
            } else {
                isApplyingProgrammaticScroll = false
            }
        }

        private func nearestIndex(in scrollView: UIScrollView) -> Int {
            let rawIndex = (scrollView.contentOffset.x + scrollView.contentInset.left) / parent.tickStride
            return clamped(Int(rawIndex.rounded()))
        }

        private func clamped(_ index: Int) -> Int {
            max(min(index, parent.count), 0)
        }

        private func activeHighlightedRange(in scrollView: UIScrollView) -> ClosedRange<Int>? {
            guard let highlightedRange = parent.highlightedRange else { return nil }
            let userIsInteracting = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
            guard userIsInteracting else { return nil }

            let lowerBound = clamped(highlightedRange.lowerBound)
            let upperBound = clamped(scrollIndex)
            return min(lowerBound, upperBound) ... max(lowerBound, upperBound)
        }
    }
}

private final class TickUIScrollView: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// A dual-handle discrete slider used to select image or page ranges.
struct DiscreteRangeSlider: View {
    let lowerValue: Int
    let upperValue: Int
    let range: ClosedRange<Int>
    let onLowerChange: (Int) -> Void
    let onUpperChange: (Int) -> Void

    @State private var activeHandle: RangeHandle?

    private let thumbSize = CGFloat(28)
    private let trackHeight = CGFloat(8)

    var body: some View {
        GeometryReader { proxy in
            let metrics = SliderMetrics(width: proxy.size.width, thumbSize: thumbSize)
            let lowerOffset = metrics.offset(for: lowerValue, in: range)
            let upperOffset = metrics.offset(for: upperValue, in: range)
            let lowerCenter = lowerOffset + (thumbSize / 2)
            let upperCenter = upperOffset + (thumbSize / 2)
            let selectedWidth = max(upperCenter - lowerCenter, trackHeight)
            let selectedOffset = upperCenter == lowerCenter
                ? max(lowerCenter - (trackHeight / 2), 0)
                : lowerCenter

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(ThemeManager.shared.accentColor.color)
                    .frame(
                        width: selectedWidth,
                        height: trackHeight
                    )
                    .offset(x: selectedOffset)

                SliderThumb(isActive: activeHandle == .lower)
                    .offset(x: lowerOffset)

                SliderThumb(isActive: activeHandle == .upper)
                    .offset(x: upperOffset)
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let handle = activeHandle
                            ?? preferredHandle(for: gesture.location.x, metrics: metrics)
                        activeHandle = handle

                        let snappedValue = metrics.snappedValue(
                            for: gesture.location.x,
                            in: range
                        )

                        switch handle {
                        case .lower:
                            onLowerChange(min(snappedValue, upperValue))
                        case .upper:
                            onUpperChange(max(snappedValue, lowerValue))
                        }
                    }
                    .onEnded { _ in
                        activeHandle = nil
                    }
            )
        }
        .frame(height: thumbSize)
    }

    private func preferredHandle(
        for locationX: CGFloat,
        metrics: SliderMetrics
    ) -> RangeHandle {
        let lowerCenter = metrics.offset(for: lowerValue, in: range) + (thumbSize / 2)
        let upperCenter = metrics.offset(for: upperValue, in: range) + (thumbSize / 2)

        if abs(lowerCenter - upperCenter) < 0.5 {
            return locationX >= lowerCenter ? .upper : .lower
        }

        return abs(locationX - lowerCenter) <= abs(locationX - upperCenter) ? .lower : .upper
    }
}

private enum RangeHandle {
    case lower
    case upper
}

/// Layout helper for discrete slider snapping and thumb positioning.
private struct SliderMetrics {
    let width: CGFloat
    let thumbSize: CGFloat

    private var usableWidth: CGFloat {
        max(width - thumbSize, 1)
    }

    func offset(for value: Int, in range: ClosedRange<Int>) -> CGFloat {
        let clampedValue = min(max(value, range.lowerBound), range.upperBound)
        guard range.lowerBound != range.upperBound else { return 0 }

        let progress = CGFloat(clampedValue - range.lowerBound)
            / CGFloat(range.upperBound - range.lowerBound)
        return progress * usableWidth
    }

    func snappedValue(for locationX: CGFloat, in range: ClosedRange<Int>) -> Int {
        guard range.lowerBound != range.upperBound else { return range.lowerBound }

        let clampedX = min(max(locationX - (thumbSize / 2), 0), usableWidth)
        let progress = clampedX / usableWidth
        let rawValue = CGFloat(range.lowerBound)
            + progress * CGFloat(range.upperBound - range.lowerBound)
        return Int(rawValue.rounded())
    }
}

private struct SliderThumb: View {
    var isActive = false

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 28, height: 28)
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isActive ? 0.24 : 0.18), radius: isActive ? 8 : 5, y: 3)
            .scaleEffect(isActive ? 1.06 : 1)
            .animation(.easeInOut(duration: UIConstants.Animation.instant), value: isActive)
    }
}

private struct StepperButton: View {
    let symbol: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
    }
}

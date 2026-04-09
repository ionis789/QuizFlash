//
//  AIGenerationSheetControls.swift
//  QuizFlash
//
//  Manual allocation and slider controls for the AI generation sheet.
//

import SwiftUI

struct ManualAllocationCard: View {
    let title: String
    let allocation: AISourceRangeAllocation
    let upperBound: Int
    let sourceSingular: String
    let sourcePlural: String
    let cardCountUpperBound: Int
    let canRemove: Bool
    let onStartChange: (Int) -> Void
    let onEndChange: (Int) -> Void
    let onCardCountChange: (Int) -> Void
    let onRemove: () -> Void

    private var coveredItemCount: Int {
        max(allocation.endIndex - allocation.startIndex + 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                Spacer()

                if canRemove {
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

            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Source Range")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(allocation.startIndex)-\(allocation.endIndex)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .statusTextMotion(trigger: "\(allocation.startIndex)-\(allocation.endIndex)")
                }

                Text("Covers \(coveredItemCount) \(coveredItemCount == 1 ? sourceSingular : sourcePlural)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                DiscreteRangeSlider(
                    lowerValue: allocation.startIndex,
                    upperValue: allocation.endIndex,
                    range: 1...max(upperBound, 1),
                    onLowerChange: onStartChange,
                    onUpperChange: onEndChange
                )

                HStack {
                    Text("1")
                    Spacer()
                    Text("\(max(upperBound, 1))")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Cards")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(allocation.cardCount)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .statusTextMotion(trigger: allocation.cardCount)
                }

                DiscreteValueSlider(
                    value: allocation.cardCount,
                    range: 1...max(cardCountUpperBound, 1),
                    onChange: onCardCountChange
                )

                HStack {
                    Text("1")
                    Spacer()
                    Text("\(max(cardCountUpperBound, 1))")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
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

/// A minimalist discrete slider for integer-backed generation controls.
struct DiscreteValueSlider: View {
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    private let thumbSize = CGFloat(28)
    private let trackHeight = CGFloat(8)

    var body: some View {
        GeometryReader { proxy in
            let metrics = SliderMetrics(width: proxy.size.width, thumbSize: thumbSize)
            let thumbOffset = metrics.offset(for: value, in: range)
            let filledWidth = thumbOffset + (thumbSize / 2)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(ThemeManager.shared.accentColor.color)
                    .frame(width: filledWidth, height: trackHeight)

                SliderThumb()
                    .offset(x: thumbOffset)
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let snappedValue = metrics.snappedValue(
                            for: gesture.location.x,
                            in: range
                        )
                        if snappedValue != value {
                            onChange(snappedValue)
                        }
                    }
            )
        }
        .frame(height: thumbSize)
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

private struct SheetValueStepper: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: UIConstants.Spacing.standard) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)

            Spacer(minLength: UIConstants.Spacing.small)

            HStack(spacing: UIConstants.Spacing.small) {
                StepperButton(symbol: "minus") {
                    onChange(max(value - 1, range.lowerBound))
                }
                .disabled(value <= range.lowerBound)

                Text("\(value)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(minWidth: 34)
                    .statusTextMotion(trigger: value)

                StepperButton(symbol: "plus") {
                    onChange(min(value + 1, range.upperBound))
                }
                .disabled(value >= range.upperBound)
            }
        }
        .padding(.horizontal, UIConstants.Spacing.standard)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

private struct StepperButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

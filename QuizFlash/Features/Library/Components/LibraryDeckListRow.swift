//
//  LibraryDeckListRow.swift
//  QuizFlash
//
//  Deck row presentation and local interaction for Library lists.
//

import SwiftUI
import UIKit
import CoreText
import SwiftData

struct LibraryDeckListRow: View, Equatable {
    let deck: LibraryDeckRowSnapshot
    let isFirstInSection: Bool
    let isSelecting: Bool
    let isSelected: Bool
    let onNavigate: () -> Void
    let onToggleSelection: () -> Void
    let onImport: () -> Void
    let onMoveToFolder: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var titleAvailableWidth: CGFloat = 0
    static func == (lhs: LibraryDeckListRow, rhs: LibraryDeckListRow) -> Bool {
        lhs.deck == rhs.deck &&
        lhs.isFirstInSection == rhs.isFirstInSection &&
        lhs.isSelecting == rhs.isSelecting &&
        lhs.isSelected == rhs.isSelected
    }

    private var deckTint: Color {
        Color(hex: deck.colorHex) ?? ThemeManager.shared.accentColor.color
    }

    private var selectionAccent: Color {
        ThemeManager.shared.accentColor.color
    }

    private var resolvedTraitCollection: UITraitCollection {
        UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
    }

    private var titleColor: Color {
        let fallback = UIColor.white
        let resolved = (UIColor(named: "DeckTitle") ?? fallback).resolvedColor(with: resolvedTraitCollection)
        return Color(uiColor: resolved)
    }

    private var secondaryMetaColor: Color {
        Color(uiColor: UIColor.secondaryLabel.resolvedColor(with: resolvedTraitCollection))
    }

    private var separatorSeed: UInt64 {
        UInt64(bitPattern: Int64(deck.id.hashValue))
    }

    private var topContentPadding: CGFloat {
        isFirstInSection
            ? LibrarySectionHeaderMetrics.firstDeckTopPadding
            : LibrarySectionHeaderMetrics.regularDeckTopPadding
    }

    var body: some View {
        rowContent
            .contentShape(Rectangle())
            .onTapGesture {
                handlePrimaryTap()
            }
            .customContextMenu(
                id: deck.id,
                isEnabled: !isSelecting,
                actions: contextMenuActions
            ) {
                rowContent
            }
            .accessibilityAddTraits(.isButton)
    }

    private var contextMenuActions: [CustomContextMenuAction] {
        guard !isSelecting else { return [] }
        return [
            CustomContextMenuAction(
                title: "Import",
                systemImage: "square.and.arrow.down",
                role: .normal,
                action: onImport
            ),
            CustomContextMenuAction(
                title: "Move to Folder",
                systemImage: "folder",
                role: .normal,
                action: onMoveToFolder
            ),
            CustomContextMenuAction(
                title: "Delete",
                systemImage: "trash",
                role: .destructive,
                action: onDelete
            )
        ]
    }

    private var rowContent: some View {
        rowMainLine
            .padding(.leading, 4)
            .padding(.trailing, 4)
            .padding(.top, topContentPadding)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                LibraryRowSeparator(
                    baseTint: deckTint,
                    highlightTint: selectionAccent,
                    seed: separatorSeed,
                    isHighlighted: isSelected,
                    isBreathing: isSelecting && !isSelected
                )
                .padding(.top, 10)
            }
    }

    private var rowMainLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            LibraryDeckTitleLabel(
                title: deck.title,
                availableWidth: titleAvailableWidth,
                titleColor: titleColor
            )
                .layoutPriority(1)

            Text("\(deck.cardCount) card\(deck.cardCount == 1 ? "" : "s")")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(secondaryMetaColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newWidth in
                    if abs(titleAvailableWidth - newWidth) > 0.5 {
                        titleAvailableWidth = newWidth
                    }
                }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func handlePrimaryTap() {
        if isSelecting {
            withAnimation(.circularSelectionSpring) {
                onToggleSelection()
            }
        } else {
            onNavigate()
        }
    }
}

struct LibraryDeckMetaLabel: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct LibraryDeckTitleLabel: View {
    let title: String
    let availableWidth: CGFloat
    let titleColor: Color

    var body: some View {
        Text(verbatim: renderedTitle)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundColor(titleColor)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var renderedTitle: String {
        guard availableWidth > 0 else { return title }
        let normalizedTitle = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalizedTitle.isEmpty else { return title }

        let words = normalizedTitle.split(separator: " ").map(String.init)
        guard words.count > 1 else { return normalizedTitle }

        let greedyLineWidth = availableWidth + 4
        var firstLineWords: [String] = []

        for word in words {
            let candidateWords = firstLineWords + [word]
            let candidateLine = candidateWords.joined(separator: " ")
            if Self.lineWidth(for: candidateLine) <= greedyLineWidth {
                firstLineWords = candidateWords
            } else {
                break
            }
        }

        guard !firstLineWords.isEmpty, firstLineWords.count < words.count else {
            return normalizedTitle
        }

        let firstLine = firstLineWords.joined(separator: " ")
        let secondLine = words.dropFirst(firstLineWords.count).joined(separator: " ")

        guard Self.lineWidth(for: secondLine) <= greedyLineWidth else {
            return normalizedTitle
        }

        return "\(firstLine)\n\(secondLine)"
    }

    private static let titleFont: UIFont = {
        let fallback = UIFont.systemFont(ofSize: 22, weight: .bold)
        guard let descriptor = fallback.fontDescriptor.withDesign(.rounded) else {
            return fallback
        }
        return UIFont(descriptor: descriptor, size: 22)
    }()

    private static func lineWidth(for text: String) -> CGFloat {
        let attributedText = NSAttributedString(
            string: text,
            attributes: [.font: titleFont]
        )
        let line = CTLineCreateWithAttributedString(attributedText)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}

struct LibraryRowSeparator: View {
    let baseTint: Color
    let highlightTint: Color
    var seed: UInt64? = nil
    var isHighlighted: Bool = false
    var isBreathing: Bool = false

    @State private var waveAmplitude: CGFloat = 0
    @State private var tintBlendProgress: CGFloat = 0
    @State private var lineWidth: CGFloat = 1.55
    @State private var lineOpacity: CGFloat = 0.16
    @State private var glowOpacity: CGFloat = 0.10
    @State private var glowRadius: CGFloat = 0.7
    @State private var waveProfile = OrganicWaveProfile.randomized(seed: UInt64.random(in: 1 ... .max))
    @State private var appliedSeed: UInt64?
    @State private var waveEntryProgress: CGFloat = 1
    @State private var liveWaveTime: Double = 0

    private var lineToggleSpring: Animation {
        .circularProgressSpring.speed(1.52)
    }

    private let waveEntryDuration: Double = 0.44

    private var waveDriverID: String {
        "\(appliedSeed ?? 0)-\(isBreathing)-\(isHighlighted)"
    }

    var body: some View {
        separatorShape()
        .frame(height: waveProfile.baseHeight)
        .clipShape(Rectangle())
        .opacity(0.92)
        .onAppear {
            refreshWaveProfileIfNeeded(force: true)
            syncSeparatorState(isInitialMount: true)
        }
        .onChange(of: seed) { _, _ in
            refreshWaveProfileIfNeeded()
            syncSeparatorState(isInitialMount: true)
        }
        .onChange(of: isBreathing) { _, _ in
            syncSeparatorState()
        }
        .onChange(of: isHighlighted) { _, _ in
            syncSeparatorState()
        }
        .task(id: waveDriverID) {
            await driveWaveClock()
        }
    }

    @ViewBuilder
    private func separatorShape() -> some View {
        OrganicWaveSeparatorShape(
            profile: waveProfile,
            elapsed: liveWaveTime,
            overallAmplitude: currentWaveAmplitude
        )
        .stroke(currentTint.opacity(lineOpacity), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        .shadow(color: currentTint.opacity(glowOpacity), radius: glowRadius, x: 0, y: 0)
    }

    private func syncSeparatorState(isInitialMount: Bool = false) {
        refreshWaveProfileIfNeeded()
        let target = targetVisualState
        let wasHighlighted = lineOpacity > 0.6

        if isInitialMount {
            applyVisualState(target, animation: nil)
            return
        }

        if wasHighlighted && !isHighlighted && !isBreathing {
            applyVisualState(target, animation: .easeInOut(duration: 0.18))
            return
        }

        if isBreathing && !isHighlighted {
            let isStartingWave = waveAmplitude <= 0.01
            applyVisualState(target, animation: nil) {
                if isStartingWave {
                    waveEntryProgress = 0
                } else {
                    waveEntryProgress = 1
                }
            }

            withAnimation(.linear(duration: waveEntryDuration)) {
                waveEntryProgress = 1
            }
            return
        }

        applyVisualState(target, animation: lineToggleSpring)
    }

    private var targetVisualState: SeparatorVisualState {
        if isHighlighted {
            return .highlighted
        }
        if isBreathing {
            return .breathing
        }
        return .passive
    }

    private var currentWaveAmplitude: CGFloat {
        guard isBreathing && !isHighlighted else { return 0 }
        return waveAmplitude * waveEntryProgress
    }

    private var currentTint: Color {
        let base = UIColor(baseTint)
        let highlight = UIColor(highlightTint)
        var baseRed: CGFloat = 0
        var baseGreen: CGFloat = 0
        var baseBlue: CGFloat = 0
        var baseAlpha: CGFloat = 0
        var highlightRed: CGFloat = 0
        var highlightGreen: CGFloat = 0
        var highlightBlue: CGFloat = 0
        var highlightAlpha: CGFloat = 0

        guard base.getRed(&baseRed, green: &baseGreen, blue: &baseBlue, alpha: &baseAlpha),
              highlight.getRed(&highlightRed, green: &highlightGreen, blue: &highlightBlue, alpha: &highlightAlpha) else {
            return isHighlighted ? highlightTint : baseTint
        }

        let progress = tintBlendProgress
        return Color(
            red: baseRed + ((highlightRed - baseRed) * progress),
            green: baseGreen + ((highlightGreen - baseGreen) * progress),
            blue: baseBlue + ((highlightBlue - baseBlue) * progress),
            opacity: baseAlpha + ((highlightAlpha - baseAlpha) * progress)
        )
    }

    private func refreshWaveProfileIfNeeded(force: Bool = false) {
        let resolvedSeed = seed ?? appliedSeed ?? UInt64.random(in: 1 ... .max)
        guard force || appliedSeed != resolvedSeed else { return }
        appliedSeed = resolvedSeed
        applyWithoutAnimation {
            waveProfile = OrganicWaveProfile.randomized(seed: resolvedSeed)
        }
    }

    private func driveWaveClock() async {
        await MainActor.run {
            liveWaveTime = 0
        }
        let startTime = CACurrentMediaTime()
        while !Task.isCancelled {
            let shouldContinue = await MainActor.run {
                isBreathing || waveAmplitude > 0.01
            }
            guard shouldContinue else { break }

            let elapsed = CACurrentMediaTime() - startTime
            await MainActor.run {
                liveWaveTime = elapsed
            }

            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    private func applyVisualState(
        _ state: SeparatorVisualState,
        animation: Animation?,
        extraChanges: (() -> Void)? = nil
    ) {
        if let animation {
            withAnimation(animation) {
                assignVisualState(state)
                extraChanges?()
            }
        } else {
            applyWithoutAnimation {
                assignVisualState(state)
                extraChanges?()
            }
        }
    }

    private func assignVisualState(_ state: SeparatorVisualState) {
        waveAmplitude = state.amplitude
        tintBlendProgress = state.tintBlendProgress
        lineWidth = state.lineWidth
        lineOpacity = state.opacity
        glowOpacity = state.glowOpacity
        glowRadius = state.glowRadius
        if !isBreathing || isHighlighted {
            waveEntryProgress = 1
        }
    }

    private func applyWithoutAnimation(_ changes: () -> Void) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            changes()
        }
    }

    private enum SeparatorVisualState {
        case passive
        case breathing
        case highlighted

        var amplitude: CGFloat {
            switch self {
            case .passive, .highlighted:
                0
            case .breathing:
                2.05
            }
        }

        var lineWidth: CGFloat {
            switch self {
            case .passive, .breathing, .highlighted:
                1.55
            }
        }

        var tintBlendProgress: CGFloat {
            switch self {
            case .passive, .breathing:
                0
            case .highlighted:
                1
            }
        }

        var opacity: CGFloat {
            switch self {
            case .passive:
                0.16
            case .breathing:
                0.16
            case .highlighted:
                0.72
            }
        }

        var glowOpacity: CGFloat {
            switch self {
            case .passive:
                0.04
            case .breathing:
                0.10
            case .highlighted:
                0.12
            }
        }

        var glowRadius: CGFloat {
            switch self {
            case .passive:
                0.45
            case .breathing:
                0.85
            case .highlighted:
                0.9
            }
        }
    }
}

private struct OrganicWaveSeparatorShape: Shape {
    let profile: OrganicWaveProfile
    let elapsed: Double
    let overallAmplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0 else { return path }

        let midY = rect.midY
        let sampleCount = profile.sampleCount
        path.move(to: CGPoint(x: rect.minX, y: midY))

        for sampleIndex in 1 ... sampleCount {
            let progress = Double(sampleIndex) / Double(sampleCount)
            let x = rect.minX + (rect.width * CGFloat(progress))
            let y = midY + profile.verticalOffset(
                at: progress,
                elapsed: elapsed,
                width: rect.width,
                overallAmplitude: overallAmplitude
            )
            path.addLine(to: CGPoint(x: x, y: y))
        }

        return path
    }
}

private struct OrganicWaveProfile {
    let seed: UInt64
    let baseHeight: CGFloat
    let sampleCount: Int
    let cycleCount: Double
    let travelAngularVelocity: Double
    let travelPhase: Double
    let secondaryPhase: Double
    let tertiaryPhase: Double
    let secondaryFrequencyMultiplier: Double
    let tertiaryFrequencyMultiplier: Double
    let lobeCount: Int
    let lobeBases: [Double]
    let lobeDepths: [Double]
    let lobePhases: [Double]
    let envelopeAngularVelocity: Double
    let globalEnvelopePhase: Double
    let globalEnvelopeDepth: Double

    static func randomized(seed: UInt64) -> OrganicWaveProfile {
        var generator = WaveIntervalRandomizer(seed: seed)
        let lobeCount = Int(generator.nextDouble(in: 6 ... 8).rounded())
        return OrganicWaveProfile(
            seed: seed,
            baseHeight: generator.nextCGFloat(in: 9.8 ... 11.0),
            sampleCount: 72,
            cycleCount: generator.nextDouble(in: 5.3 ... 6.4),
            travelAngularVelocity: generator.nextDouble(in: 3.1 ... 3.6),
            travelPhase: generator.nextDouble(in: 0 ... (.pi * 2)),
            secondaryPhase: generator.nextDouble(in: 0 ... (.pi * 2)),
            tertiaryPhase: generator.nextDouble(in: 0 ... (.pi * 2)),
            secondaryFrequencyMultiplier: generator.nextDouble(in: 1.9 ... 2.2),
            tertiaryFrequencyMultiplier: generator.nextDouble(in: 2.8 ... 3.2),
            lobeCount: lobeCount,
            lobeBases: (0 ..< lobeCount).map { _ in generator.nextDouble(in: 0.84 ... 1.08) },
            lobeDepths: (0 ..< lobeCount).map { _ in generator.nextDouble(in: 0.07 ... 0.14) },
            lobePhases: (0 ..< lobeCount).map { _ in generator.nextDouble(in: 0 ... (.pi * 2)) },
            envelopeAngularVelocity: generator.nextDouble(in: 0.54 ... 0.72),
            globalEnvelopePhase: generator.nextDouble(in: 0 ... (.pi * 2)),
            globalEnvelopeDepth: generator.nextDouble(in: 0.04 ... 0.09)
        )
    }

    func verticalOffset(
        at progress: Double,
        elapsed: Double,
        width: CGFloat,
        overallAmplitude: CGFloat
    ) -> CGFloat {
        guard overallAmplitude > 0.001 else { return 0 }

        let spatialPhase = progress * cycleCount * (.pi * 2)
        let travelPhase = (elapsed * travelAngularVelocity) + self.travelPhase
        let primary = sin(spatialPhase + travelPhase)
        let secondary = 0.22 * sin((spatialPhase * secondaryFrequencyMultiplier) + (travelPhase * 1.04) + secondaryPhase)
        let tertiary = 0.11 * sin((spatialPhase * tertiaryFrequencyMultiplier) + (travelPhase * 0.92) + tertiaryPhase)
        let localEnvelope = envelope(at: progress, elapsed: elapsed)
        let edgeFade = edgeFadeFactor(for: progress)
        return CGFloat((primary + secondary + tertiary) * localEnvelope * edgeFade) * overallAmplitude
    }

    private func envelope(at progress: Double, elapsed: Double) -> Double {
        let scaled = max(0, min(progress, 1)) * Double(max(lobeCount - 1, 1))
        let lowerIndex = min(max(Int(floor(scaled)), 0), lobeCount - 1)
        let upperIndex = min(lowerIndex + 1, lobeCount - 1)
        let mix = smoothstep(scaled - floor(scaled))
        let lowerValue = lobeValue(at: lowerIndex, elapsed: elapsed)
        let upperValue = lobeValue(at: upperIndex, elapsed: elapsed)
        let local = lowerValue + ((upperValue - lowerValue) * mix)
        let global = 1 + (sin((elapsed * envelopeAngularVelocity) + globalEnvelopePhase) * globalEnvelopeDepth)
        return max(0.72, local * global)
    }

    private func lobeValue(at index: Int, elapsed: Double) -> Double {
        lobeBases[index] + (sin((elapsed * envelopeAngularVelocity) + lobePhases[index]) * lobeDepths[index])
    }

    private func edgeFadeFactor(for progress: Double) -> Double {
        let leading = min(1, progress / 0.08)
        let trailing = min(1, (1 - progress) / 0.08)
        return smoothstep(min(leading, trailing))
    }

    private func smoothstep(_ value: Double) -> Double {
        let clamped = max(0, min(value, 1))
        return clamped * clamped * (3 - (2 * clamped))
    }
}

private struct WaveIntervalRandomizer {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func nextUnit() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value = value ^ (value >> 31)
        return Double(value) / Double(UInt64.max)
    }

    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + ((range.upperBound - range.lowerBound) * nextUnit())
    }

    mutating func nextCGFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat(nextDouble(in: Double(range.lowerBound) ... Double(range.upperBound)))
    }
}

private extension CGFloat {
    var roundedString: String {
        String(format: "%.1f", Double(self))
    }

    var preciseRoundedString: String {
        String(format: "%.2f", Double(self))
    }
}

//
//  CardAppearanceSettingView.swift
//  QuizFlash
//
//  Fullscreen card appearance configurator.
//  Presents a live mock card that responds in real time to the selected
//  content overflow mode, so the user can see the difference before committing.
//
//  Storage: @AppStorage(CardContentMode.storageKey) — UserDefaults, zero
//  SwiftData overhead. FlipCard reads the same key independently.

import SwiftUI

private let kCardAppearanceChromeSpace = "CardAppearanceChromeSpace"

// MARK: - Card Content Mode

/// Controls how FlipCard handles content that overflows the card bounds.
enum CardContentMode: String, CaseIterable {

    /// Content is scaled down proportionally to always fit inside the card.
    /// No interaction required — everything is visible at once.
    case scaleToFit = "scaleToFit"

    /// Content scrolls vertically inside the card.
    /// Preserves original font sizes at the cost of requiring a scroll gesture.
    case scrollable = "scrollable"

    static let storageKey = "card.contentMode"

    var label: String {
        switch self {
        case .scaleToFit: return "Scale to Fit"
        case .scrollable: return "Scrollable"
        }
    }

    var description: String {
        switch self {
        case .scaleToFit:
            return "Content shrinks to always fit on screen. Best for quick review."
        case .scrollable:
            return "Content keeps its size and scrolls. Best for detailed notes."
        }
    }

    var icon: String {
        switch self {
        case .scaleToFit: return "arrow.up.left.and.arrow.down.right"
        case .scrollable: return "scroll.fill"
        }
    }
}

// MARK: - Card Appearance Setting View

struct SettingsCardAppearanceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ThemeManager.self) private var themeManager
    @State private var isCollapsedTitleVisible = false
    @State private var navigationBarHeight: CGFloat =
        UIConstants.Size.capsuleHeight + UIConstants.Layout.deckNavigationTopPadding
    @State private var navigationBarBottomY: CGFloat = 0

    @AppStorage(CardContentMode.storageKey)
    private var rawMode: String = CardContentMode.scaleToFit.rawValue

    private var selectedMode: CardContentMode {
        CardContentMode(rawValue: rawMode) ?? .scaleToFit
    }

    // Controls which face of the mock card is shown
    @State private var isMockFlipped = false

    var body: some View {
        ZStack(alignment: .top) {
            background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    LargeScreenTitle(title: "Card Appearance")
                        .collapsibleTitleRevealAnchor(
                            in: kCardAppearanceChromeSpace,
                            navigationBarBottomY: navigationBarBottomY,
                            revealClearance: SettingsChromeMetrics.pillRevealClearance,
                            isVisible: $isCollapsedTitleVisible
                        )

                    previewSection
                    pickerSection
                    descriptionSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: navigationBarHeight + UIConstants.Spacing.small)
            }

            navigationBar
        }
        .coordinateSpace(name: kCardAppearanceChromeSpace)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        CollapsibleTitleNavigationBar(
            coordinateSpaceName: kCardAppearanceChromeSpace,
            onHeightChange: { navigationBarHeight = $0 },
            onBottomChange: { navigationBarBottomY = $0 }
        ) {
            ChromeCircleIconButton(systemName: "chevron.left") {
                dismiss()
            }
        } center: { maxWidth in
            CollapsibleTitlePill(
                title: "Card Appearance",
                maxWidth: maxWidth,
                isVisible: isCollapsedTitleVisible
            )
        } trailing: {
            ChromeCirclePlaceholder()
        }
    }

    // MARK: - Live Preview Section

    private var previewSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Preview")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                // Tap to flip hint
                Label(isMockFlipped ? "Showing Answer" : "Showing Question",
                      systemImage: isMockFlipped ? "lightbulb.fill" : "questionmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .onTapGesture {
                        withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 0.85)) {
                            isMockFlipped.toggle()
                        }
                    }
            }

            MockCardView(
                isFlipped: $isMockFlipped,
                mode: selectedMode
            )
            .frame(height: 340)
            .shadow(
                color: colorScheme == .dark
                    ? Color.black.opacity(0.45)
                    : Color.black.opacity(0.12),
                radius: 24, y: 10
            )

            Text("Tap the label above to flip the card")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Mode Picker Section

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Overflow Behaviour")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(CardContentMode.allCases, id: \.rawValue) { mode in
                    ModeOptionRow(
                        mode: mode,
                        isSelected: selectedMode == mode
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            rawMode = mode.rawValue
                        }
                    }
                }
            }
        }
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
                .font(.body)
                .padding(.top, 1)

            Text(selectedMode.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .animation(.spring(response: 0.3), value: selectedMode.rawValue)
    }

    // MARK: - Background

    private var background: some View {
        themeManager.groupedScreenBackground
    }
}

// MARK: - Mode Option Row

private struct ModeOptionRow: View {
    let mode: CardContentMode
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected
                              ? Color.accentColor.opacity(0.15)
                              : Color(uiColor: .tertiarySystemFill))
                        .frame(width: 44, height: 44)

                    Image(systemName: mode.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                }

                Spacer()

                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color(uiColor: .separator),
                                lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(
                        color: isSelected
                            ? Color.accentColor.opacity(0.12)
                            : Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04),
                        radius: isSelected ? 8 : 4, y: 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear,
                            lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
}

// MARK: - Mock Card View
//
// Self-contained preview card that demonstrates both content modes.
// Uses hardcoded text that intentionally overflows so the behavioural
// difference between Scale and Scroll is immediately obvious.
// Mirrors FlipCard's visual structure without requiring real model data.

private struct MockCardView: View {
    @Binding var isFlipped: Bool
    let mode: CardContentMode

    @Environment(\.colorScheme) private var colorScheme

    private let cornerRadius: CGFloat = 24

    var body: some View {
        ZStack {
            // Back face (answer)
            mockFace(
                content: mockAnswerContent,
                label: "ANSWER",
                labelColor: .green
            )
            .rotation3DEffect(
                .degrees(isFlipped ? 0 : 180),
                axis: (x: 0, y: 1, z: 0)
            )
            .opacity(isFlipped ? 1 : 0)

            // Front face (question)
            mockFace(
                content: mockQuestionContent,
                label: "QUESTION",
                labelColor: .blue
            )
            .rotation3DEffect(
                .degrees(isFlipped ? -180 : 0),
                axis: (x: 0, y: 1, z: 0)
            )
            .opacity(isFlipped ? 0 : 1)
        }
    }

    // MARK: Face Builder

    @ViewBuilder
    private func mockFace(
        content: some View,
        label: String,
        labelColor: Color
    ) -> some View {
        ZStack {
            // Card background
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(cardBackground)

            // Inner glow border
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.55), lineWidth: 6)
                .blur(radius: 5)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.30), lineWidth: 1)
                .blur(radius: 1)

            // Content area — switches between scale and scroll mode
            GeometryReader { geo in
                Group {
                    if mode == .scrollable {
                        // Scroll mode: natural size, vertical scroll
                        ScrollView(.vertical, showsIndicators: false) {
                            content
                                .padding(20)
                        }
                    } else {
                        // Scale mode: shrinks to fit — mirrors FlipCard behaviour
                        scaledContent(content: content, in: geo.size)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            // Face label badge
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(label)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(labelColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(labelColor.opacity(0.12), in: Capsule())
                        .padding(12)
                }
            }
        }
    }

    // Mirrors FlipCard's GeometryReader + scaleEffect logic exactly
    @ViewBuilder
    private func scaledContent<C: View>(content: C, in size: CGSize) -> some View {
        let vPad: CGFloat  = 20
        let hPad: CGFloat  = 20
        let available      = size.height - vPad * 2

        content
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .background(
                GeometryReader { inner in
                    Color.clear.preference(
                        key: _MockHeightKey.self,
                        value: inner.size.height
                    )
                }
            )
            .modifier(_ScaleToFitModifier(availableHeight: available))
            .frame(width: size.width, alignment: .top)
    }

    // MARK: Mock Content

    /// Intentionally long so overflow behaviour is clearly visible.
    @ViewBuilder
    private var mockQuestionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cellular Respiration")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            Text("Explain the three main stages of cellular respiration and describe what happens during each stage, including the reactants consumed and the products generated.")
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.4)

            Text("Include the net ATP yield for each stage and where in the cell each stage occurs.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var mockAnswerContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            answerItem(
                number: "1",
                title: "Glycolysis",
                body: "Occurs in the cytoplasm. Glucose (6C) → 2 pyruvate. Net: 2 ATP + 2 NADH."
            )
            answerItem(
                number: "2",
                title: "Krebs Cycle",
                body: "Occurs in the mitochondrial matrix. 2 pyruvate → 6 CO₂. Yields: 2 ATP + 8 NADH + 2 FADH₂."
            )
            answerItem(
                number: "3",
                title: "Electron Transport Chain",
                body: "Inner mitochondrial membrane. NADH + FADH₂ → H₂O. Yields: ~32–34 ATP via chemiosmosis."
            )
        }
    }

    @ViewBuilder
    private func answerItem(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Helpers

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
            : AnyShapeStyle(Color.white)
    }
}

// MARK: - Scale-to-fit modifier (mirrors FlipCard logic)

private struct _MockHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct _ScaleToFitModifier: ViewModifier {
    let availableHeight: CGFloat
    @State private var measuredHeight: CGFloat = 0

    func body(content: Content) -> some View {
        let scale: CGFloat = measuredHeight > 0 && measuredHeight > availableHeight
            ? max(availableHeight / measuredHeight, 0.5)
            : 1.0

        content
            .onPreferenceChange(_MockHeightKey.self) { h in
                if h > 0 { measuredHeight = h }
            }
            .scaleEffect(scale, anchor: .top)
    }
}

#Preview {
    SettingsCardAppearanceView()
}

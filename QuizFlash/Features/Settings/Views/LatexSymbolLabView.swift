//
//  LatexSymbolLabView.swift
//  QuizFlash
//
//  Visual regression lab for high-risk LaTeX symbols and expressions.
//

import SwiftUI

private let kLatexSymbolLabChromeSpace = "LatexSymbolLabChromeSpace"

struct LatexSymbolLabView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager

    @State private var isCollapsedTitleVisible = false
    @State private var navigationBarHeight: CGFloat =
        UIConstants.Size.capsuleHeight + UIConstants.Layout.deckNavigationTopPadding
    @State private var navigationBarBottomY: CGFloat = 0
    @State private var customSample = #"$x_1 \neq x_2$"#

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                    LargeScreenTitle(title: "LaTeX Symbol Lab")
                        .collapsibleTitleRevealAnchor(
                            in: kLatexSymbolLabChromeSpace,
                            navigationBarBottomY: navigationBarBottomY,
                            revealClearance: SettingsChromeMetrics.pillRevealClearance,
                            isVisible: $isCollapsedTitleVisible
                        )

                    SettingsInfoCard(
                        icon: "function",
                        tint: .green,
                        text: "Use this internal screen to verify risky symbols, operators, and compact expressions. If anything renders incorrectly, copy the exact LaTeX command or sample label and we can fix it quickly."
                    )

                    SettingsSectionCard(
                        title: "Custom Sample",
                        subtitle: "Paste any LaTeX expression or rich text sample here and inspect the live renderer."
                    ) {
                        TextEditor(text: $customSample)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120)
                            .padding(UIConstants.Spacing.standard)
                            .background(
                                RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                                    .fill(Color.black.opacity(0.18))
                            )

                        SettingsCardDivider()

                        LatexSymbolRenderCard(
                            title: "Live Preview",
                            command: nil,
                            sample: customSample
                        )
                    }

                    ForEach(LatexSymbolCategory.allCases) { category in
                        SettingsSectionCard(
                            title: category.title,
                            subtitle: category.subtitle
                        ) {
                            ForEach(Array(category.samples.enumerated()), id: \.element.id) { index, sample in
                                LatexSymbolRenderCard(
                                    title: sample.title,
                                    command: sample.command,
                                    sample: sample.preview
                                )

                                if index < category.samples.count - 1 {
                                    SettingsCardDivider()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, UIConstants.Spacing.large)
                .padding(.top, UIConstants.Spacing.large)
                .padding(.bottom, UIConstants.Spacing.huge)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: navigationBarHeight + UIConstants.Spacing.small)
            }

            navigationBar
        }
        .coordinateSpace(name: kLatexSymbolLabChromeSpace)
        .background(themeManager.groupedScreenBackground)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
    }

    private var navigationBar: some View {
        CollapsibleTitleNavigationBar(
            coordinateSpaceName: kLatexSymbolLabChromeSpace,
            onHeightChange: { navigationBarHeight = $0 },
            onBottomChange: { navigationBarBottomY = $0 }
        ) {
            ChromeCircleIconButton(systemName: "chevron.left") {
                dismiss()
            }
        } center: { maxWidth in
            CollapsibleTitlePill(
                title: "LaTeX Symbol Lab",
                maxWidth: maxWidth,
                isVisible: isCollapsedTitleVisible
            )
        } trailing: {
            ChromeCircleIconButton(systemName: "arrow.counterclockwise") {
                customSample = #"$x_1 \neq x_2$"#
            }
        }
    }
}

private struct LatexSymbolRenderCard: View {
    let title: String
    let command: String?
    let sample: String

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                if let command {
                    Text(command)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Text(sample)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            MixedMathTextView(
                text: sample,
                fontSize: 24,
                textColor: .primary,
                alignment: .leading,
                isInteractive: false,
                allowsReadOnlyOverflowScrolling: true
            )
            .padding(UIConstants.Spacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                    .fill(Color.black.opacity(0.18))
            )
        }
    }
}

private struct LatexSymbolSample: Identifiable {
    let id = UUID()
    let title: String
    let command: String
    let preview: String
}

private enum LatexSymbolCategory: String, CaseIterable, Identifiable {
    case relations
    case membership
    case greek
    case arrows
    case operators

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relations: return "Relations"
        case .membership: return "Membership & Sets"
        case .greek: return "Greek Variants"
        case .arrows: return "Arrows & Logic"
        case .operators: return "Operators & Structures"
        }
    }

    var subtitle: String {
        switch self {
        case .relations:
            return "High-risk equality and comparison symbols."
        case .membership:
            return "Set inclusion, membership, and intersection/union."
        case .greek:
            return "Symbols that often drift into the wrong visual variant."
        case .arrows:
            return "Mappings, implications, and equivalence."
        case .operators:
            return "Common structured expressions that exercise more than one symbol."
        }
    }

    var samples: [LatexSymbolSample] {
        switch self {
        case .relations:
            return [
                LatexSymbolSample(title: "Not Equal", command: #"\\neq / \\ne"#, preview: #"$x_1 \neq x_2$"#),
                LatexSymbolSample(title: "Less / Greater or Equal", command: #"\\leq / \\geq"#, preview: #"$a \leq b \leq c$ și $x \geq 0$"#),
                LatexSymbolSample(title: "Approx / Similar", command: #"\\approx / \\sim / \\simeq"#, preview: #"$f(x) \approx g(x)$, $A \sim B$, $u \simeq v$"#)
            ]
        case .membership:
            return [
                LatexSymbolSample(title: "Membership", command: #"\\in / \\notin"#, preview: #"$x \in A$ și $y \notin B$"#),
                LatexSymbolSample(title: "Subset", command: #"\\subset / \\subseteq"#, preview: #"$A \subset B$ și $C \subseteq D$"#),
                LatexSymbolSample(title: "Union / Intersection", command: #"\\cup / \\cap"#, preview: #"$A \cup B$ și $A \cap B$"#)
            ]
        case .greek:
            return [
                LatexSymbolSample(title: "Epsilon Pair", command: #"\\epsilon / \\varepsilon"#, preview: #"$\epsilon \neq \varepsilon$"#),
                LatexSymbolSample(title: "Phi Pair", command: #"\\phi / \\varphi"#, preview: #"$\phi \neq \varphi$"#),
                LatexSymbolSample(title: "Theta / Lambda / Tau", command: #"\\theta / \\lambda / \\tau"#, preview: #"$\theta, \lambda, \tau$"#)
            ]
        case .arrows:
            return [
                LatexSymbolSample(title: "Functions", command: #"\\to / \\mapsto"#, preview: #"$f: X \to Y,\; x \mapsto f(x)$"#),
                LatexSymbolSample(title: "Implication", command: #"\\Rightarrow / \\implies"#, preview: #"$P \Rightarrow Q$ și $P \implies Q$"#),
                LatexSymbolSample(title: "Equivalence", command: #"\\leftrightarrow / \\Leftrightarrow / \\iff"#, preview: #"$P \leftrightarrow Q$, $P \Leftrightarrow Q$, $P \iff Q$"#)
            ]
        case .operators:
            return [
                LatexSymbolSample(title: "Quantifiers", command: #"\\forall / \\exists"#, preview: #"$\forall x \in X,\; \exists y \in Y$"#),
                LatexSymbolSample(title: "Product and Dot", command: #"\\times / \\cdot"#, preview: #"$u \cdot v$ și $A \times B$"#),
                LatexSymbolSample(title: "Structured Formula", command: #"\\mathbb / \\frac / \\sum / \\int"#, preview: #"$f: \mathbb{R}^n \to \mathbb{R},\; \frac{1}{n}\sum_{i=1}^{n} x_i,\; \int_a^b f(x)\,dx$"#)
            ]
        }
    }
}

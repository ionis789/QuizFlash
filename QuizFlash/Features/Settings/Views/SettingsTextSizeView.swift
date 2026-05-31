//
//  SettingsTextSizeView.swift
//  QuizFlash
//
//  App and card-content text size controls with live preview.
//

import SwiftUI

private let kSettingsTextSizeChromeSpace = "SettingsTextSizeChromeSpace"

// MARK: - Settings Text Size View

struct SettingsTextSizeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    @State private var isCollapsedTitleVisible = false
    @State private var navigationBarHeight: CGFloat =
        UIConstants.Size.capsuleHeight + UIConstants.Layout.deckNavigationTopPadding
    @State private var navigationBarBottomY: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                themeManager.groupedScreenBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                        LargeScreenTitle(title: "Text Size")
                            .collapsibleTitleRevealAnchor(
                                in: kSettingsTextSizeChromeSpace,
                                navigationBarBottomY: navigationBarBottomY,
                                revealClearance: SettingsChromeMetrics.pillRevealClearance,
                                isVisible: $isCollapsedTitleVisible
                            )

                        textSizePreview

                        SettingsSectionCard(
                            title: "App Interface",
                            subtitle: "Controls QuizFlash chrome, settings rows, navigation labels, and other app-owned UI where Dynamic Type is supported."
                        ) {
                            SettingsToggleRow(
                                icon: "iphone",
                                tint: .green,
                                title: "Use System Text Size",
                                detail: "Follow the text size selected in iOS Settings.",
                                isOn: usesSystemTextSizeBinding
                            )

                            SettingsCardDivider()

                            TextSizeScaleSliderPanel(
                                icon: "textformat.size",
                                tint: .blue,
                                title: "App Text",
                                detail: "Choose a comfortable base size for QuizFlash interface text.",
                                value: appInterfaceTextScaleBinding,
                                range: 0.85...1.30,
                                step: 0.05,
                                isEnabled: !appPreferences.usesSystemTextSize
                            )
                        }

                        SettingsSectionCard(
                            title: "Card Content",
                            subtitle: "Scales authored card text in the flashcard editor, preview, Flashcards, and Quiz without changing saved card data."
                        ) {
                            TextSizeScaleSliderPanel(
                                icon: "rectangle.on.rectangle",
                                tint: themeManager.accentColor.color,
                                title: "Card Text",
                                detail: "Adjust only study content, keeping app chrome and controls stable.",
                                value: cardContentTextScaleBinding,
                                range: 0.75...1.40,
                                step: 0.05,
                                isEnabled: true
                            )
                        }

                        SettingsInfoCard(
                            icon: "slider.horizontal.3",
                            tint: .teal,
                            text: "Deck-specific play mode settings still apply on top where they exist, while this slider acts as the global content scale."
                        )
                    }
                    .padding(.horizontal, UIConstants.Spacing.large)
                    .padding(.top, UIConstants.Spacing.large)
                    .padding(.bottom, UIConstants.Spacing.huge)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: navigationBarHeight + UIConstants.Spacing.small)
                }
            }
            .screenTopEdgeShadow(
                topHeight: structuralTopEdgeShadowHeight,
                topRevealProgress: isCollapsedTitleVisible ? 1 : 0,
                debugScreenID: "settings.text-size",
                style: .progressiveBlur()
            )

            navigationBar
        }
        .coordinateSpace(name: kSettingsTextSizeChromeSpace)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
    }

    private var structuralTopEdgeShadowHeight: CGFloat {
        if navigationBarBottomY > 0 {
            return navigationBarBottomY
        }
        return UIConstants.Layout.topEdgeShadowHeight
    }

    private var textSizePreview: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Preview")
                        .font(.system(size: 13 * appPreviewScale, weight: .bold, design: .rounded))
                        .foregroundStyle(themeManager.textSecondary)

                    Text(verbatim: "QuizFlash")
                        .font(.system(size: 28 * appPreviewScale, weight: .black, design: .rounded))
                        .foregroundStyle(themeManager.textPrimary)
                }

                Spacer(minLength: UIConstants.Spacing.medium)

                Text(percentText(appPreferences.cardContentTextScale))
                    .font(.system(size: 13 * appPreviewScale, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.textPrimary)
                    .padding(.horizontal, UIConstants.Spacing.standard)
                    .padding(.vertical, UIConstants.Spacing.small)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                Text("QUESTION")
                    .font(.system(size: 11 * appPreviewScale, weight: .black, design: .rounded))
                    .foregroundStyle(themeManager.textSecondary)

                Text("How does changing text size affect a study card?")
                    .font(.system(size: 22 * cardPreviewScale, weight: .semibold, design: .rounded))
                    .foregroundStyle(themeManager.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("The interface stays readable while authored card content can be tuned separately for review comfort.")
                    .font(.system(size: 16 * cardPreviewScale, weight: .medium, design: .rounded))
                    .foregroundStyle(themeManager.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(UIConstants.Spacing.large)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
            .overlay {
                RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
            }
        }
        .padding(UIConstants.Spacing.large)
        .settingsCardBackground(cornerRadius: UIConstants.Radius.maximum)
    }

    private var appPreviewScale: CGFloat {
        appPreferences.usesSystemTextSize
            ? 1
            : CGFloat(appPreferences.appInterfaceTextScale)
    }

    private var cardPreviewScale: CGFloat {
        CGFloat(appPreferences.cardContentTextScale)
    }

    private var usesSystemTextSizeBinding: Binding<Bool> {
        Binding(
            get: { appPreferences.usesSystemTextSize },
            set: { appPreferences.usesSystemTextSize = $0 }
        )
    }

    private var appInterfaceTextScaleBinding: Binding<Double> {
        Binding(
            get: { appPreferences.appInterfaceTextScale },
            set: { appPreferences.appInterfaceTextScale = $0 }
        )
    }

    private var cardContentTextScaleBinding: Binding<Double> {
        Binding(
            get: { appPreferences.cardContentTextScale },
            set: { appPreferences.cardContentTextScale = $0 }
        )
    }

    private var navigationBar: some View {
        CollapsibleTitleNavigationBar(
            coordinateSpaceName: kSettingsTextSizeChromeSpace,
            onHeightChange: { navigationBarHeight = $0 },
            onBottomChange: { navigationBarBottomY = $0 }
        ) {
            ChromeCircleIconButton(systemName: "chevron.left") {
                dismiss()
            }
        } center: { maxWidth in
            CollapsibleTitlePill(
                title: "Text Size",
                maxWidth: maxWidth,
                isVisible: isCollapsedTitleVisible
            )
        } trailing: {
            ChromeCirclePlaceholder()
        }
    }
}

// MARK: - Text Size Slider Panel

private struct TextSizeScaleSliderPanel: View {
    @Environment(ThemeManager.self) private var themeManager

    let icon: String
    let tint: Color
    let title: SettingsTextContent
    let detail: SettingsTextContent
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let isEnabled: Bool

    init(
        icon: String,
        tint: Color,
        title: SettingsTextContent,
        detail: SettingsTextContent,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        isEnabled: Bool
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.detail = detail
        _value = value
        self.range = range
        self.step = step
        self.isEnabled = isEnabled
    }

    init(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        isEnabled: Bool
    ) {
        self.init(
            icon: icon,
            tint: tint,
            title: .localizedLiteral(title),
            detail: .localizedLiteral(detail),
            value: value,
            range: range,
            step: step,
            isEnabled: isEnabled
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                ZStack {
                    RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                        .fill(tint.opacity(isEnabled ? 0.14 : 0.07))
                        .frame(width: 40, height: 40)

                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.45))
                }

                VStack(alignment: .leading, spacing: 4) {
                    settingsText(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(themeManager.textPrimary.opacity(isEnabled ? 1 : 0.55))

                    settingsText(detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(themeManager.textSecondary.opacity(isEnabled ? 1 : 0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: UIConstants.Spacing.standard)

                Text(percentText(value))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(themeManager.textPrimary.opacity(isEnabled ? 1 : 0.55))
                    .contentTransition(.numericText())
                    .padding(.horizontal, UIConstants.Spacing.standard)
                    .padding(.vertical, UIConstants.Spacing.small)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            HStack(spacing: UIConstants.Spacing.standard) {
                Text("A")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.textSecondary)

                Slider(value: $value, in: range, step: step)
                    .tint(tint)
                    .disabled(!isEnabled)

                Text("A")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.textSecondary)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .padding(.leading, 54)
        }
    }

    @ViewBuilder
    private func settingsText(_ content: SettingsTextContent) -> some View {
        switch content {
        case .localized(let resource):
            Text(resource)
        case .verbatim(let value):
            Text(verbatim: value)
        }
    }
}

private func percentText(_ scale: Double) -> String {
    "\(Int((scale * 100).rounded()))%"
}

//
//  PlayModeSettingsScreen.swift
//  QuizFlash
//
//  Shared mode-settings screen used by the deck play-mode carousel.
//

import SwiftUI

// MARK: - Play Mode Settings Screen

/// A reusable placeholder settings screen that keeps upcoming mode controls aligned
/// with QuizFlash's glass chrome, deck palette, and navigation language.
struct PlayModeSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The deck selected on the parent `DeckView`.
    let deck: DeckModel

    /// The mode currently being configured.
    let mode: DeckPlayModeDestination

    /// Lightweight compatibility counts for the active deck.
    let availability: PlayModeCardAvailability

    /// Safe-area values passed by the custom full-screen sheet container.
    let safeAreaInsets: UIEdgeInsets

    @State private var headerHeight: CGFloat = 0

    private var accentColor: Color { ThemeManager.shared.accentColor.color }

    private var deckColor: Color {
        Color(hex: deck.colorHex) ?? accentColor
    }

    private var tintColor: Color {
        mode.tintColor(deckColor: deckColor, accentColor: accentColor)
    }

    private var compatibleCardCount: Int {
        mode.compatibleCardCount(in: availability)
    }

    private var hasCompatibleCards: Bool {
        mode.hasCompatibleCards(in: availability)
    }

    private var horizontalInset: CGFloat {
        horizontalSizeClass == .compact
            ? UIConstants.Layout.compactScreenEdgeInset
        : UIConstants.Layout.screenEdgeInset
    }

    var body: some View {
        GeometryReader { geo in
            let resolvedSafeTopInset = max(safeAreaInsets.top, geo.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)

            ZStack(alignment: .top) {
                if fullScreenSheetDismiss == nil {
                    PlayModeSettingsBackground(deck: deck, mode: mode)
                        .ignoresSafeArea()
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                        overviewCard
                        settingsCard
                        readinessCard
                    }
                        .padding(.horizontal, horizontalInset)
                        .padding(.top, headerHeight + UIConstants.Spacing.large)
                        .padding(.bottom, resolvedSafeBottomInset + UIConstants.Spacing.huge)
                }

                header(safeTopInset: resolvedSafeTopInset)
            }
                .fullScreenSheetDragActivationHeight(headerHeight)
        }
            .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Navigation Bar

    private func header(safeTopInset: CGFloat) -> some View {
        VStack(spacing: UIConstants.Spacing.small) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 56, height: 5)
                .accessibilityHidden(true)

            ZStack {
                VStack(spacing: 2) {
                    Text("\(mode.title) Settings")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(deck.title.uppercased())
                        .font(
                            .system(
                            size: UIConstants.Size.navigationChromeLabel,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {


                    Spacer(minLength: 0)

                    dismissButton
                        .frame(width: UIConstants.Size.actionButton, alignment: .trailing)
                }
            }
                .frame(height: UIConstants.Size.capsuleHeight)
        }
            .padding(.top, safeTopInset + UIConstants.Spacing.tiny)
            .padding(.horizontal, horizontalInset)
            .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            if abs(headerHeight - newHeight) > 0.5 {
                headerHeight = newHeight
            }
        }
    }



    private var dismissButton: some View {
        Button(action: dismissSheet) {
            Image(systemName: "xmark")
                .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
                .foregroundStyle(.primary)
                .frame(
                width: UIConstants.Size.actionButton,
                height: UIConstants.Size.actionButton
            )
                .glassButton(shape: .circle)
        }
            .buttonStyle(.plain)
    }

    // MARK: - Cards

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: UIConstants.Radius.large,
                        style: .continuous
                    )
                        .fill(tintColor.opacity(0.12))
                        .frame(
                        width: UIConstants.Size.actionButton + UIConstants.Spacing.extraLarge,
                        height: UIConstants.Size.actionButton + UIConstants.Spacing.extraLarge
                    )

                    Image(systemName: mode.systemImage)
                        .font(.system(size: UIConstants.Size.iconLarge, weight: .black))
                        .foregroundStyle(tintColor)
                }

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    Text(mode.isGameplayImplemented ? "CONFIGURE & LAUNCH" : "SETTINGS PLACEHOLDER")
                        .font(
                            .system(
                            size: UIConstants.Size.navigationChromeLabel,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                        .foregroundStyle(.secondary)

                    Text(mode.settingsHeadline)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(mode.settingsSupportingCopy)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: UIConstants.Spacing.small) {
                settingsStatusChip(
                    title: mode.isGameplayImplemented ? "Gameplay Ready" : "Gameplay Soon",
                    icon: mode.isGameplayImplemented ? "play.fill" : "hourglass"
                )

                Spacer(minLength: 0)

                settingsStatusChip(
                    title: hasCompatibleCards
                        ? "\(compatibleCardCount) Compatible"
                        : "No Compatible Cards",
                    icon: hasCompatibleCards ? "checkmark.seal" : "exclamationmark.circle"
                )
            }
        }
            .padding(UIConstants.Spacing.large)
            .widgetStyle(cornerRadius: UIConstants.Radius.maximum)
            .overlay {
            RoundedRectangle(
                cornerRadius: UIConstants.Radius.maximum,
                style: .continuous
            )
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
        }
            .shadow(
            color: tintColor.opacity(0.12),
            radius: UIConstants.Shadow.heavyRadius,
            y: UIConstants.Shadow.yOffset
        )
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            Text("Planned Options")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            ForEach(mode.settingPresets) { setting in
                PlayModeSettingRow(
                    icon: setting.icon,
                    iconColor: tintColor,
                    title: setting.title,
                    detail: setting.detail
                )
            }
        }
            .padding(UIConstants.Spacing.large)
            .widgetStyle(cornerRadius: UIConstants.Radius.large)
            .overlay {
            RoundedRectangle(
                cornerRadius: UIConstants.Radius.large,
                style: .continuous
            )
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
        }
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            Text("Next Step")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(
                readinessCopy
            )
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
            .padding(UIConstants.Spacing.large)
            .widgetStyle(cornerRadius: UIConstants.Radius.large)
            .overlay {
            RoundedRectangle(
                cornerRadius: UIConstants.Radius.large,
                style: .continuous
            )
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
        }
    }

    private func settingsStatusChip(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, UIConstants.Spacing.standard)
            .padding(.vertical, UIConstants.Spacing.small)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private func dismissSheet() {
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            dismiss()
        }
    }

    private var readinessCopy: String {
        if mode.isGameplayImplemented {
            if hasCompatibleCards {
                return "This deck has \(compatibleCardCount) compatible \(mode.compatibilityRequirementLabel), so the gameplay flow can launch without coercing other card kinds."
            }

            return "This gameplay flow exists, but this deck does not contain any compatible \(mode.compatibilityRequirementLabel) yet."
        }

        if hasCompatibleCards {
            return "This deck already has \(compatibleCardCount) compatible \(mode.compatibilityRequirementLabel), and the mode contract is ready for future gameplay work."
        }

        return "This surface is ready for future configuration controls, and the deck will need compatible \(mode.compatibilityRequirementLabel) before launch."
    }
}

// MARK: - Settings Background

/// Decorative background shared by play-mode settings surfaces.
struct PlayModeSettingsBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let deck: DeckModel
    let mode: DeckPlayModeDestination

    private var accentColor: Color { ThemeManager.shared.accentColor.color }
    private var deckColor: Color { Color(hex: deck.colorHex) ?? accentColor }
    private var tintColor: Color {
        mode.tintColor(deckColor: deckColor, accentColor: accentColor)
    }

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color.black
            } else {
                Color(uiColor: .systemGroupedBackground)
            }

            LinearGradient(
                colors: [
                    deckColor.opacity(colorScheme == .dark ? 0.18 : 0.14),
                    tintColor.opacity(colorScheme == .dark ? 0.10 : 0.07),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(deckColor.opacity(0.18))
                .frame(
                    width: UIConstants.Spacing.huge * 8,
                    height: UIConstants.Spacing.huge * 8
                )
                .blur(radius: UIConstants.Spacing.huge * 2.5)
                .offset(
                    x: UIConstants.Spacing.huge * 2,
                    y: -UIConstants.Spacing.huge * 2
                )

            Circle()
                .fill(accentColor.opacity(0.12))
                .frame(
                    width: UIConstants.Spacing.huge * 7,
                    height: UIConstants.Spacing.huge * 7
                )
                .blur(radius: UIConstants.Spacing.huge * 2)
                .offset(
                    x: -UIConstants.Spacing.huge * 2,
                    y: UIConstants.Spacing.huge * 4
                )
        }
    }
}

// MARK: - Play Mode Setting Row

/// Lightweight placeholder row used inside `PlayModeSettingsScreen`.
private struct PlayModeSettingRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: UIConstants.Radius.medium,
                    style: .continuous
                )
                    .fill(iconColor.opacity(0.12))

                Image(systemName: icon)
                    .font(.system(size: UIConstants.Size.iconStandard, weight: .bold))
                    .foregroundStyle(iconColor)
            }
                .frame(
                width: UIConstants.Size.actionButton,
                height: UIConstants.Size.actionButton
            )

            VStack(alignment: .leading, spacing: UIConstants.Spacing.tiny) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Text("Soon")
                .font(.caption.weight(.bold))
                .foregroundStyle(iconColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(iconColor.opacity(0.12), in: Capsule())
        }
    }
}

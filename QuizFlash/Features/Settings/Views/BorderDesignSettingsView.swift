//
//  BorderDesignSettingsView.swift
//  QuizFlash
//
//  Global border tuning screen for shared app surfaces.
//

import SwiftUI

// MARK: - Border Design Settings View

struct BorderDesignSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                headerCard
                controlsCard
                appliedSurfacesCard
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.large)
            .padding(.bottom, UIConstants.Spacing.huge)
        }
        .background(themeManager.groupedScreenBackground.ignoresSafeArea())
        .navigationTitle(localized("Border Design"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            settingsNavigationBar
        }
        .swipeBack { dismiss() }
    }

    private var headerCard: some View {
        SettingsHeaderCard(
            icon: "rectangle.dashed",
            title: SettingsTextContent.verbatim(localized("Border Design")),
            subtitle: SettingsTextContent.verbatim(localized("Border system for Home, cards, settings, and controls.")),
            tint: borderPreviewAccentColor,
            badges: [
                SettingsTextContent.verbatim(appPreferences.borderDesign.preset.localizedTitle(locale: appPreferences.resolvedLocale)),
                SettingsTextContent.verbatim("\(Int((appPreferences.borderDesign.thickness * 100).rounded()))%")
            ]
        )
    }

    private var controlsCard: some View {
        SettingsSectionCard(
            title: SettingsTextContent.verbatim(localized("Border Controls")),
            subtitle: SettingsTextContent.verbatim(localized("Change these values once. Every preview below updates live."))
        ) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
                SettingsMenuPickerRow(
                    icon: "slider.horizontal.3",
                    tint: borderPreviewAccentColor,
                    title: SettingsTextContent.verbatim(localized("Border Type")),
                    selection: borderPresetBinding,
                    options: AppBorderStylePreset.allCases,
                    titleForOption: { option, locale in
                        option.localizedTitle(locale: locale)
                    }
                )

                borderDesignSlider(
                    title: localized("Thickness"),
                    detail: localized("Controls how thick every border is."),
                    value: borderThicknessBinding
                )

                borderDesignSlider(
                    title: localized("Depth"),
                    detail: localized("Controls how visible the border color is."),
                    value: borderDepthBinding
                )

                borderDesignSlider(
                    title: localized("Color"),
                    detail: localized("Changes the border color family."),
                    value: borderHueBinding
                )
            }
        }
    }

    private var appliedSurfacesCard: some View {
        SettingsSectionCard(
            title: SettingsTextContent.verbatim(localized("Where it changes")),
            subtitle: nil
        ) {
            VStack(spacing: UIConstants.Spacing.medium) {
                borderRolePreviewRow(
                    title: localized("Home dashboard"),
                    detail: localized("Activity card, recent decks, folders."),
                    primaryRole: .homeCard,
                    secondaryRole: nil
                )

                SettingsCardDivider()

                borderRolePreviewRow(
                    title: localized("Flashcards"),
                    detail: localized("Study cards and widget cards."),
                    primaryRole: .card,
                    secondaryRole: .widgetPrimary
                )

                SettingsCardDivider()

                borderRolePreviewRow(
                    title: localized("Panels"),
                    detail: localized("Settings rows, sheets, grouped surfaces."),
                    primaryRole: .panel,
                    secondaryRole: .control
                )

                SettingsCardDivider()

                borderRolePreviewRow(
                    title: localized("Small controls"),
                    detail: localized("Pills, chips, compact controls."),
                    primaryRole: .pill,
                    secondaryRole: .control
                )
            }
        }
    }

    private var settingsNavigationBar: some View {
        HStack {
            ChromeCircleIconButton(systemName: "chevron.compact.left") {
                dismiss()
            }

            Spacer()
        }
        .padding(.horizontal, UIConstants.Spacing.large)
        .padding(.top, UIConstants.Layout.deckNavigationTopPadding)
        .padding(.bottom, UIConstants.Spacing.small)
    }

    private var borderPreviewAccentColor: Color {
        Color(
            hue: appPreferences.borderDesign.hue,
            saturation: colorScheme == .dark ? 0.52 : 0.46,
            brightness: colorScheme == .dark ? 0.78 : 0.52
        )
    }

    private func borderRolePreviewRow(
        title: String,
        detail: String,
        primaryRole: AppBorderSurfaceRole,
        secondaryRole: AppBorderSurfaceRole?
    ) -> some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
            HStack(spacing: 8) {
                borderPreviewSwatch(role: primaryRole, width: 58, height: 42)

                if let secondaryRole {
                    borderPreviewSwatch(role: secondaryRole, width: 42, height: 42)
                }
            }
            .frame(width: 112, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.bold))
                    .foregroundStyle(themeManager.textPrimary)

                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(themeManager.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, UIConstants.Spacing.small)
    }

    private func borderPreviewSwatch(
        role: AppBorderSurfaceRole,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let radius = role == .pill ? height / 2 : UIConstants.Radius.medium
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        return shape
            .fill(themeManager.roleColor(.widgetSurfaceFill).opacity(0.72))
            .frame(width: width, height: height)
            .overlay {
                shape
                    .strokeBorder(
                        AppBorderRenderer.color(
                            for: role,
                            preferences: appPreferences.borderDesign,
                            colorScheme: colorScheme
                        ),
                        lineWidth: AppBorderRenderer.lineWidth(
                            for: role,
                            preferences: appPreferences.borderDesign
                        )
                    )
            }
    }

    private func borderDesignSlider(
        title: String,
        detail: String,
        value: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: UIConstants.Spacing.small) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.bold))
                        .foregroundStyle(themeManager.textPrimary)

                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(themeManager.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: UIConstants.Spacing.standard)

                Text("\(Int((value.wrappedValue * 100).rounded()))")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(themeManager.textPrimary)
                    .padding(.horizontal, UIConstants.Spacing.medium)
                    .frame(height: 30)
                    .background(borderPreviewAccentColor.opacity(0.10), in: Capsule())
            }

            Slider(
                value: value,
                in: AppBorderDesignPreferences.valueRange,
                step: 0.01
            )
            .tint(borderPreviewAccentColor)
        }
    }

    private var borderPresetBinding: Binding<AppBorderStylePreset> {
        Binding(
            get: { appPreferences.borderDesign.preset },
            set: { newValue in
                appPreferences.borderDesign = appPreferences.borderDesign.updating { design in
                    design.preset = newValue
                }
            }
        )
    }

    private var borderThicknessBinding: Binding<Double> {
        borderDesignBinding(\.thickness)
    }

    private var borderDepthBinding: Binding<Double> {
        borderDesignBinding(\.depth)
    }

    private var borderHueBinding: Binding<Double> {
        borderDesignBinding(\.hue)
    }

    private func borderDesignBinding(
        _ keyPath: WritableKeyPath<AppBorderDesignPreferences, Double>
    ) -> Binding<Double> {
        Binding(
            get: { appPreferences.borderDesign[keyPath: keyPath] },
            set: { newValue in
                appPreferences.borderDesign = appPreferences.borderDesign.updating { design in
                    design[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, locale: appPreferences.resolvedLocale)
    }
}

#Preview {
    NavigationStack {
        BorderDesignSettingsView()
            .environment(ThemeManager.shared)
            .environment(AppPreferences.shared)
    }
}

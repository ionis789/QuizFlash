//
//  DevelopmentThemeStudioView.swift
//  QuizFlash
//
//  Live theme-token editor for developer-only palette tuning.
//

import SwiftUI

struct DevelopmentThemeStudioView: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                previewSection
                roleSection
                paletteSection
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.large)
            .padding(.bottom, UIConstants.Size.bottomChromeBarHeight + 120)
        }
        .background(themeManager.screenBackground.ignoresSafeArea())
        .navigationTitle("Theme Studio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if themeManager.hasThemeOverrides {
                    Button("Reset All") {
                        themeManager.resetAllThemeOverrides()
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(themeManager.dangerPrimary)
                }
            }
        }
    }

    private var previewSection: some View {
        SettingsSectionCard(
            title: "Live Preview",
            subtitle: "Adjust tokens below. Shared chrome updates immediately."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Button("Primary") {}
                        .quizFlashButtonStyle(.primary)

                    Button("Danger") {}
                        .quizFlashButtonStyle(.accentAlt)
                }

                HStack(spacing: 12) {
                    Text("Surface")
                        .font(.caption.weight(.bold))
                        .quizFlashLabelChrome(.surface, size: 36, horizontalPadding: 14)

                    Text("Light")
                        .font(.caption.weight(.bold))
                        .quizFlashLabelChrome(.secondary, size: 36, horizontalPadding: 14)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Widget Preview")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(themeManager.textSecondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Shared widget surface")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(themeManager.textPrimary)

                        Text("Use this preview to tune background, text, and accent balance before touching screen-level UI.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(themeManager.textSecondary)

                        HStack(spacing: 10) {
                            miniStat(title: "Brand", tint: themeManager.brandPrimary)
                            miniStat(title: "Rose", tint: themeManager.highlightRose)
                            miniStat(title: "Danger", tint: themeManager.dangerPrimary)
                        }
                    }
                    .padding(UIConstants.Spacing.large)
                    .flashcardStyle(cornerRadius: 28, shadowRadius: 0, surfaceRole: .widget)
                }
            }
        }
    }

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
            ForEach(ThemeColorTokenGroup.allCases) { group in
                SettingsSectionCard(
                    title: group.rawValue,
                    subtitle: nil
                ) {
                    VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                        ForEach(Array(groupTokens(for: group).enumerated()), id: \.element.id) { index, token in
                            DevelopmentThemeTokenRow(token: token)

                            if index < groupTokens(for: group).count - 1 {
                                SettingsCardDivider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
            ForEach(ThemeColorRoleGroup.allCases) { group in
                SettingsSectionCard(
                    title: "\(group.rawValue) Roles",
                    subtitle: nil
                ) {
                    VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                        let roles = groupRoles(for: group)

                        ForEach(Array(roles.enumerated()), id: \.element.id) { index, role in
                            DevelopmentThemeRoleRow(role: role)

                            if index < roles.count - 1 {
                                SettingsCardDivider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func groupTokens(for group: ThemeColorTokenGroup) -> [ThemeColorToken] {
        ThemeColorToken.allCases.filter { $0.group == group }
    }

    private func groupRoles(for group: ThemeColorRoleGroup) -> [ThemeColorRole] {
        ThemeColorRole.allCases.filter { $0.group == group }
    }

    private func miniStat(title: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(themeManager.surfaceElevated, in: Capsule(style: .continuous))
    }
}

private struct DevelopmentThemeRoleRow: View {
    @Environment(ThemeManager.self) private var themeManager

    let role: ThemeColorRole

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                Circle()
                    .fill(themeManager.roleColor(role))
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(role.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(themeManager.textPrimary)

                    Text(role.usage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(themeManager.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if themeManager.hasRoleOverride(for: role) {
                    Button("Reset") {
                        themeManager.clearRoleOverride(for: role)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(themeManager.dangerPrimary)
                }
            }

            Menu {
                ForEach(ThemeColorToken.allCases) { token in
                    Button {
                        themeManager.setRoleOverride(token, for: role)
                    } label: {
                        HStack {
                            Text(token.title)
                            if themeManager.resolvedToken(for: role) == token {
                                Spacer(minLength: 8)
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text("Mapped to")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(themeManager.textSecondary)

                    Text(themeManager.resolvedToken(for: role).title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.textPrimary)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(themeManager.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(themeManager.surfaceElevated, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct DevelopmentThemeTokenRow: View {
    @Environment(ThemeManager.self) private var themeManager

    let token: ThemeColorToken

    @State private var draftHex: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 42, height: 42)
                    .background(themeManager.color(token), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(token.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(themeManager.textPrimary)

                    Text(token.usage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(themeManager.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if themeManager.hasColorOverride(for: token) {
                    Button("Reset") {
                        themeManager.clearColorOverride(for: token)
                        draftHex = themeManager.resolvedHex(for: token)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(themeManager.dangerPrimary)
                }
            }

            HStack(spacing: 10) {
                TextField("#RRGGBB", text: $draftHex)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(themeManager.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(themeManager.surfaceElevated, in: Capsule(style: .continuous))
                    .onChange(of: draftHex) { _, newValue in
                        if let normalizedHex = normalizedHex(newValue) {
                            themeManager.setColorHexOverride(normalizedHex, for: token)
                            draftHex = normalizedHex
                        }
                    }

                Text("Default \(themeManager.defaultHex(for: token))")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(themeManager.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
            }
        }
        .onAppear {
            draftHex = themeManager.resolvedHex(for: token)
        }
        .onChange(of: themeManager.resolvedHex(for: token)) { _, newValue in
            if draftHex != newValue {
                draftHex = newValue
            }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { themeManager.color(token) },
            set: { newColor in
                themeManager.setColorOverride(newColor, for: token)
                draftHex = themeManager.resolvedHex(for: token)
            }
        )
    }

    private func normalizedHex(_ value: String) -> String? {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "#", with: "")

        guard trimmed.count == 6 || trimmed.count == 8 else { return nil }
        guard CharacterSet(charactersIn: trimmed).isSubset(of: CharacterSet(charactersIn: "0123456789ABCDEF")) else {
            return nil
        }

        return "#\(trimmed)"
    }
}

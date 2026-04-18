//
//  DevelopmentThemeStudioView.swift
//  QuizFlash
//
//  Screen-first live theme editor for core app screens.
//

import SwiftUI

struct DevelopmentThemeStudioView: View {
    @Environment(ThemeManager.self) private var themeManager

    @State private var selectedScreenID: ThemeStudioScreenID = .home
    @State private var searchText = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                screenPickerSection
                searchSection
                selectedScreenSummarySection
                componentSection
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

    private var selectedScreen: ThemeStudioScreenDescriptor {
        ThemeStudioCatalog.screen(selectedScreenID)
    }

    private var normalizedSearch: String {
        searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var filteredComponents: [ThemeStudioComponentDescriptor] {
        selectedScreen.components.filter(matches(component:))
    }

    private var screenPickerSection: some View {
        SettingsSectionCard(
            title: "Screens",
            subtitle: "Pick a real app screen first. Each component card below shows the exact Swift type plus the live color inputs that shape it."
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ThemeStudioScreenID.allCases) { screenID in
                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                selectedScreenID = screenID
                            }
                        } label: {
                            Text(screenID.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(
                                    screenID == selectedScreenID
                                        ? themeManager.roleColor(.labelPrimaryForeground)
                                        : themeManager.roleColor(.labelSurfaceForeground)
                                )
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(
                                    screenID == selectedScreenID
                                        ? themeManager.roleColor(.labelPrimaryFill)
                                        : themeManager.roleColor(.labelSurfaceFill),
                                    in: Capsule(style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var searchSection: some View {
        SettingsSectionCard(
            title: selectedScreen.title,
            subtitle: "Search by Swift type name, location note, slot name, or token."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(themeManager.textSecondary)

                    TextField("Search inside \(selectedScreen.title)", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(themeManager.textPrimary)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(themeManager.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(themeManager.surfaceSecondary, in: Capsule(style: .continuous))

                HStack(spacing: 8) {
                    ThemeStudioLegendPill(text: "\(filteredComponents.count) components")
                    ThemeStudioLegendPill(text: themeManager.hasThemeOverrides ? "Overrides active" : "Default mapping")
                }
            }
        }
    }

    private var selectedScreenSummarySection: some View {
        SettingsSectionCard(
            title: "How To Read This Screen",
            subtitle: "Every card is a real Swift view. Every row is a live color slot bound either to a semantic role or directly to a palette token."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ThemeStudioGuideLine(
                    title: "Swift type name",
                    detail: "The primary label is the real component name from code."
                )
                ThemeStudioGuideLine(
                    title: "Shared badge",
                    detail: "If a component or slot is reused, edits propagate to all screens that consume the same shared primitive."
                )
                ThemeStudioGuideLine(
                    title: "Token + hex",
                    detail: "Remap the slot to a different token or recolor the current token inline. Changes apply live and persist."
                )
            }
        }
    }

    private var componentSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
            if filteredComponents.isEmpty {
                SettingsSectionCard(
                    title: "No Results",
                    subtitle: "Nothing on this screen matches the current search."
                ) {
                    Text("Try a Swift type name such as `LibraryDeckListRow`, a slot name like `backgroundFill`, or a token such as `BrandPrimary`.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(themeManager.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(filteredComponents) { component in
                    ThemeStudioComponentCard(
                        screenID: selectedScreenID,
                        component: component
                    )
                }
            }
        }
    }

    private func matches(component: ThemeStudioComponentDescriptor) -> Bool {
        guard !normalizedSearch.isEmpty else { return true }

        let tokenTitles = component.slots
            .map { themeManager.resolvedToken(for: $0.bindingTarget).title }
            .joined(separator: " ")

        let bindingTitles = component.slots
            .map(\.bindingTarget.title)
            .joined(separator: " ")

        let slotNames = component.slots
            .map(\.name)
            .joined(separator: " ")

        let slotNotes = component.slots
            .compactMap(\.note)
            .joined(separator: " ")

        let linkedScreens = ThemeStudioCatalog.linkedScreenIDs(for: component.componentKindID)
            .map(\.title)
            .joined(separator: " ")

        let haystack = [
            component.swiftTypeName,
            component.note,
            slotNames,
            slotNotes,
            tokenTitles,
            bindingTitles,
            linkedScreens
        ]
            .joined(separator: " ")
            .lowercased()

        return haystack.contains(normalizedSearch)
    }
}

private struct ThemeStudioComponentCard: View {
    @Environment(ThemeManager.self) private var themeManager

    let screenID: ThemeStudioScreenID
    let component: ThemeStudioComponentDescriptor

    private var relatedScreens: [ThemeStudioScreenID] {
        ThemeStudioCatalog.linkedScreenIDs(for: component.componentKindID)
            .filter { $0 != screenID }
    }

    var body: some View {
        SettingsSectionCard(
            title: component.swiftTypeName,
            subtitle: component.note
        ) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                if !relatedScreens.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shared Consumers")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(themeManager.textSecondary)

                        FlowLayout(spacing: 8) {
                            ThemeStudioLegendPill(text: "Shared")
                            ForEach(relatedScreens) { relatedScreen in
                                ThemeStudioLegendPill(text: relatedScreen.title)
                            }
                        }
                    }
                }

                ForEach(Array(component.slots.enumerated()), id: \.element.id) { index, slot in
                    ThemeStudioSlotRow(
                        slot: slot,
                        componentKindID: component.componentKindID,
                        currentScreenID: screenID
                    )

                    if index < component.slots.count - 1 {
                        SettingsCardDivider()
                    }
                }
            }
        }
    }
}

private struct ThemeStudioSlotRow: View {
    @Environment(ThemeManager.self) private var themeManager

    let slot: ThemeStudioColorSlotDescriptor
    let componentKindID: String
    let currentScreenID: ThemeStudioScreenID

    @State private var draftHex = ""

    private var relatedScreens: [ThemeStudioScreenID] {
        ThemeStudioCatalog.linkedScreenIDs(for: componentKindID)
            .filter { $0 != currentScreenID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 40, height: 40)
                    .background(themeManager.resolvedColor(for: slot.bindingTarget), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(slot.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(themeManager.textPrimary)

                    if let note = slot.note {
                        Text(note)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(themeManager.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    FlowLayout(spacing: 8) {
                        ThemeStudioLegendPill(text: themeManager.resolvedToken(for: slot.bindingTarget).title)

                        if slot.isShared {
                            ThemeStudioLegendPill(text: "Shared slot")
                        }

                        if !themeManager.canRemap(slot.bindingTarget) {
                            ThemeStudioLegendPill(text: "Direct token")
                        }
                    }

                    if !relatedScreens.isEmpty {
                        Text("Also visible in \(relatedScreens.map(\.title).joined(separator: ", "))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(themeManager.textSecondary)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                if themeManager.canRemap(slot.bindingTarget) {
                    Menu {
                        ForEach(ThemeColorToken.allCases) { token in
                            Button {
                                themeManager.setBindingOverride(token, for: slot.bindingTarget)
                            } label: {
                                HStack {
                                    Text(token.title)
                                    if themeManager.resolvedToken(for: slot.bindingTarget) == token {
                                        Spacer(minLength: 8)
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Remap")
                                .font(.caption.weight(.bold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(themeManager.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(themeManager.surfaceSecondary, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                TextField("#RRGGBB", text: $draftHex)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(themeManager.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(themeManager.surfaceSecondary, in: Capsule(style: .continuous))
                    .onChange(of: draftHex) { _, newValue in
                        if let normalizedHex = normalizedHex(newValue) {
                            themeManager.setColorHexOverride(normalizedHex, for: slot.bindingTarget)
                            draftHex = normalizedHex
                        }
                    }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text("Current \(themeManager.resolvedHex(for: slot.bindingTarget))")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(themeManager.textSecondary)

                Text("Default \(themeManager.defaultHex(for: slot.bindingTarget))")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(themeManager.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if themeManager.hasBindingOverride(for: slot.bindingTarget) {
                    Button("Reset Mapping") {
                        themeManager.clearBindingOverride(for: slot.bindingTarget)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(themeManager.highlightWarm)
                }

                if themeManager.hasColorOverride(for: slot.bindingTarget) {
                    Button("Reset Color") {
                        themeManager.clearColorOverride(for: slot.bindingTarget)
                        draftHex = themeManager.resolvedHex(for: slot.bindingTarget)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(themeManager.dangerPrimary)
                }
            }
        }
        .onAppear {
            draftHex = themeManager.resolvedHex(for: slot.bindingTarget)
        }
        .onChange(of: themeManager.resolvedHex(for: slot.bindingTarget)) { _, newValue in
            if draftHex != newValue {
                draftHex = newValue
            }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { themeManager.resolvedColor(for: slot.bindingTarget) },
            set: { newColor in
                themeManager.setColorOverride(newColor, for: slot.bindingTarget)
                draftHex = themeManager.resolvedHex(for: slot.bindingTarget)
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

private struct ThemeStudioGuideLine: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(themeManager.textPrimary)

            Text(detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(themeManager.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ThemeStudioLegendPill: View {
    @Environment(ThemeManager.self) private var themeManager

    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(themeManager.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(themeManager.surfaceSecondary, in: Capsule(style: .continuous))
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: spacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
